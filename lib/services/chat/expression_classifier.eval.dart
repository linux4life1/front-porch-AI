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

part of 'expression_classifier.dart';

/// LLM reclass + ONNX classify for [ExpressionService].
extension ExpressionServiceEval on ExpressionService {
  /// Fire-and-forget: ask the LLM to map an unknown emotion word to a standard label.
  /// Uses JSON output so thinking models can reason first then return the label.
  Future<void> _reclassifyEmotionAsync(String unknownEmotion) async {
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
        _cachedExpressionLabel = extractedLabel;
        onNotify();
      } else {
        debugPrint(
          '[Expression] reclassify: label "$extractedLabel" not valid, using neutral',
        );
      }
    } catch (e) {
      debugPrint('[Expression] reclassify error: $e');
    }
  }

  /// Fire-and-forget: classify emotion using ONNX model.
  /// Uses the last AI message text as classification input.
  Future<void> _classifyWithOnnxAsync(String emotion) async {
    if (_expressionClassifierService == null) {
      initExpressionClassifier();
    }
    if (_expressionClassifierService == null) return;

    _onnxClassifying = true;
    _lastOnnxMessageCount = getMessages().length;
    _lastOnnxMessageText =
        getMessages().isNotEmpty && !getMessages().last.isUser
        ? getMessages().last.text
        : '';
    stdout.writeln(
      '>>> [CHAT:ONNX] Starting classification for message count: $_lastOnnxMessageCount',
    ); // verbatim from original (for >>> marker visibility in logs; dart:io import for this only; no change for mechanical fidelity)
    try {
      // Initialize classifier with current mode
      await _expressionClassifierService!.ensureInitialized(
        getCurrentEmotion: getCharacterEmotion,
        reclassify: (unknown) async {
          return 'neutral';
        },
      );

      // Use last AI message text for classification
      String text = '';
      for (int i = getMessages().length - 1; i >= 0; i--) {
        if (!getMessages()[i].isUser && getMessages()[i].text.isNotEmpty) {
          text = getMessages()[i].text;
          break;
        }
      }
      // Reasoning models leave their <think> block in the stored message
      // text — classify the character's prose, not the meta-reasoning.
      text = stripThinkTags(text);
      if (text.isEmpty) text = emotion;

      final result = await _expressionClassifierService!.classify(text);
      if (result != null) {
        final label = result.emotion.toLowerCase();
        if (EmotionLabels.all.contains(label)) {
          debugPrint(
            '[Expression:ONNX] emotion=$emotion -> label=$label (confidence: ${result.confidence})',
          );
          _onnxExpressionLabel = label;
          _onnxCachedForEmotion = emotion;
          onNotify();
          return;
        }
      }
      // Fallback
      _onnxExpressionLabel = 'neutral';
      _onnxCachedForEmotion = emotion;
      onNotify();
      // cancel check only reached on fallback path due to early return on valid ONNX result (preserves original try/early-return/fallback placement); finally only clears classifying flag
      if (getRealismEvalCancelled()) {
        await onHandleRealismEvalCancelledDuringOnnx();
        return;
      }
    } catch (e) {
      debugPrint('[Expression:ONNX] classification error: $e');
      _onnxExpressionLabel = 'neutral';
      _onnxCachedForEmotion = emotion;
      onNotify();
    } finally {
      _onnxClassifying = false;
    }
  }
}
