// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/llm_eval_engine.dart'
    show kScalarEvalRepeatPenalty;
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// LLM reclass for [ExpressionService]: maps an unknown emotion word to one
/// standard label through the shared tools-vs-text eval transport.
class ExpressionReclassifier {
  ExpressionReclassifier({
    required this.getIsEvaluatingRealism,
    required this.getLlmServiceForReclass,
    required this.getIsThinkingModelForReclass,
    this.fireToolEval,
    this.probe,
    this.getBackendIdentity,
  });

  final bool Function() getIsEvaluatingRealism;
  final LLMService Function() getLlmServiceForReclass;
  final bool Function() getIsThinkingModelForReclass;
  final Object? fireToolEval;
  final ToolTransportProbe? probe;
  final String Function()? getBackendIdentity;

  /// Fire-and-forget: ask the LLM to map an unknown emotion word to a standard label.
  /// Uses JSON output so thinking models can reason first then return the label.
  ///
  /// [onLabel] receives a valid standard label (inside the guarded call, so a
  /// throw from it is logged like any other reclassify error).
  Future<void> reclassify(
    String unknownEmotion, {
    required void Function(String label) onLabel,
  }) async {
    if (getIsEvaluatingRealism()) {
      debugPrint(
        '[Expression] reclassify: skipped — realism engine is evaluating',
      );
      return;
    }
    final llmService = getLlmServiceForReclass();
    if (!llmService.isReady) {
      debugPrint('[Expression] reclassify: LLM not ready, skipping');
      return;
    }

    try {
      final labels = EmotionLabels.all.join(', ');
      String buildPrompt({required bool toolsMode}) =>
          'Classify the emotion "$unknownEmotion" into exactly ONE of these labels: "$labels".\n'
          '${toolsMode ? 'Report by calling the $kExpressionTool tool with your choice as "label". Use ONLY the tool — no plain-text reply.' : 'Return ONLY a JSON object with one key "label" containing your choice.\n'
                    'Example: {"label": "surprise"}\n'
                    'Response:'}';

      // Determine if thinking model is in use (same logic as realism engine)
      final isThinkingModel = getIsThinkingModelForReclass();

      Future<String?> fireText(
        String prompt, {
        void Function(String)? onChunk,
      }) async {
        final params = GenerationParams(
          prompt: prompt,
          maxLength: isThinkingModel ? 2048 : 32,
          temperature: 0.1,
          topP: 0.5,
          repeatPenalty: kScalarEvalRepeatPenalty,
          reasoningEnabled: false,
          // Same as every other eval: without this the reasoning-disable
          // block is never sent to remote ":thinking" models and they reason
          // through a one-word classification (this was the one eval that
          // forgot the flag).
          reasoningMaxTokens: 0,
          mandatoryReasoningHeadroom: true,
          stopSequences: isThinkingModel ? [] : ['}\n', '}'],
        );
        final StringBuffer sb = StringBuffer();
        await for (final chunk in llmService.generateStream(params)) {
          sb.write(chunk);
        }
        return sb.toString().trim();
      }

      String response =
          (fireToolEval != null && probe != null
              ? await fireStructuredEval(
                  probe: probe!,
                  backendIdentity: getBackendIdentity?.call() ?? '',
                  debugLabel: kExpressionTool,
                  tools: kExpressionEvalTools,
                  buildPrompt: buildPrompt,
                  callToText: (resp) =>
                      realismToolCallToJson(kExpressionTool, resp.calls),
                  fireToolEval: fireToolEval!,
                  toolChoice: kExpressionTool,
                  fireTextEval: fireText,
                )
              : await fireText(buildPrompt(toolsMode: false))) ??
          '';
      debugPrint('[Expression] reclassify raw response: "$response"');

      // Extract JSON from response (handles thinking model output with <think> blocks)
      if (response.contains('```')) {
        final match = RegExp(
          r'```(?:json)?\s*\n?(.*?)\n?```',
          dotAll: true,
        ).firstMatch(response);
        if (match != null) {
          response = match.group(1)!.trim();
        }
      }

      // Find JSON object in response
      String jsonStr = response;
      if (!response.startsWith('{')) {
        final objMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(response);
        if (objMatch != null) {
          jsonStr = objMatch.group(0)!;
        }
      }

      String? extractedLabel;
      try {
        final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
        extractedLabel = (parsed['label'] as String?)?.trim().toLowerCase();
      } catch (e) {
        debugPrint('[Expression] reclassify JSON parse failed: $e');
      }

      if (extractedLabel != null &&
          EmotionLabels.all.contains(extractedLabel)) {
        debugPrint(
          '[Expression] reclassify: mapped "$unknownEmotion" -> "$extractedLabel"',
        );
        onLabel(extractedLabel);
      } else {
        debugPrint(
          '[Expression] reclassify: label "$extractedLabel" not valid, using neutral',
        );
      }
    } catch (e) {
      debugPrint('[Expression] reclassify error: $e');
    }
  }
}
