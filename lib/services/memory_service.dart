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

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' as drift;
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'memory_service_retrieve.dart';
part 'memory_service_embed.dart';

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
            !positions.any((p) => p >= m.positionStart && p <= m.positionEnd))
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

  /// Set when [retrieve] failed (query embed / thrown). Null = last search
  /// completed or was skipped. Chat stamps `rag_receipt` error from this
  /// instead of lying "nothing relevant" (audit P1.9).
  String? lastRetrieveError;

  /// Re-check only while the engine is down so a retrieve/embed during
  /// download cannot latch "dead" after files land (audit P1.8). Once
  /// live, skip — [EmbeddingService.isAvailable] is the live flag.
  Future<void> _ensureEmbeddingsReady() async {
    if (!_embeddingService.isAvailable) {
      debugPrint('[RAG:Memory] Checking embedding availability...');
      await _embeddingService.checkAvailability();
    }
  }

  /// Per-session chain so import backfill and live post-gen embed cannot both
  /// discover the same missing window and insert duplicate rows (no unique
  /// key on position ranges).
  final Map<String, Future<void>> _embedChains = {};

  bool get isEmbedding => _isEmbedding;
  int get pendingEmbeddings => _pendingEmbeddings;

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

  /// Expose the embedding service for use by other services (e.g. persona fact dedup).
  EmbeddingService get embeddingService => _embeddingService;

  /// Whether RAG memory is fully operational (enabled + embeddings available).
  bool get isOperational =>
      _storageService.memorySettings.ragEnabled &&
      _embeddingService.isAvailable;

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

  /// Strip reasoning and truncate for embedding.
  ///
  /// A closed-block-only strip left an unclosed `<think>` tail in the text,
  /// which then became a stored memory: the character could later "remember"
  /// the model's deliberation as something that happened.
  String _cleanForEmbedding(String text) {
    final cleaned = stripThinkTags(text);
    if (cleaned.length <= _maxEmbedChars) return cleaned;
    return cleaned.substring(0, _maxEmbedChars);
  }

  /// Result of one [embedMessageWindow] pass.
  ///
  /// - [stored] windows written this call
  /// - [hasMore] true if missing windows remain (or pass aborted early)
  /// - [aborted] true if [shouldContinue] returned false mid-pass
  ///
  /// Callers must not treat `stored == 0` alone as "done" (a paused pass and a
  /// null-embed skip both used to return 0 and look finished).
  /// Embed a sliding window of messages and store the vectors.
  ///
  /// Called asynchronously after each message generation. Embeds messages
  /// in windows of [ragWindowSize] messages, skipping windows that are
  /// already embedded (by checking existing position ranges).
  ///
  /// Optional [maxWindows] caps work so a large import backfill can yield
  /// between chunks; the live path omits it (full pass). When set, only that
  /// many *missing* windows are discovered per call (avoids O(N²) full-history
  /// rescans on every chunk). Optional [shouldContinue] aborts mid-pass without
  /// losing already-stored progress.
  void notify() => notifyListeners();

  Future<({int stored, bool hasMore, bool aborted})> embedMessageWindow({
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
      () => _embedMessageWindowBody(
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
  }) => _retrieveImpl(
    queryText: queryText,
    sourceCharacterIds: sourceCharacterIds,
    currentSessionId: currentSessionId,
    inContextStart: inContextStart,
    limit: limit,
    minScore: minScore,
    characterPriorities: characterPriorities,
    sessionScopedCharacterIds: sessionScopedCharacterIds,
  );

  /// Embed one piece of text, or null when embeddings aren't operational
  /// (RAG off / sidecar unavailable). Availability-guarded single-text door
  /// for other services — the Journal uses it for card vectors and cold-card
  /// query embedding.
  Future<List<double>?> embedText(String text) async {
    await _ensureEmbeddingsReady();
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
