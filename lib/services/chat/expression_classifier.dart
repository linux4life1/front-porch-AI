// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/avatar_image.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/avatar_gallery.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/expression_classifier.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';
import 'package:front_porch_ai/utils/think_tags.dart';

/// Plain (non-ChangeNotifier) domain service owning the chat-scoped expression
/// label selection state machine, manual override, avatar resolution (with
/// random + lastId reroll avoidance), LLM reclassification, ONNX cache/debounce/
/// classify wiring, and related caches.
///
/// ChatService owns the instance via a private late final and delegates. All
/// cross state (isEvaluatingRealism guard, LLM for reclass stream + isThinking,
/// storage for mode, isGenerating for ONNX stability, current emotion, messages
/// for last-AI text + count, and the special realism-cancel-during-onnx path)
/// is accessed exclusively via 13 callbacks (onNotify + onSaveChat + 11 granular get*/set*/on*) supplied at construction (4 of which for the cancel cross). This keeps
/// the extracted service testable and avoids cycles. (Granular callbacks chosen
/// over a full parent interface ref for this leaf extraction per the Stage 3
/// precedent in needs/chaos/relationship and updated plan guidance in
/// refactoring-guide.md.)
///
/// The low-level ExpressionClassifierService (LLM/ONNX/manual mode manager +
/// sidecar) remains in lib/services/expression_classifier.dart and is owned/
/// initialized here for the chat's use. The top-level service is wired from
/// main.dart via the (deprecated) shim on ChatService.
///
/// Extraction is mechanical: original fields, the large currentExpressionLabel
/// getter (manual priority, ONNX stability+debounce+trigger+cache, LLM map +
/// reclass trigger), resolveExpressionAvatar (prime fallback, neutral fallback,
/// multi match random with optional reroll avoiding lastId), setManual,
/// reclassifyEmotion public, init, setService, _reclassifyEmotionAsync (full
/// stream + json/think extract + notify), _classifyWithOnnxAsync (debounce,
/// ensure, last AI pick, classify, fallback, notify + the cancel block),
/// the regen onnx invalidate, and reset/invalidate helpers copied/adapted.
///
/// Group vs 1:1 parity preserved exactly for expression: expression label/avatar
/// computation is not per-speaker (unlike relationship/needs); it derives from
/// the current _characterEmotion scalar (which the owner loads/swaps via
/// _loadGroupRealismIntoScalars / _save... for the active speaker during
/// impersonation/group turns). Manual override and ONNX caches are chat-scoped
/// (shared). When owner switches speaker emotion, currentExpressionLabel +
/// resolve behave identically to 1:1. No per-speaker expression label storage
/// was present originally.
///
/// UI-coordination (command handling kept thin in god), prompt injection
/// (expression label lists for _get*Injection) and some context using emotion
/// stay in ChatService (to be thinned in step 8 prompt_injection subdir).
/// @Deprecated shims on ChatService preserve the public surface used by
/// external callers (chat_page.dart for current/resolve; main for setService;
/// reclassify/manual for API + tests): currentExpressionLabel,
/// manualExpressionLabel, resolveExpressionAvatar, reclassifyEmotion.
///
/// Reset helper (resetForFreshChat) + invalidate helper support the documented
/// "keep reset blocks in sync" sites and regen paths in parent without adding
/// private helpers to the god file.
///
/// 0 new private methods added to ChatService as part of this step (thins +
/// delegations only; deletions of moved code are mandatory part of the task).
class ExpressionService {
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;

  // Callbacks for parent-owned cross-domain state (realism guard for reclass,
  // LLM for async reclass stream + thinking mode, storage for onnx mode,
  // generating for onnx keep-prior, emotion for onnx ensure/classify fallback,
  // messages for onnx last-AI text + count + label messageCount check).
  // These remain in ChatService until their owning domains are extracted later.
  final bool Function() getIsEvaluatingRealism;
  final StorageService Function() getStorageService;
  final LLMService Function() getLlmServiceForReclass;
  final bool Function() getIsGenerating;
  final String Function() getCharacterEmotion;
  final List<ChatMessage> Function() getMessages;
  final bool Function() getIsThinkingModelForReclass;

  // Special cbs for the cancel-during-onnx block that was inside the original
  // _classifyWithOnnxAsync (uses messages + save + flags + notify). Kept
  // granular so leaf can own the classify without owning god realism flags.
  final bool Function() getRealismEvalCancelled;
  final void Function(bool) setRealismEvalCancelled;
  final void Function(bool) setIsEvaluatingRealism;
  final Future<void> Function() onHandleRealismEvalCancelledDuringOnnx;

  // Owned simulation state (moved verbatim from ChatService).
  String? _lastExpressionAvatarId;
  String? _manualExpressionLabel;
  final Random _expressionRandom = Random();
  String? _cachedExpressionLabel;
  String? _cachedForEmotion;

  // ONNX expression classification
  ExpressionClassifierService? _expressionClassifierService;
  String? _onnxExpressionLabel;
  String? _onnxCachedForEmotion;
  int _lastOnnxMessageCount = 0;
  String? _lastOnnxMessageText;
  bool _onnxClassifying = false;
  Timer? _onnxDebounce;

  // Tools transport for the LLM reclassify (nullable — tests and tool-less
  // hosts stay on the text path; the god wires the shared probe/door the
  // other structured evals use).
  final Future<LlmToolResponse?> Function(
    String prompt,
    List<Map<String, dynamic>> tools,
  )?
  fireToolEval;
  final ToolTransportProbe? probe;
  final String Function()? getBackendIdentity;

  ExpressionService({
    required this.onNotify,
    required this.onSaveChat,
    required this.getIsEvaluatingRealism,
    required this.getStorageService,
    required this.getLlmServiceForReclass,
    required this.getIsGenerating,
    required this.getCharacterEmotion,
    required this.getMessages,
    required this.getIsThinkingModelForReclass,
    required this.getRealismEvalCancelled,
    required this.setRealismEvalCancelled,
    required this.setIsEvaluatingRealism,
    required this.onHandleRealismEvalCancelledDuringOnnx,
    this.fireToolEval,
    this.probe,
    this.getBackendIdentity,
  });

  // ── Public surface (for @Deprecated shims in ChatService + direct test/UI callers) ──────

  String? get manualExpressionLabel => _manualExpressionLabel;

  /// Returns the standard expression label for the current emotion.
  ///
  /// If a manual expression is set via [setManualExpression], returns that.
  /// When classification mode is 'onnx', uses the ONNX classifier result.
  /// Otherwise maps the nuanced emotion to a standard label
  /// using [EmotionLabels.nuancedToStandard].
  String? get currentExpressionLabel {
    // Manual override takes priority
    if (_manualExpressionLabel != null && _manualExpressionLabel!.isNotEmpty) {
      return _manualExpressionLabel!.toLowerCase();
    }

    final lower = getCharacterEmotion().toLowerCase();
    final messageCount = getMessages().length;

    final lastAiMsgText = getMessages().isNotEmpty && !getMessages().last.isUser
        ? getMessages().last.text
        : '';

    // ONNX mode: trigger classification if needed and return cached result
    if (getStorageService().expressionSettings.expressionClassificationMode ==
        'onnx') {
      // ── STABILITY: Keep previous expression while generating ───────────────
      // As requested, we don't want "live" updates. We keep the current
      // face until the message is complete.
      if (getIsGenerating()) {
        return _onnxExpressionLabel ??
            EmotionLabels.nuancedToStandard[lower] ??
            'neutral';
      }

      // Trigger async ONNX classification if a new message arrived, text changed, or emotion changed
      if ((_onnxCachedForEmotion != lower ||
              messageCount != _lastOnnxMessageCount ||
              lastAiMsgText != _lastOnnxMessageText) &&
          !_onnxClassifying &&
          _onnxDebounce == null) {
        // Use a small debounce to avoid rapid re-triggering during UI transitions
        _onnxDebounce = Timer(const Duration(milliseconds: 500), () {
          _onnxDebounce = null;
          _classifyWithOnnxAsync(lower);
        });
      }

      if (_onnxCachedForEmotion == lower && _onnxExpressionLabel != null) {
        return _onnxExpressionLabel;
      }
      return _onnxExpressionLabel ??
          EmotionLabels.nuancedToStandard[lower] ??
          'neutral';
    }

    if (getCharacterEmotion().isEmpty) return 'neutral';

    // Return cached label if emotion hasn't changed
    if (_cachedForEmotion == lower && _cachedExpressionLabel != null) {
      return _cachedExpressionLabel;
    }

    // Direct match
    if (EmotionLabels.all.contains(lower)) {
      debugPrint('[Expression] emotion=$lower -> label=$lower (direct match)');
      _cachedForEmotion = lower;
      _cachedExpressionLabel = lower;
      return lower;
    }

    // Nuanced mapping
    final mapped = EmotionLabels.nuancedToStandard[lower];
    if (mapped != null) {
      debugPrint(
        '[Expression] emotion=$lower -> label=$mapped (nuanced mapping)',
      );
      _cachedForEmotion = lower;
      _cachedExpressionLabel = mapped;
      return mapped;
    }

    // Unmapped — trigger LLM re-classification
    debugPrint(
      '[Expression] emotion=$lower -> UNMAPPED, triggering LLM re-classification',
    );
    _reclassifyEmotionAsync(lower);
    _cachedForEmotion = lower;
    _cachedExpressionLabel = 'neutral';
    return 'neutral';
  }

  /// Resolves the best matching expression avatar for the given character.
  ///
  /// Returns the [AvatarImage] to display, or null if no expression images
  /// are available. Uses [currentExpressionLabel] for matching.
  ///
  /// If [rerollIfSame] is true and multiple avatars share the same label,
  /// a random one is picked (avoiding the previously shown avatar).
  AvatarImage? resolveExpressionAvatar(
    CharacterCard character, {
    bool rerollIfSame = false,
  }) {
    // Gallery "looks" are stored as avatar rows too — filter them out so a look
    // can never be chosen (or counted) as an emotion face.
    final avatars = expressionsFrom(character.avatarImages);
    if (avatars.isEmpty) {
      return null;
    }

    final label = currentExpressionLabel;
    if (label == null) {
      return avatars
              .where((a) => a.displayOrder + 1 == character.primeAvatarIndex)
              .isEmpty
          ? avatars.first
          : avatars.firstWhere(
              (a) => a.displayOrder + 1 == character.primeAvatarIndex,
            );
    }

    // Find all avatars matching the current emotion label
    final matches = avatars
        .where((a) => a.label?.toLowerCase() == label)
        .toList();

    if (matches.isEmpty) {
      // Fallback: try neutral, then prime avatar
      final neutral = avatars
          .where((a) => a.label?.toLowerCase() == 'neutral')
          .toList();
      if (neutral.isNotEmpty) {
        return neutral.first;
      }
      return avatars
              .where((a) => a.displayOrder + 1 == character.primeAvatarIndex)
              .isEmpty
          ? avatars.first
          : avatars.firstWhere(
              (a) => a.displayOrder + 1 == character.primeAvatarIndex,
            );
    }

    if (matches.length == 1) {
      return matches.first;
    }

    // Multiple matches — pick randomly, optionally avoiding the last one shown
    if (rerollIfSame && _lastExpressionAvatarId != null) {
      final different = matches
          .where((a) => a.id != _lastExpressionAvatarId)
          .toList();
      if (different.isNotEmpty) {
        final picked = different[_expressionRandom.nextInt(different.length)];
        _lastExpressionAvatarId = picked.id;
        return picked;
      }
    }

    final picked = matches[_expressionRandom.nextInt(matches.length)];
    _lastExpressionAvatarId = picked.id;
    return picked;
  }

  /// Manually set an expression label (e.g., from /expression-set command).
  /// Pass null to clear the manual override and resume auto-detection.
  void setManualExpression(String? label) {
    _manualExpressionLabel = label;
    _lastExpressionAvatarId = null;
    onNotify();
  }

  Future<String> reclassifyEmotion(String unknownEmotion) async {
    _reclassifyEmotionAsync(unknownEmotion);
    // Fire-and-forget (side effects + notify happen inside _reclassify... async); return value is the pre-extraction shim contract (always neutral immediate)
    return 'neutral';
  }

  /// Initialize the ONNX expression classifier service.
  void initExpressionClassifier() {
    _expressionClassifierService ??= ExpressionClassifierService(
      getStorageService(),
    );
  }

  /// Set the ExpressionClassifierService (for ONNX).
  void setExpressionClassifierService(ExpressionClassifierService service) {
    _expressionClassifierService = service;
  }

  // ── Reset / seed / load helpers (support "keep reset blocks in sync" in parent) ──

  void resetForFreshChat() {
    _manualExpressionLabel = null;
    _lastExpressionAvatarId = null;
    _cachedExpressionLabel = null;
    _cachedForEmotion = null;
    _onnxExpressionLabel = null;
    _onnxCachedForEmotion = null;
    _lastOnnxMessageCount = 0;
    _lastOnnxMessageText = null;
    _onnxClassifying = false;
    _onnxDebounce?.cancel();
    _onnxDebounce = null;
  }

  void invalidateOnnxCacheForNewResponse() {
    _onnxCachedForEmotion = null;
    _onnxExpressionLabel = null;
    _lastOnnxMessageText = null;
  }

  // ── Core logic (verbatim mechanical extraction) ───────────────────────────

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
          repeatPenalty: 1.15,
          reasoningEnabled: false,
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
