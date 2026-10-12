// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Sliding-window embed + insert for RAG memory. Owns the in-flight counters
// and the per-session lock.

import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory/memory_vectors.dart';
import 'package:front_porch_ai/services/storage_service.dart';

typedef EmbedPassResult = ({int stored, bool hasMore, bool aborted});

class MemoryWindowEmbedder {
  MemoryWindowEmbedder({
    required EmbeddingService embeddings,
    required StorageService storage,
    required AppDatabase Function() db,
    required bool Function() isOperational,
    required void Function() onChanged,
  }) : _embeddings = embeddings,
       _storage = storage,
       _db = db,
       _isOperational = isOperational,
       _onChanged = onChanged;

  final EmbeddingService _embeddings;
  final StorageService _storage;
  final AppDatabase Function() _db;
  final bool Function() _isOperational;
  final void Function() _onChanged;

  bool _isEmbedding = false;
  int _pendingEmbeddings = 0;

  /// Per-session chain so import backfill and live post-gen embed cannot both
  /// discover the same missing window and insert duplicate rows (no unique
  /// key on position ranges).
  final Map<String, Future<void>> _embedChains = {};

  bool get isEmbedding => _isEmbedding;
  int get pendingEmbeddings => _pendingEmbeddings;

  /// See [MemoryService.embedMessageWindow].
  Future<EmbedPassResult> embed({
    required String sessionId,
    required String characterId,
    required List<String> formattedMessages,
    required int totalMessageCount,
    int positionOffset = 0,
    int? maxWindows,
    bool Function()? shouldContinue,
  }) {
    // Serialize discover+insert per session so import backfill and live
    // post-gen cannot double-insert the same range (no unique DB key).
    return _withSessionEmbedLock(
      sessionId,
      () => _embedBody(
        sessionId: sessionId,
        characterId: characterId,
        formattedMessages: formattedMessages,
        totalMessageCount: totalMessageCount,
        positionOffset: positionOffset,
        maxWindows: maxWindows,
        shouldContinue: shouldContinue,
      ),
    );
  }

  Future<T> _withSessionEmbedLock<T>(
    String sessionId,
    Future<T> Function() body,
  ) async {
    final prev = _embedChains[sessionId] ?? Future<void>.value();
    final gate = Completer<void>();
    _embedChains[sessionId] = gate.future;
    await prev;
    try {
      return await body();
    } finally {
      gate.complete();
      if (identical(_embedChains[sessionId], gate.future)) {
        _embedChains.remove(sessionId);
      }
    }
  }

  Future<EmbedPassResult> _embedBody({
    required String sessionId,
    required String characterId,
    required List<String> formattedMessages,
    required int totalMessageCount,
    required int positionOffset,
    int? maxWindows,
    bool Function()? shouldContinue,
  }) async {
    await ensureEmbeddingsReady(_embeddings);
    if (!_isOperational()) {
      debugPrint(
        '[RAG:Memory] embedMessageWindow skipped — not operational (enabled=${_storage.memorySettings.ragEnabled}, available=${_embeddings.isAvailable})',
      );
      return (stored: 0, hasMore: false, aborted: false);
    }

    debugPrint(
      '[RAG:Memory] ── Embedding session $sessionId (char: $characterId, ${formattedMessages.length} msgs, total: $totalMessageCount) ──',
    );

    _isEmbedding = true;
    _pendingEmbeddings++;
    _onChanged();

    var stored = 0;
    var aborted = false;
    var hasMore = false;
    try {
      final windowSize = _storage.memorySettings.ragWindowSize;

      // Ranges only — never load embedding BLOBs for a presence check.
      final existingRanges = await _db().getEmbeddingRangesForSession(
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
        final cleanedText = cleanForEmbedding(windowText);
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
        final vector = await _embeddings.embed(window.text);
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

        await _db().insertEmbedding(
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
      _onChanged();
    }
    return (stored: stored, hasMore: hasMore, aborted: aborted);
  }
}
