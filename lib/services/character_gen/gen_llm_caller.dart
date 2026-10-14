// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_state.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The one streaming LLM call every chargen stage makes, with retry,
/// degenerate-output detection, and abort checks against [GenRunState].
class GenLlmCaller {
  GenLlmCaller(this._state);

  final GenRunState _state;

  // ═════════════════════════════════════════════════════════════
  //  LLM Calling
  // ═════════════════════════════════════════════════════════════

  /// Call the LLM and collect all tokens. Returns raw text or null.
  /// Retries up to [maxRetries] times with exponential backoff on failure.
  ///
  /// [isJsonMode] — When true, adds `}\n` to stop sequences so the model halts
  /// the moment the JSON object closes (safe for thinking models: they think
  /// freely, then produce the JSON, then hit `}\n` and stop).
  /// [grammar] — Optional GBNF grammar string for KoboldCPP local + non-thinking
  /// backends. Pass null to skip (all API backends ignore this).
  Future<String?> call(
    String prompt, {
    int maxLen = 8192,
    int minLen = 64,
    int maxRetries = 3,
    bool isJsonMode = false,
    void Function(String accumulated)? onProgress,
  }) async {
    final int myEpoch = _state.generationEpoch;
    final llm = _state.llm;
    final promptEstTokens = (prompt.length / 4).ceil();
    String? lastError;
    debugPrint(
      'CharacterGen: Prompt size: ${prompt.length} chars (~$promptEstTokens tokens), maxLen: $maxLen',
    );
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (_state.isStale(myEpoch)) {
        debugPrint('CharacterGen: Aborting before attempt $attempt');
        return null;
      }

      String accumulated = '';
      int tokenCount = 0;
      bool repetitionDetected = false;
      try {
        if (llm is KoboldService) {
          // Wizard runs force the server idle (aborting a stuck/runaway
          // generation from a previous run). Background runs (Scene Guest
          // mint) WAIT instead — the server-side abort would kill a
          // background pass's eval mid-request, and a tools call cut down
          // that way returns an empty 200 that reads as "model can't speak
          // tools" (see generateCharacter's abortInFlight doc).
          _state.abortInFlight
              ? await llm.ensureServerIdle()
              : await llm.waitForIdle();
        }
        if (_state.isStale(myEpoch)) return null;

        final stops = ['<END>', '</END>'];
        // NOTE: We intentionally do NOT add '}\n' as a stop sequence for
        // JSON mode. Character cards use {{char}} and {{user}} template
        // markers — the API matches }\n inside }}\n and truncates the
        // output. JSON completion is handled by the balanced brace checker.

        await for (final token in llm.generateStream(
          GenerationParams(
            prompt: prompt,
            maxLength: maxLen,
            minLength: minLen,
            temperature: isJsonMode ? 0.7 : 0.85,
            repeatPenalty: 1.15,
            minP: 0.05,
            topP: isJsonMode ? 0.90 : 0.95,
            reasoningEnabled: _state.reasoningEnabled,
            // When reasoning is OFF, also pin the budget to 0. On oMLX/OpenRouter/
            // Nano-GPT the `reasoning:{enabled:false}` signal is only emitted when a
            // max_tokens is present (see OpenRouterService's payload guard); without
            // this, hybrid thinking models (Qwen3, DeepSeek, Kimi:thinking) fall back
            // to thinking-on and dump a <think> block into the output — which was
            // leaking straight into the portrait-prompt seed. Matches the convention
            // every other suppress path uses (evals, Continue, call mode). When the
            // user turns reasoning ON for generation, leave it null so the model
            // reasons normally.
            reasoningMaxTokens: _state.reasoningEnabled ? null : 0,
            // Silent mandatory-reasoners 200 `enabled:false` then think until
            // length with no content. Opt in so generateStream can learn +
            // retry once with think headroom while keeping exclude:true.
            mandatoryReasoningHeadroom: !_state.reasoningEnabled,
            stopSequences: stops,
          ),
        )) {
          if (_state.isStale(myEpoch)) {
            llm.abortGeneration();
            break;
          }
          accumulated += token;
          tokenCount++;

          // Degenerate output detection — fires every 50 tokens for fast catch.
          // Two strategies:
          //   1. Substring repeat: a 300-char tail appears earlier in the text
          //   2. Word-salad: low unique-word ratio (model spewing random words)
          if (tokenCount > 100 &&
              tokenCount % 50 == 0 &&
              accumulated.length > 400) {
            // Strategy 1: exact substring repeat
            final tail = accumulated.substring(accumulated.length - 300);
            final earlier = accumulated.substring(0, accumulated.length - 300);
            if (earlier.contains(tail)) {
              debugPrint(
                'CharacterGen: Repetition loop detected at token $tokenCount — aborting',
              );
              repetitionDetected = true;
              break;
            }

            // Strategy 2: unique word ratio in the last ~500 chars
            final recentText = accumulated.length > 500
                ? accumulated.substring(accumulated.length - 500)
                : accumulated;
            final words = recentText.toLowerCase().split(RegExp(r'\s+'));
            if (words.length > 20) {
              final uniqueRatio = words.toSet().length / words.length;
              if (uniqueRatio < 0.30) {
                debugPrint(
                  'CharacterGen: Word-salad detected at token $tokenCount '
                  '(unique ratio: ${(uniqueRatio * 100).toStringAsFixed(1)}%) — aborting',
                );
                repetitionDetected = true;
                break;
              }
            }
          }

          if (isJsonMode &&
              JsonSanitizer.hasCompleteObject(stripThinkBlocks(accumulated))) {
            break;
          }

          if (onProgress != null) {
            onProgress(stripThinkBlocks(accumulated));
          }
        }

        if (_state.isStale(myEpoch)) return null;

        debugPrint(
          'CharacterGen: Stream done. Tokens: $tokenCount, '
          'Raw: ${accumulated.length} chars${repetitionDetected ? ' (truncated due to repetition)' : ''}',
        );

        // Treat think-only output (nothing left after stripping <think>
        // blocks) as a failure so the retry loop can recover — otherwise the
        // caller cleans it to empty and the field (e.g. the first message) is
        // silently dropped.
        if (stripThinkBlocks(accumulated).isNotEmpty) return accumulated;

        // Empty / think-only response — retry with diagnostics
        debugPrint(
          'CharacterGen: Empty/think-only response on attempt $attempt/$maxRetries. '
          'Prompt ~$promptEstTokens tokens. If this exceeds your model\'s context window, '
          'try a shorter concept or reduce lore depth.',
        );
      } catch (e) {
        if (_state.isStale(myEpoch)) return null;
        if (e is SilentMandatoryReasoningStarveException) {
          debugPrint('CharacterGen: $e — failing this step (no more retries)');
          _state.lastFailure = '$e';
          return null;
        }
        lastError = '$e';
        debugPrint(
          'CharacterGen: LLM error on attempt $attempt/$maxRetries: $e',
        );
      }

      // Wait before retrying (exponential backoff: 2s, 4s, 8s)
      if (attempt < maxRetries) {
        final delay = _state.retryDelay(attempt);
        debugPrint('CharacterGen: Retrying in ${delay.inSeconds}s...');
        onProgress?.call(
          '[Retrying in ${delay.inSeconds}s... (attempt ${attempt + 1}/$maxRetries)]',
        );
        final deadline = DateTime.now().add(delay);
        while (DateTime.now().isBefore(deadline)) {
          if (_state.isStale(myEpoch)) return null;
          await Future.delayed(const Duration(milliseconds: 250));
        }
        onProgress?.call(''); // Clear retry message
      }
    }

    debugPrint('CharacterGen: All $maxRetries attempts failed');
    if (!_state.isStale(myEpoch)) {
      _state.lastFailure = lastError ?? 'The model sent back nothing.';
    }
    return null;
  }
}
