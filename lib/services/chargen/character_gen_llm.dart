// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../character_gen_service.dart';

extension GenLlm on CharacterGenService {
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
  Future<String?> _callLLM(
    String prompt, {
    int maxLen = 8192,
    int minLen = 64,
    int maxRetries = 3,
    bool isJsonMode = false,
    void Function(String accumulated)? onProgress,
  }) async {
    final int myEpoch = _generationEpoch;
    final promptEstTokens = (prompt.length / 4).ceil();
    debugPrint(
      'CharacterGen: Prompt size: ${prompt.length} chars (~$promptEstTokens tokens), maxLen: $maxLen',
    );
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (_aborted || _generationEpoch != myEpoch) {
        debugPrint('CharacterGen: Aborting before attempt $attempt');
        return null;
      }

      String accumulated = '';
      int tokenCount = 0;
      bool repetitionDetected = false;
      try {
        if (_llmService is KoboldService) {
          await _llmService.ensureServerIdle();
        }
        if (_aborted || _generationEpoch != myEpoch) return null;

        final stops = ['<END>', '</END>'];
        // NOTE: We intentionally do NOT add '}\n' as a stop sequence for
        // JSON mode. Character cards use {{char}} and {{user}} template
        // markers — the API matches }\n inside }}\n and truncates the
        // output. JSON completion is handled by the balanced brace checker.

        await for (final token in _llmService.generateStream(
          GenerationParams(
            prompt: prompt,
            maxLength: maxLen,
            minLength: minLen,
            temperature: isJsonMode ? 0.7 : 0.85,
            repeatPenalty: 1.15,
            minP: 0.05,
            topP: isJsonMode ? 0.90 : 0.95,
            reasoningEnabled: _reasoningEnabled,
            stopSequences: stops,
          ),
        )) {
          if (_aborted || _generationEpoch != myEpoch) {
            _llmService.abortGeneration();
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

          if (isJsonMode) {
            // Strip think blocks (fuzzy — models misspell <think> at high temp)
            final tOpen = r'<(?:think|thinking|thnk|thik|tink|thin|hink|ink)>';
            final tClose =
                r'</(?:think|thinking|thnk|thik|tink|thin|hink|ink)>';
            final stripped = accumulated
                .replaceAll(
                  RegExp(tOpen + r'[\s\S]*?' + tClose, caseSensitive: false),
                  '',
                )
                .replaceAll(
                  RegExp(tOpen + r'[\s\S]*$', caseSensitive: false),
                  '',
                )
                .trim();
            if (stripped.startsWith('{')) {
              int depth = 0;
              bool inString = false;
              bool complete = false;
              for (int ci = 0; ci < stripped.length; ci++) {
                final ch = stripped[ci];
                if (ch == '"' && (ci == 0 || stripped[ci - 1] != '\\')) {
                  inString = !inString;
                } else if (!inString) {
                  if (ch == '{') {
                    // Skip doubled {{ (template markers like {{char}})
                    if (ci + 1 < stripped.length && stripped[ci + 1] == '{') {
                      ci++; // skip the second {
                      continue;
                    }
                    depth++;
                  } else if (ch == '}') {
                    // Skip doubled }} (template markers like {{char}})
                    if (ci + 1 < stripped.length && stripped[ci + 1] == '}') {
                      ci++; // skip the second }
                      continue;
                    }
                    depth--;
                    if (depth == 0) {
                      complete = true;
                      break;
                    }
                  }
                }
              }
              if (complete) break;
            }
          }

          if (onProgress != null) {
            String preview = accumulated;
            // Fuzzy think-tag stripping for preview
            final tO = r'<(?:think|thinking|thnk|thik|tink|thin|hink|ink)>';
            final tC = r'</(?:think|thinking|thnk|thik|tink|thin|hink|ink)>';
            preview = preview.replaceAll(RegExp(tO + r'[\s\S]*?' + tC), '');
            preview = preview.replaceAll(RegExp(tO + r'[\s\S]*$'), '');
            onProgress(preview.trim());
          }
        }

        if (_aborted || _generationEpoch != myEpoch) return null;

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
        if (_aborted || _generationEpoch != myEpoch) return null;
        debugPrint(
          'CharacterGen: LLM error on attempt $attempt/$maxRetries: $e',
        );
      }

      // Wait before retrying (exponential backoff: 2s, 4s, 8s)
      if (attempt < maxRetries) {
        final delay = Duration(seconds: 2 * (1 << (attempt - 1)));
        debugPrint('CharacterGen: Retrying in ${delay.inSeconds}s...');
        onProgress?.call(
          '[Retrying in ${delay.inSeconds}s... (attempt ${attempt + 1}/$maxRetries)]',
        );
        final deadline = DateTime.now().add(delay);
        while (DateTime.now().isBefore(deadline)) {
          if (_aborted || _generationEpoch != myEpoch) return null;
          await Future.delayed(const Duration(milliseconds: 250));
        }
        onProgress?.call(''); // Clear retry message
      }
    }

    debugPrint('CharacterGen: All $maxRetries attempts failed');
    return null;
  }
}
