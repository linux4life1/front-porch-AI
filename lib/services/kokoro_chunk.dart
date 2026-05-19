// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Kokoro-safe text chunking.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/kokoro_debug.dart';
//
// The goal is to break user-provided text (especially long, stylized RP narration)
// into small, safe pieces that `kokoro.create()` can handle reliably, while
// preserving enough ordering information for correct audio reassembly.

/// A single piece of text to be synthesized by one Kokoro worker call.
///
/// `originalIndex` indicates the position of this chunk in the original
/// sequence of work submitted for the current utterance. This is used by
/// the ordered collector to ensure audio plays in the correct order even
/// when workers complete out of order.
class KokoroChunk {
  final int originalIndex;
  final String text;
  final String voice;
  final double speed;
  final String lang;
  final String outputPath;
  final String modelPath;
  final String voicesPath;

  const KokoroChunk({
    required this.originalIndex,
    required this.text,
    required this.voice,
    required this.speed,
    required this.lang,
    required this.outputPath,
    required this.modelPath,
    required this.voicesPath,
  });
}

/// Utility that turns raw text (or a list of sentences) into a list of
/// `KokoroChunk`s that are safe for `kokoro.create()`.
///
/// Key behaviors:
/// - Hard maximum length per chunk (~300 characters by default)
/// - Respects common RP-friendly boundaries (`. ! ? — … … *`)
/// - Never produces empty chunks
class KokoroChunker {
  /// Default target size for fixed-character chunking in "read everything" (verbatim) mode.
  /// Raised from 100 because Kokoro workers keep the model hot; larger chunks = far fewer
  /// audible pauses while still staying well under what the ONNX model can handle reliably.
  static const int verbatimChunkSize = 240;

  /// Splits the given text into safe `KokoroChunk` objects.
  ///
  /// [voice], [speed], [lang], [modelPath] and [voicesPath] are applied to every chunk.
  static List<KokoroChunk> split({
    required String text,
    required String voice,
    required double speed,
    required String lang,
    required String modelPath,
    required String voicesPath,
    String? outputPathPrefix,
    int maxChars = 450,
  }) {
    if (text.trim().isEmpty) return const [];

    final prefix = outputPathPrefix ?? 'kokoro_chunk';

    final rawParts = _smartSplit(text);

    final chunks = <KokoroChunk>[];
    int chunkCounter = 0;

    kDebugPrint('[KokoroChunker] Splitting text of length ${text.length} into chunks (max $maxChars chars)');

    for (final part in rawParts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.length <= maxChars) {
        final chunk = _makeChunk(
          index: chunkCounter++,
          text: trimmed,
          voice: voice,
          speed: speed,
          lang: lang,
          modelPath: modelPath,
          voicesPath: voicesPath,
          prefix: prefix,
        );
        if (trimmed.length < 25) {
          kDebugPrint('[KokoroChunker] ⚠️  Very small chunk created #${chunk.originalIndex} (len=${trimmed.length}): "${_preview(trimmed)}"');
        } else {
          kDebugPrint('[KokoroChunker] Created chunk #${chunk.originalIndex} (len=${trimmed.length}): "${_preview(trimmed)}"');
        }
        chunks.add(chunk);
      } else {
        final subChunks = _forceSplit(trimmed, maxChars);
        for (final sub in subChunks) {
          if (sub.trim().isNotEmpty) {
            final chunk = _makeChunk(
              index: chunkCounter++,
              text: sub.trim(),
              voice: voice,
              speed: speed,
              lang: lang,
              modelPath: modelPath,
              voicesPath: voicesPath,
              prefix: prefix,
            );
            if (sub.length < 25) {
              kDebugPrint('[KokoroChunker] ⚠️  Very small FORCED chunk #${chunk.originalIndex} (len=${sub.length}): "${_preview(sub)}"');
            } else {
              kDebugPrint('[KokoroChunker] Created chunk #${chunk.originalIndex} (len=${sub.length}, FORCED): "${_preview(sub)}"');
            }
            chunks.add(chunk);
          }
        }
      }
    }

    kDebugPrint('[KokoroChunker] Finished splitting → produced ${chunks.length} chunks');
    return chunks;
  }

  static String _preview(String text) {
    const max = 80;
    if (text.length <= max) return text;
    return text.substring(0, max) + '...';
  }

  /// Smarter split for stylized RP text (especially heavy dialogue + action).
  /// Goals:
  /// - Keep short back-and-forth dialogue together ("That's it." "Take it.")
  /// - Be conservative inside *action* blocks
  /// - Avoid creating tiny broken fragments
  static List<String> _smartSplit(String text) {
    // Primary split on strong sentence terminators
    final sentencePattern = RegExp(r'(?<=[.!?])\s+');
    final raw = text.split(sentencePattern);

    final parts = raw
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Merge very short consecutive pieces (very common in RP dialogue).
    // Keep merging as long as the accumulated chunk is still relatively short
    // and the next piece is also short. This is tuned for stylized RP.
    const targetMin = 40;   // Try to keep chunks at least this long when possible
    const hardMin = 25;     // Never leave a chunk shorter than this unless forced

    final merged = <String>[];
    int i = 0;

    while (i < parts.length) {
      String current = parts[i];
      i++;

      // Keep pulling in the next short piece if it helps us reach a sensible size
      while (i < parts.length) {
        final next = parts[i];
        if (next.length > 40) break; // next piece is substantial, stop merging

        final combinedLen = current.length + 1 + next.length; // +1 for space
        if (combinedLen < targetMin || (current.length < hardMin && combinedLen < 80)) {
          current = '$current $next';
          i++;
        } else {
          break;
        }
      }

      merged.add(current);
    }

    return merged;
  }

  /// Fixed-size character chunking for "read everything" (verbatim) mode.
  ///
  /// Unlike the normal sentence splitter, this one deliberately does **not** split on
  /// sentence boundaries so that long *action* blocks, internal monologues, and
  /// theatrical RP flow stay together. It only chops when it has to.
  ///
  /// The key quality improvement: inside a search window around the target size it
  /// strongly prefers natural prosody/breath points that Kokoro can intone well:
  ///   - End of spoken dialogue ("." or "!" or "?" followed by space/quote/*)
  ///   - Em-dashes and ellipses (— …)
  ///   - Action block edges (*)
  ///   - Clause breaks (, ; :)
  /// Only falls back to a plain word boundary if nothing better exists.
  ///
  /// This eliminates most of the "weird pauses every 100 chars" the user heard
  /// with the old naive implementation while still guaranteeing a hard cap so
  /// the persistent worker never receives a monster string.
  static List<KokoroChunk> splitFixedCharacterCount({
    required String text,
    required String voice,
    required double speed,
    required String lang,
    required String modelPath,
    required String voicesPath,
    String? outputPathPrefix,
    int chunkSize = verbatimChunkSize,
  }) {
    if (text.trim().isEmpty) return const [];

    final prefix = outputPathPrefix ?? 'kokoro_chunk';
    final chunks = <KokoroChunk>[];
    int index = 0;
    int start = 0;

    kDebugPrint('[KokoroChunker] Using smart fixed-character chunking (target ${chunkSize} chars) for verbatim mode');

    while (start < text.length) {
      if (start >= text.length) break;

      int idealEnd = start + chunkSize;
      int searchEnd = (idealEnd + 40).clamp(0, text.length); // small lookahead for better breaks

      int chosenEnd = text.length;

      if (idealEnd >= text.length) {
        chosenEnd = text.length;
      } else {
        // Build a search window [idealEnd-70 .. idealEnd+40]
        final windowStart = (idealEnd - 70).clamp(start + 20, text.length);
        final window = text.substring(windowStart, searchEnd);

        // Priority order for theatrical RP / long narration (best intonation points first)
        final candidates = <int>[];

        // 1. Strong sentence / dialogue ends — best possible break for prosody
        final sentenceEnd = RegExp(r'[.!?]["”»]?\s+').allMatches(window).lastOrNull;
        if (sentenceEnd != null) {
          candidates.add(windowStart + sentenceEnd.end);
        }

        // 2. Em-dashes and ellipses (very common in the user's RP style)
        for (final marker in ['—', '–', '…', '...']) {
          final idx = window.lastIndexOf(marker);
          if (idx != -1) candidates.add(windowStart + idx + marker.length);
        }

        // 3. Action block boundaries (*text*) — critical for "read everything" mode
        final actionBoundary = RegExp(r'\s*\*').allMatches(window).lastOrNull;
        if (actionBoundary != null) {
          candidates.add(windowStart + actionBoundary.start);
        }

        // 4. Clause / breath pauses
        for (final marker in [', ', '; ', ': ']) {
          final idx = window.lastIndexOf(marker);
          if (idx != -1) candidates.add(windowStart + idx + marker.length);
        }

        // 5. End of quoted dialogue even if not followed by strong punctuation
        final quoteEnd = RegExp(r'["”»]\s+').allMatches(window).lastOrNull;
        if (quoteEnd != null) {
          candidates.add(windowStart + quoteEnd.end);
        }

        // 6. Last resort: clean word boundary
        final lastSpace = window.lastIndexOf(' ');
        if (lastSpace != -1) {
          candidates.add(windowStart + lastSpace);
        }

        // Pick the best candidate that is still inside a sane range
        for (final c in candidates) {
          if (c > start + 30 && c <= idealEnd + 55) {
            chosenEnd = c;
            break;
          }
        }

        // Absolute fallback: hard word boundary near the target
        if (chosenEnd == text.length) {
          final hardSpace = text.lastIndexOf(' ', idealEnd + 20);
          if (hardSpace > start + 30) {
            chosenEnd = hardSpace;
          } else {
            chosenEnd = idealEnd; // last-ditch hard cut (rare)
          }
        }
      }

      String chunkText = text.substring(start, chosenEnd).trim();

      if (chunkText.isNotEmpty) {
        final chunk = _makeChunk(
          index: index++,
          text: chunkText,
          voice: voice,
          speed: speed,
          lang: lang,
          modelPath: modelPath,
          voicesPath: voicesPath,
          prefix: prefix,
        );

        if (chunkText.length < 25) {
          kDebugPrint('[KokoroChunker] ⚠️  Very small chunk created #${chunk.originalIndex} (len=${chunkText.length}): "${_preview(chunkText)}"');
        } else {
          kDebugPrint('[KokoroChunker] Created chunk #${chunk.originalIndex} (len=${chunkText.length}): "${_preview(chunkText)}"');
        }

        chunks.add(chunk);
      }

      start = chosenEnd;

      // Skip leading whitespace for the next chunk
      while (start < text.length && (text[start] == ' ' || text[start] == '\n' || text[start] == '\t')) {
        start++;
      }
    }

    kDebugPrint('[KokoroChunker] Finished smart fixed-character splitting → produced ${chunks.length} chunks');
    return chunks;
  }

  /// Force-split a long chunk when we have no choice.
  /// We try very hard not to create tiny fragments (< 25 chars).
  /// We prefer splitting after commas, semicolons, "and", "but", etc.
  static List<String> _forceSplit(String text, int maxChars) {
    final result = <String>[];
    String remaining = text;

    while (remaining.length > maxChars) {
      // Look for a reasonable break point in the window [maxChars*0.65 ... maxChars + 60]
      final minSearch = (maxChars * 0.65).floor().clamp(0, remaining.length - 1);
      final maxSearch = (maxChars + 60).clamp(0, remaining.length);

      final searchRegion = remaining.substring(minSearch, maxSearch);

      int breakPos = -1;

      // Preferred break points for RP/prose (in rough order of quality)
      final breakOptions = [
        ', ', '; ', ' and ', ' but ', ' so ', ' because ',
        '—', '–', '…', '...',
        ', ', ' '
      ];

      for (final option in breakOptions) {
        final idx = searchRegion.lastIndexOf(option);
        if (idx != -1) {
          final candidate = minSearch + idx + option.length;
          // Only accept if the resulting first chunk is reasonably sized
          if (candidate >= 25 && candidate <= maxChars + 30) {
            breakPos = candidate;
            break;
          }
        }
      }

      if (breakPos == -1 || breakPos < 25) {
        // Last resort: hard cut, but try to land on a space
        breakPos = maxChars;
        final spaceIdx = remaining.lastIndexOf(' ', breakPos + 20);
        if (spaceIdx > breakPos - 15 && spaceIdx > 20) {
          breakPos = spaceIdx + 1;
        }
      }

      final firstPart = remaining.substring(0, breakPos).trim();
      if (firstPart.length < 20) {
        // Something went wrong — just take a bigger chunk
        breakPos = maxChars + 30;
      }

      result.add(remaining.substring(0, breakPos).trim());
      remaining = remaining.substring(breakPos).trim();
    }

    if (remaining.isNotEmpty) {
      result.add(remaining);
    }

    // Final safety filter: drop any absurdly tiny chunks
    return result.where((s) => s.length >= 18).toList();
  }

  static KokoroChunk _makeChunk({
    required int index,
    required String text,
    required String voice,
    required double speed,
    required String lang,
    required String modelPath,
    required String voicesPath,
    required String prefix,
  }) {
    final safeIndex = index.toString().padLeft(4, '0');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempDir = Directory.systemTemp.path;
    final path = p.join(tempDir, '${prefix}_${timestamp}_$safeIndex.wav');

    return KokoroChunk(
      originalIndex: index,
      text: text,
      voice: voice,
      speed: speed,
      lang: lang,
      outputPath: path,
      modelPath: modelPath,
      voicesPath: voicesPath,
    );
  }
}