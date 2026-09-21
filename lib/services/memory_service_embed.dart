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

part of 'memory_service.dart';

/// Window embed insert. Retrieve scoring stays on [MemoryService].
extension MemoryServiceEmbed on MemoryService {
  Future<({int stored, bool hasMore, bool aborted})> _embedMessageWindowBody({
    required String sessionId,
    required String characterId,
    required List<String> formattedMessages,
    required int totalMessageCount,
    required int positionOffset,
    int? maxWindows,
    bool Function()? shouldContinue,
  }) async {
    await _ensureEmbeddingsReady();
    if (!isOperational) {
      debugPrint(
        '[RAG:Memory] embedMessageWindow skipped — not operational (enabled=${_storageService.memorySettings.ragEnabled}, available=${_embeddingService.isAvailable})',
      );
      return (stored: 0, hasMore: false, aborted: false);
    }

    debugPrint(
      '[RAG:Memory] ── Embedding session $sessionId (char: $characterId, ${formattedMessages.length} msgs, total: $totalMessageCount) ──',
    );

    _isEmbedding = true;
    _pendingEmbeddings++;
    notify();

    var stored = 0;
    var aborted = false;
    var hasMore = false;
    try {
      final windowSize = _storageService.memorySettings.ragWindowSize;

      // Ranges only — never load embedding BLOBs for a presence check.
      final existingRanges = await _db.getEmbeddingRangesForSession(
        sessionId,
        characterId: characterId,
      );

      debugPrint(
        '[RAG:Memory] Existing ranges: ${existingRanges.length}, window size: $windowSize',
      );

      // Discover missing windows. When [maxWindows] is set, stop after finding
      // that many candidates and remember that more may exist past the scan.
      final newWindows = <({int start, int end, String text})>[];
      var cappedDiscovery = false;

      for (
        int i = 0;
        i <= formattedMessages.length - windowSize;
        i += windowSize
      ) {
        final end = (i + windowSize - 1).clamp(0, formattedMessages.length - 1);
        // Persist positions — never the in-memory 0..N of a 24-row tail.
        final persistStart = i + positionOffset;
        final persistEnd = end + positionOffset;
        final range = (persistStart, persistEnd);

        if (existingRanges.contains(range)) {
          continue; // Already embedded
        }

        final windowText = formattedMessages.sublist(i, end + 1).join('\n');
        final cleanedText = _cleanForEmbedding(windowText);
        if (cleanedText.isEmpty) continue; // Skip if only think blocks
        newWindows.add((
          start: persistStart,
          end: persistEnd,
          text: cleanedText,
        ));
        if (maxWindows != null && newWindows.length >= maxWindows) {
          // Peek whether any further missing range exists without cleaning.
          for (
            int j = i + windowSize;
            j <= formattedMessages.length - windowSize;
            j += windowSize
          ) {
            final jEnd = (j + windowSize - 1).clamp(
              0,
              formattedMessages.length - 1,
            );
            if (!existingRanges.contains((
              j + positionOffset,
              jEnd + positionOffset,
            ))) {
              cappedDiscovery = true;
              break;
            }
          }
          break;
        }
      }

      if (newWindows.isEmpty) {
        debugPrint(
          '[RAG:Memory] No new windows to embed (all ${existingRanges.length} windows already stored)',
        );
        return (stored: 0, hasMore: false, aborted: false);
      }

      debugPrint(
        '[RAG:Memory] ▶ Embedding up to ${newWindows.length} window(s)'
        '${maxWindows != null ? ' (budget $maxWindows)' : ''}'
        '${cappedDiscovery ? ', more remain' : ''}...',
      );

      // Embed each window and store. Null embeds skip to the next candidate
      // in this pass rather than treating the whole backfill as finished.
      for (var wi = 0; wi < newWindows.length; wi++) {
        final window = newWindows[wi];
        if (shouldContinue != null && !shouldContinue()) {
          aborted = true;
          hasMore = true;
          debugPrint(
            '[RAG:Memory]   ⏸ Aborting mid-pass (shouldContinue=false); '
            '$stored stored — remaining resume later',
          );
          break;
        }
        debugPrint(
          '[RAG:Memory]   Window [${window.start}-${window.end}] (${window.text.length} chars)...',
        );
        final vector = await _embeddingService.embed(window.text);
        if (vector == null) {
          debugPrint(
            '[RAG:Memory]   ✗ Embedding returned null for window [${window.start}-${window.end}]',
          );
          // Still more work (this window + any after) — do not claim done.
          hasMore = true;
          continue;
        }

        final bytes = Float32List.fromList(
          vector.map((e) => e.toDouble()).toList(),
        );

        await _db.insertEmbedding(
          MessageEmbeddingsCompanion(
            sessionId: drift.Value(sessionId),
            characterId: drift.Value(characterId),
            positionStart: drift.Value(window.start),
            positionEnd: drift.Value(window.end),
            content: drift.Value(window.text),
            embedding: drift.Value(Uint8List.view(bytes.buffer)),
            dimensions: drift.Value(vector.length),
          ),
        );
        stored++;
        debugPrint(
          '[RAG:Memory]   ✅ Stored in DB (${vector.length}d, ${bytes.lengthInBytes} bytes)',
        );
      }

      if (!aborted) {
        hasMore = cappedDiscovery || hasMore;
      }

      debugPrint(
        '[RAG:Memory] ── Done: $stored stored this call '
        '(hasMore=$hasMore aborted=$aborted) ──',
      );
    } catch (e) {
      debugPrint('[RAG:Memory] ✗ Embedding failed: $e');
      // Fail soft: allow caller to retry later rather than claim finished.
      hasMore = true;
    } finally {
      _pendingEmbeddings--;
      _isEmbedding = _pendingEmbeddings > 0;
      notify();
    }
    return (stored: stored, hasMore: hasMore, aborted: aborted);
  }
}
