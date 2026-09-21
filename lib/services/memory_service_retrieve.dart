// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RAG retrieve: score stored windows and Data Bank entries against the
// query. Embed/store stays on MemoryService. Session isolation for
// sessionScopedCharacterIds stays here (group_rag_identity_test).

part of 'memory_service.dart';

extension MemoryServiceRetrieve on MemoryService {
  Future<List<RetrievedMemory>> _retrieveImpl({
    required String queryText,
    required List<String> sourceCharacterIds,
    required String currentSessionId,
    required int inContextStart,
    required int limit,
    required double minScore,
    Map<String, double>? characterPriorities,
    required Set<String> sessionScopedCharacterIds,
  }) async {
    lastRetrieveError = null;
    await _ensureEmbeddingsReady();
    if (!isOperational || queryText.trim().isEmpty) {
      debugPrint(
        '[RAG:Memory] retrieve() skipped — not operational or empty query',
      );
      return [];
    }

    // Skip retrieval for brand new sessions with very few messages
    if (inContextStart < 3) {
      debugPrint(
        '[RAG:Memory] retrieve() skipped - session too new (inContextStart=$inContextStart)',
      );
      return [];
    }

    final cleanedQuery = _cleanForEmbedding(queryText);
    final queryPreview = cleanedQuery.length > 100
        ? '${cleanedQuery.substring(0, 100)}...'
        : cleanedQuery;
    debugPrint(
      '[RAG:Memory] ── Retrieving memories (limit: $limit, minScore: $minScore) ──',
    );
    debugPrint('[RAG:Memory] Query: "$queryPreview"');
    debugPrint('[RAG:Memory] Source character IDs: $sourceCharacterIds');
    debugPrint(
      '[RAG:Memory] Current session: $currentSessionId, inContextStart: $inContextStart',
    );

    try {
      final queryVector = await _embeddingService.embed(cleanedQuery);
      if (queryVector == null) {
        lastRetrieveError = 'query embed failed';
        debugPrint(
          '[RAG:Memory] ✗ Query embedding failed — aborting retrieval',
        );
        return [];
      }
      debugPrint('[RAG:Memory] Query vector: ${queryVector.length}d');

      final candidates = await _db.getEmbeddingsForCharacters(
        sourceCharacterIds,
        currentSessionId: currentSessionId,
        sessionScopedCharacterIds: sessionScopedCharacterIds,
      );
      debugPrint('[RAG:Memory] Candidates from DB: ${candidates.length}');

      final dataBankCandidates = <DataBankEntry>[];
      for (final charId in sourceCharacterIds) {
        final entries = await _db.getDataBankEntriesForCharacter(charId);
        dataBankCandidates.addAll(
          entries.where((e) => e.embedding != null && e.dimensions > 0),
        );
      }
      if (dataBankCandidates.isNotEmpty) {
        debugPrint(
          '[RAG:Memory] Data Bank candidates: ${dataBankCandidates.length}',
        );
      }

      if (candidates.isEmpty && dataBankCandidates.isEmpty) {
        debugPrint(
          '[RAG:Memory] No stored embeddings or Data Bank entries found',
        );
        return [];
      }

      final scored = <RetrievedMemory>[];
      var skippedInContext = 0;
      var skippedCrossSession = 0;
      var belowThreshold = 0;

      for (final candidate in candidates) {
        // Session isolation: the speaker's OWN memories must never cross chats
        // (stale locations/storylines from a previous chat with the same
        // character). Explicit cross-character sources are intentionally NOT
        // session-scoped, so their opt-in cross-session recall still works.
        if (sessionScopedCharacterIds.contains(candidate.characterId) &&
            candidate.sessionId != currentSessionId) {
          skippedCrossSession++;
          continue;
        }

        // Current-session windows still in (or too close to) the visible
        // context — see isWindowEligible for the overlap + min-age rules.
        if (!MemoryService.isWindowEligible(
          candidateSessionId: candidate.sessionId,
          currentSessionId: currentSessionId,
          positionEnd: candidate.positionEnd,
          inContextStart: inContextStart,
        )) {
          skippedInContext++;
          continue;
        }

        final storedVector = MemoryService.bytesToVector(
          candidate.embedding,
          candidate.dimensions,
        );
        if (storedVector == null) continue;

        final rawScore = MemoryService.cosineSimilarity(
          queryVector,
          storedVector,
        );
        final priority = characterPriorities?[candidate.characterId] ?? 1.0;
        final score = rawScore * priority;

        if (score >= minScore) {
          scored.add(
            RetrievedMemory(
              content: candidate.content,
              characterId: candidate.characterId,
              sessionId: candidate.sessionId,
              positionStart: candidate.positionStart,
              positionEnd: candidate.positionEnd,
              score: score,
            ),
          );
        } else {
          belowThreshold++;
        }
      }

      for (final entry in dataBankCandidates) {
        final storedVector = MemoryService.bytesToVector(
          entry.embedding!,
          entry.dimensions,
        );
        if (storedVector == null) continue;

        final rawScore = MemoryService.cosineSimilarity(
          queryVector,
          storedVector,
        );
        final priority = characterPriorities?[entry.characterId] ?? 1.0;
        final score = rawScore * priority;

        if (score >= minScore) {
          scored.add(
            RetrievedMemory(
              content: '[Data Bank: ${entry.title}] ${entry.content}',
              characterId: entry.characterId,
              sessionId: 'databank',
              positionStart: -1,
              positionEnd: -1,
              score: score,
            ),
          );
        } else {
          belowThreshold++;
        }
      }

      debugPrint(
        '[RAG:Memory] Scoring: ${scored.length} above threshold, $belowThreshold below, $skippedInContext skipped (in-context), $skippedCrossSession skipped (cross-session)',
      );

      scored.sort((a, b) => b.score.compareTo(a.score));
      final results = scored.take(limit).toList();

      if (results.isNotEmpty) {
        debugPrint('[RAG:Memory] ── Top ${results.length} results: ──');
        for (var i = 0; i < results.length; i++) {
          final m = results[i];
          final contentPreview = m.content.length > 60
              ? '${m.content.substring(0, 60)}...'
              : m.content;
          debugPrint(
            '[RAG:Memory]   #${i + 1} score=${m.score.toStringAsFixed(3)} [${m.positionStart}-${m.positionEnd}] char=${m.characterId ?? "n/a"}',
          );
          debugPrint('[RAG:Memory]       "$contentPreview"');
        }
      } else {
        debugPrint('[RAG:Memory] No results above threshold $minScore');
      }

      return results;
    } catch (e) {
      lastRetrieveError = '$e';
      debugPrint('[RAG:Memory] ✗ Retrieval failed: $e');
      return [];
    }
  }
}
