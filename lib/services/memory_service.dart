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

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' as drift;
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/database/database.dart';

/// A retrieved memory from the vector store.
class RetrievedMemory {
  final String content;
  final String? characterId;
  final String sessionId;
  final int positionStart;
  final int positionEnd;
  final double score; // cosine similarity 0.0–1.0

  const RetrievedMemory({
    required this.content,
    this.characterId,
    required this.sessionId,
    required this.positionStart,
    required this.positionEnd,
    required this.score,
  });

  /// Two-tier memory dedupe (living-time-features.md §8): drop retrievals
  /// whose span overlaps positions the Journal already expanded verbatim
  /// this turn — the exact lines are in the prompt once; twice is budget
  /// spent teaching the model to repeat itself. Pure; current-session only
  /// (cross-session sources use a different position space).
  static List<RetrievedMemory> excludingPositions(
    List<RetrievedMemory> memories,
    Set<int> positions, {
    required String currentSessionId,
  }) {
    if (positions.isEmpty) return memories;
    return [
      for (final m in memories)
        if (m.sessionId != currentSessionId ||
            !positions.any(
              (p) => p >= m.positionStart && p <= m.positionEnd,
            ))
          m,
    ];
  }
}

/// Orchestrates RAG memory: embedding message windows and retrieving relevant
/// past context for prompt injection.
///
/// Works with [EmbeddingService] for vector generation and [AppDatabase] for
/// vector storage. Only activates when RAG is enabled and embeddings are available.
class MemoryService extends ChangeNotifier {
  /// Minimum retrieval similarity. Nomic cosine scores have a high floor —
  /// UNRELATED text still lands around 0.4–0.6 — so the old 0.3 admitted
  /// essentially everything and retrieval degenerated to "top-N by rank"
  /// (the "parrots back prior events that don't fit the scene" report).
  /// 0.45 matches the Journal's verbatim-expansion bar (journal_physics
  /// kMinExpandSimilarity), the in-repo calibration for "the conversation is
  /// clearly reaching for this" in this embedding space.
  static const double kRagMinScore = 0.45;

  /// Current-session windows must END at least this many messages before the
  /// visible-context boundary to be retrievable. The windows just below the
  /// boundary are near-duplicates of the ongoing scene — they were trimmed
  /// this turn or a few turns ago, score highest of ALL candidates against a
  /// recent-messages query, and re-injecting them drags the model backward
  /// (repeating itself / reviving events the chat moved past). They become
  /// eligible naturally as the story advances. Cross-session and Data Bank
  /// sources are genuinely old and are never age-gated.
  static const int kRagMinAgeMessages = 20;

  /// Whether a stored window is old enough (relative to the visible-context
  /// boundary) to be offered for retrieval. Pure — the unit-tested core of
  /// [retrieve]'s candidate loop; cross-session isolation stays in the loop
  /// (it needs the session-scoped characterId set).
  ///
  /// Current-session windows must be strictly OLDER than the visible context
  /// by [kRagMinAgeMessages]. Comparing the window END (not start) also
  /// closes the boundary-overlap bug: a window straddling the trim point
  /// (start < boundary <= end) used to pass the old start-only check and got
  /// injected while its tail lines were still sitting in the visible
  /// transcript — literal self-repetition. Other-session and Data Bank
  /// content is never age-gated.
  static bool isWindowEligible({
    required String candidateSessionId,
    required String currentSessionId,
    required int positionEnd,
    required int inContextStart,
  }) {
    return candidateSessionId != currentSessionId ||
        positionEnd < inContextStart - kRagMinAgeMessages;
  }

  final EmbeddingService _embeddingService;
  final StorageService _storageService;
  AppDatabase _db;

  bool _isEmbedding = false;
  int _pendingEmbeddings = 0;
  bool _availabilityChecked = false;

  bool get isEmbedding => _isEmbedding;
  int get pendingEmbeddings => _pendingEmbeddings;

  /// Expose the embedding service for use by other services (e.g. persona fact dedup).
  EmbeddingService get embeddingService => _embeddingService;

  /// Whether RAG memory is fully operational (enabled + embeddings available).
  bool get isOperational =>
      _storageService.ragEnabled && _embeddingService.isAvailable;

  /// Get all stored content chunks for the given characters, sorted chronologically.
  /// Used to ground summary generation in real conversation content.
  Future<List<String>> getAllContentForCharacters(
    List<String> characterIds,
  ) async {
    if (characterIds.isEmpty) return [];
    final embeddings = await _db.getEmbeddingsForCharacters(characterIds);
    // Sort by messageIndex (chronological order)
    embeddings.sort((a, b) => a.positionStart.compareTo(b.positionStart));
    return embeddings.map((e) => e.content).toList();
  }

  MemoryService(this._embeddingService, this._storageService, this._db);

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  /// Maximum characters per embedding window. Embedding models have limited
  /// context, and large texts are very slow on CPU ONNX. 2000 chars ≈ 500 tokens.
  static const int _maxEmbedChars = 2000;

  /// Strip `<think>...</think>` blocks and truncate for embedding.
  String _cleanForEmbedding(String text) {
    // Remove think blocks (LLM reasoning, not conversation content)
    final cleaned = text
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .trim();
    if (cleaned.length <= _maxEmbedChars) return cleaned;
    return cleaned.substring(0, _maxEmbedChars);
  }

  /// Embed a sliding window of messages and store the vectors.
  ///
  /// Called asynchronously after each message generation. Embeds messages
  /// in windows of [ragWindowSize] messages, skipping windows that are
  /// already embedded (by checking existing position ranges).
  Future<void> embedMessageWindow({
    required String sessionId,
    required String characterId,
    required List<String> formattedMessages,
    required int totalMessageCount,
  }) async {
    // Lazy availability check — run once on first use
    if (!_availabilityChecked) {
      _availabilityChecked = true;
      debugPrint('[RAG:Memory] Checking embedding availability...');
      await _embeddingService.checkAvailability();
    }
    if (!isOperational) {
      debugPrint(
        '[RAG:Memory] embedMessageWindow skipped — not operational (enabled=${_storageService.ragEnabled}, available=${_embeddingService.isAvailable})',
      );
      return;
    }

    debugPrint(
      '[RAG:Memory] ── Embedding session $sessionId (char: $characterId, ${formattedMessages.length} msgs, total: $totalMessageCount) ──',
    );

    _isEmbedding = true;
    _pendingEmbeddings++;
    notifyListeners();

    try {
      final windowSize = _storageService.ragWindowSize;

      // Get existing embeddings to avoid re-embedding. Dedup is scoped to THIS
      // character: a single session can hold windows for more than one speaker
      // (e.g. a 1:1 host plus a Scene Guest), and each must store its own copy
      // under its own id so memory round-trips per character. Without the
      // characterId filter, the second speaker's identical position range would
      // be wrongly skipped as "already embedded".
      final existing = await _db.getEmbeddingsForSession(sessionId);
      final existingRanges = existing
          .where((e) => e.characterId == characterId)
          .map((e) => (e.positionStart, e.positionEnd))
          .toSet();

      debugPrint(
        '[RAG:Memory] Existing embeddings: ${existing.length}, window size: $windowSize',
      );

      // Build windows from oldest to newest
      final newWindows = <({int start, int end, String text})>[];

      for (
        int i = 0;
        i <= formattedMessages.length - windowSize;
        i += windowSize
      ) {
        final end = (i + windowSize - 1).clamp(0, formattedMessages.length - 1);
        final range = (i, end);

        if (existingRanges.contains(range)) {
          continue; // Already embedded
        }

        final windowText = formattedMessages.sublist(i, end + 1).join('\n');
        final cleanedText = _cleanForEmbedding(windowText);
        if (cleanedText.isEmpty) continue; // Skip if only think blocks
        newWindows.add((start: i, end: end, text: cleanedText));
      }

      if (newWindows.isEmpty) {
        debugPrint(
          '[RAG:Memory] No new windows to embed (all ${existingRanges.length} windows already stored)',
        );
        return;
      }

      debugPrint(
        '[RAG:Memory] ▶ Embedding ${newWindows.length} new window(s)...',
      );

      // Embed each window and store
      int stored = 0;
      for (final window in newWindows) {
        debugPrint(
          '[RAG:Memory]   Window [${window.start}-${window.end}] (${window.text.length} chars)...',
        );
        final vector = await _embeddingService.embed(window.text);
        if (vector == null) {
          debugPrint(
            '[RAG:Memory]   ✗ Embedding returned null for window [${window.start}-${window.end}]',
          );
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

      debugPrint(
        '[RAG:Memory] ── Done: $stored/${newWindows.length} windows stored ──',
      );
    } catch (e) {
      debugPrint('[RAG:Memory] ✗ Embedding failed: $e');
    } finally {
      _pendingEmbeddings--;
      _isEmbedding = _pendingEmbeddings > 0;
      notifyListeners();
    }
  }

  /// Retrieve relevant past memories for the current conversation context.
  ///
  /// Embeds the [queryText] (typically the last 2-3 messages), then searches
  /// the vector store for similar message windows. Only searches embeddings
  /// from the specified [sourceCharacterIds] and excludes any from the
  /// [currentSessionId] that fall within the [inContextPositions] range.
  ///
  /// **Session isolation** — characters listed in [sessionScopedCharacterIds]
  /// (i.e. the current speaker/self) only ever contribute memories from the
  /// current session. This is what stops a brand-new chat from surfacing stale
  /// locations and storylines that belong to a *different* chat with the same
  /// character — matching the Journal's strict per-chat guarantee. Characters
  /// NOT in that set (explicit cross-character memory sources) are deliberately
  /// left unscoped, so the opt-in "let X remember things about Y" feature still
  /// reaches across sessions. Data Bank entries are a separate, intentional
  /// cross-session knowledge source and are never scoped here.
  Future<List<RetrievedMemory>> retrieve({
    required String queryText,
    required List<String> sourceCharacterIds,
    required String currentSessionId,
    int inContextStart = 0,
    int limit = 5,
    double minScore = kRagMinScore,
    Map<String, double>? characterPriorities,
    Set<String> sessionScopedCharacterIds = const {},
  }) async {
    // Lazy availability check — run once on first use
    if (!_availabilityChecked) {
      _availabilityChecked = true;
      debugPrint('[RAG:Memory] Checking embedding availability...');
      await _embeddingService.checkAvailability();
    }
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
      // Embed the query
      final queryVector = await _embeddingService.embed(cleanedQuery);
      if (queryVector == null) {
        debugPrint(
          '[RAG:Memory] ✗ Query embedding failed — aborting retrieval',
        );
        return [];
      }
      debugPrint('[RAG:Memory] Query vector: ${queryVector.length}d');

      // Get all candidate embeddings from the specified characters
      final candidates = await _db.getEmbeddingsForCharacters(
        sourceCharacterIds,
      );
      debugPrint('[RAG:Memory] Candidates from DB: ${candidates.length}');

      // Also fetch Data Bank entries with embeddings for these characters
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

      // Score each candidate against the query
      final scored = <RetrievedMemory>[];
      int skippedInContext = 0;
      int skippedCrossSession = 0;
      int belowThreshold = 0;

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
        if (!isWindowEligible(
          candidateSessionId: candidate.sessionId,
          currentSessionId: currentSessionId,
          positionEnd: candidate.positionEnd,
          inContextStart: inContextStart,
        )) {
          skippedInContext++;
          continue;
        }

        // Deserialize the stored embedding
        final storedVector = bytesToVector(
          candidate.embedding,
          candidate.dimensions,
        );
        if (storedVector == null) continue;

        // Calculate similarity
        final rawScore = cosineSimilarity(queryVector, storedVector);
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

      // Score Data Bank entries
      for (final entry in dataBankCandidates) {
        final storedVector = bytesToVector(entry.embedding!, entry.dimensions);
        if (storedVector == null) continue;

        final rawScore = cosineSimilarity(queryVector, storedVector);
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

      // Sort by score descending and take top N
      scored.sort((a, b) => b.score.compareTo(a.score));
      final results = scored.take(limit).toList();

      if (results.isNotEmpty) {
        debugPrint('[RAG:Memory] ── Top ${results.length} results: ──');
        for (int i = 0; i < results.length; i++) {
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
      debugPrint('[RAG:Memory] ✗ Retrieval failed: $e');
      return [];
    }
  }

  /// Embed one piece of text, or null when embeddings aren't operational
  /// (RAG off / sidecar unavailable). Availability-guarded single-text door
  /// for other services — the Journal uses it for card vectors and cold-card
  /// query embedding.
  Future<List<double>?> embedText(String text) async {
    if (!_availabilityChecked) {
      _availabilityChecked = true;
      await _embeddingService.checkAvailability();
    }
    if (!isOperational) return null;
    final cleaned = _cleanForEmbedding(text);
    if (cleaned.isEmpty) return null;
    return _embeddingService.embed(cleaned);
  }

  /// Convert stored bytes back to a vector of doubles.
  static List<double>? bytesToVector(Uint8List bytes, int dimensions) {
    try {
      final floats = Float32List.view(
        bytes.buffer,
        bytes.offsetInBytes,
        dimensions,
      );
      return floats.map((f) => f.toDouble()).toList();
    } catch (e) {
      debugPrint('[MemoryService] Failed to deserialize embedding: $e');
      return null;
    }
  }

  /// Cosine similarity between two vectors.
  /// Returns a value between -1.0 and 1.0 (1.0 = identical direction).
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0.0) return 0.0;

    return dotProduct / denominator;
  }
}
