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

import 'package:front_porch_ai/services/chat/eval_traffic.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/services.dart';

/// The objectives' one door to the model: native tool calls first through
/// the same `fireStructuredEval` fork TimeService and the Realism judges
/// use, the streamed text floor otherwise. Step generation and the goal sync
/// both go through it.
class ObjectiveEvalDoor {
  ObjectiveEvalDoor({
    required this.getLlmService,
    required this.stripThinkBlocks,
    this.fireToolEval,
    this.probe,
    this.getBackendIdentity,
    this.getPreferTextEvals,
  });

  final LLMService Function() getLlmService;
  final String Function(String) stripThinkBlocks;

  /// Null = text only (dedicated tests that never wired the probe).
  final Object? fireToolEval;
  final ToolTransportProbe? probe;
  final String Function()? getBackendIdentity;
  final bool Function()? getPreferTextEvals;

  Future<String> fire({
    required String debugLabel,
    required List<Map<String, dynamic>> tools,
    required String toolName,
    required String trafficLabel,
    required double temperature,
    required String Function({required bool toolsMode}) buildPrompt,
    required String? Function(List<LlmToolCall> calls) callToText,
    bool reasoningOff = false,
    LlmRequestCancel? cancel,
  }) async {
    Future<String?> fireText(
      String prompt, {
      void Function(String)? onChunk,
    }) async {
      final llm = getLlmService();
      if (!llm.isReady) return null;
      final params = GenerationParams(
        prompt: prompt,
        maxLength: 2000,
        temperature: temperature,
        reasoningEnabled: false,
        reasoningMaxTokens: reasoningOff ? 0 : null,
        mandatoryReasoningHeadroom: true,
        stopSequences: const [],
        cancel: cancel,
      );
      final watch = Stopwatch()..start();
      var responseText = '';
      await for (final chunk in llm.generateStream(params)) {
        responseText += chunk;
      }
      EvalTraffic.current.record(
        label: trafficLabel,
        lane: 'raw',
        promptChars: params.prompt.length,
        outputChars: responseText.length,
        ms: watch.elapsedMilliseconds,
      );
      return responseText;
    }

    final raw = fireToolEval != null && probe != null
        ? await fireStructuredEval(
            probe: probe!,
            backendIdentity: getBackendIdentity?.call() ?? '',
            debugLabel: debugLabel,
            tools: tools,
            buildPrompt: buildPrompt,
            callToText: (resp) => callToText(resp.calls),
            fireToolEval: fireToolEval!,
            fireTextEval: fireText,
            toolChoice: toolName,
            maxLength: 2000,
            getPreferTextEvals: getPreferTextEvals,
            cancel: cancel,
            isCancelled: () => cancel?.isCancelled ?? false,
          )
        : await fireText(buildPrompt(toolsMode: false));
    return stripThinkBlocks(raw ?? '');
  }
}
