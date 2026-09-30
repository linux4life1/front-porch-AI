// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Embedding, journal, growth-ring, data-bank, objective, and story-project
// queries.

part of 'database.dart';

/// Embedding, journal, growth-ring, data-bank, objective, and story-project queries.
extension AppDatabaseMemoryQueries on AppDatabase {
  // ── Embedding Queries ──────────────────────────────────────────────

  Future<void> insertEmbedding(MessageEmbeddingsCompanion embedding) async {
    if (!embedding.id.present) {
      embedding = embedding.copyWith(id: Value(_uuid.v4()));
    }
    await into(messageEmbeddings).insert(embedding);
  }

  Future<void> insertEmbeddings(
    List<MessageEmbeddingsCompanion> embeddings,
  ) async {
    final withIds = embeddings
        .map((e) => e.id.present ? e : e.copyWith(id: Value(_uuid.v4())))
        .toList();
    await batch((b) => b.insertAll(messageEmbeddings, withIds));
  }

  /// Embeddings for [characterIds]. When [currentSessionId] is set, owners
  /// in [sessionScopedCharacterIds] are limited to that chat so retrieve()
  /// does not load every session's blobs and throw them away in Dart.
  /// Unscoped ids (opt-in cross-character memory) still span sessions.
  Future<List<MessageEmbedding>> getEmbeddingsForCharacters(
    List<String> characterIds, {
    String? currentSessionId,
    Set<String> sessionScopedCharacterIds = const {},
  }) async {
    if (characterIds.isEmpty) return [];
    final scoped = [
      for (final id in sessionScopedCharacterIds)
        if (characterIds.contains(id)) id,
    ];
    final q = select(messageEmbeddings)
      ..where((e) => e.characterId.isIn(characterIds));
    if (currentSessionId != null &&
        currentSessionId.isNotEmpty &&
        scoped.isNotEmpty) {
      final unscoped = [
        for (final id in characterIds)
          if (!scoped.contains(id)) id,
      ];
      q.where((e) {
        final thisChat = e.sessionId.equals(currentSessionId);
        if (unscoped.isEmpty) return thisChat;
        return thisChat | e.characterId.isIn(unscoped);
      });
    }
    return q.get();
  }

  /// Presence-only ranges for one session (+ optional character). Does **not**
  /// load embedding BLOBs — used by chunked import backfill so each pass is
  /// not O(N) blob copies into the UI isolate.
  ///
  /// - `characterId == null` → all characters in the session.
  /// - `characterId` non-null (even `''`) → only that exact character id.
  ///   Not a wildcard: empty string matches only rows stored under `''`.
  Future<Set<(int, int)>> getEmbeddingRangesForSession(
    String sessionId, {
    String? characterId,
  }) async {
    final q = selectOnly(messageEmbeddings)
      ..addColumns([
        messageEmbeddings.positionStart,
        messageEmbeddings.positionEnd,
      ])
      ..where(messageEmbeddings.sessionId.equals(sessionId));
    if (characterId != null) {
      q.where(messageEmbeddings.characterId.equals(characterId));
    }
    final rows = await q.get();
    return {
      for (final r in rows)
        (
          r.read(messageEmbeddings.positionStart)!,
          r.read(messageEmbeddings.positionEnd)!,
        ),
    };
  }

  /// Delete all embeddings for a session (cascading cleanup).
  Future<int> deleteEmbeddingsForSession(String sessionId) => (delete(
    messageEmbeddings,
  )..where((e) => e.sessionId.equals(sessionId))).go();

  /// Delete all embeddings for a character.
  Future<int> deleteEmbeddingsForCharacter(String characterId) => (delete(
    messageEmbeddings,
  )..where((e) => e.characterId.equals(characterId))).go();

  /// Count total embeddings (for debug/settings display).
  Future<int> countEmbeddings() async {
    final result = await customSelect(
      'SELECT COUNT(*) AS cnt FROM message_embeddings',
    ).getSingle();
    return result.read<int>('cnt');
  }

  // ── Journal Queries ────────────────────────────────────────────────
  // The Journal: per-chat, per-character memory cards. No bumpSyncVersion,
  // matching the MessageEmbeddings precedent (derived, session-local data).

  /// All cards for one diary owner in one chat — pinned first, then oldest
  /// first (stable reading order for prompt handles and the UI).
  /// Every diary owner's cards for one session — the timeline-integrity
  /// invalidation sweep (regen/edit/delete) must cover owners no longer in
  /// the cast, so it cannot iterate the live participant list.
  Future<List<JournalMemoryData>> getJournalCardsForSession(String sessionId) =>
      (select(
        journalMemories,
      )..where((j) => j.sessionId.equals(sessionId))).get();

  Future<List<JournalMemoryData>> getJournalCards(
    String sessionId,
    String characterId,
  ) =>
      (select(journalMemories)
            ..where(
              (j) =>
                  j.sessionId.equals(sessionId) &
                  j.characterId.equals(characterId),
            )
            ..orderBy([
              (j) => OrderingTerm.desc(j.pinned),
              (j) => OrderingTerm.asc(j.createdAt),
            ]))
          .get();

  Future<void> insertJournalCard(JournalMemoriesCompanion card) async {
    if (!card.id.present) {
      card = card.copyWith(id: Value(_uuid.v4()));
    }
    await into(journalMemories).insert(card);
  }

  /// Single card by primary key (porch-ack clear, rare paths).
  Future<JournalMemoryData?> getJournalCardById(String id) => (select(
    journalMemories,
  )..where((j) => j.id.equals(id))).getSingleOrNull();

  /// Write-by-id partial update (mirrors [updateMessage] style).
  Future<void> updateJournalCard(String id, JournalMemoriesCompanion card) =>
      (update(journalMemories)..where((j) => j.id.equals(id))).write(card);

  Future<int> deleteJournalCard(String id) =>
      (delete(journalMemories)..where((j) => j.id.equals(id))).go();

  /// Cascading cleanup (also invoked inline by [deleteSessionById]).
  Future<int> deleteJournalCardsForSession(String sessionId) => (delete(
    journalMemories,
  )..where((j) => j.sessionId.equals(sessionId))).go();

  Future<int> countJournalCards(String sessionId, String characterId) async {
    final result = await customSelect(
      'SELECT COUNT(*) AS cnt FROM journal_memories '
      'WHERE session_id = ? AND character_id = ?',
      variables: [
        Variable.withString(sessionId),
        Variable.withString(characterId),
      ],
    ).getSingle();
    return result.read<int>('cnt');
  }

  // ── Growth Ring Queries ────────────────────────────────────────────────
  // Growth Rings: per-chat, per-character growth entries + per-session pass
  // cursor (docs/design/growth-rings.md). No bumpSyncVersion, matching the
  // JournalMemories precedent (derived, session-local data).

  /// All rings (active AND retired) for one owner in one chat — active first
  /// by strength descending, then retired by recency. This order is what the
  /// growth prompt numbers its 1-based handles by (active rings only) and
  /// what the timeline UI renders, so the surfaces always agree.
  Future<List<GrowthRingData>> getGrowthRings(
    String sessionId,
    String characterId,
  ) =>
      (select(growthRings)
            ..where(
              (g) =>
                  g.sessionId.equals(sessionId) &
                  g.characterId.equals(characterId),
            )
            ..orderBy([
              (g) => OrderingTerm.asc(g.retired),
              (g) => OrderingTerm.desc(g.strength),
              (g) => OrderingTerm.asc(g.createdAt),
            ]))
          .get();

  Future<void> insertGrowthRing(GrowthRingsCompanion ring) async {
    if (!ring.id.present) {
      ring = ring.copyWith(id: Value(_uuid.v4()));
    }
    await into(growthRings).insert(ring);
  }

  /// Write-by-id partial update (mirrors [updateJournalCard] style).
  Future<void> updateGrowthRing(String id, GrowthRingsCompanion ring) =>
      (update(growthRings)..where((g) => g.id.equals(id))).write(ring);

  Future<int> deleteGrowthRing(String id) =>
      (delete(growthRings)..where((g) => g.id.equals(id))).go();

  /// Every ring in one chat, all owners (fork carry-over).
  Future<List<GrowthRingData>> getGrowthRingsForSession(String sessionId) =>
      (select(growthRings)..where((g) => g.sessionId.equals(sessionId))).get();

  /// Re-key one owner's rings within a session (group⇄solo cast transitions —
  /// mirrors [reassignObjectives]).
  Future<int> reassignGrowthRings(
    String fromCharacterId,
    String toCharacterId, {
    required String sessionId,
  }) =>
      (update(growthRings)..where(
            (g) =>
                g.sessionId.equals(sessionId) &
                g.characterId.equals(fromCharacterId),
          ))
          .write(GrowthRingsCompanion(characterId: Value(toCharacterId)));

  /// Delete one character's rings in one chat (hard cast-removal hygiene).
  Future<int> deleteGrowthRingsForCharacter(
    String sessionId,
    String characterId,
  ) =>
      (delete(growthRings)..where(
            (g) =>
                g.sessionId.equals(sessionId) &
                g.characterId.equals(characterId),
          ))
          .go();

  /// The growth pass cursor for a session (0 when no pass has run yet).
  Future<int> getGrowthCursor(String sessionId) async {
    final row = await (select(
      growthState,
    )..where((g) => g.sessionId.equals(sessionId))).getSingleOrNull();
    return row?.cursor ?? 0;
  }

  Future<void> setGrowthCursor(String sessionId, int cursor) =>
      into(growthState).insertOnConflictUpdate(
        GrowthStateCompanion(
          sessionId: Value(sessionId),
          cursor: Value(cursor),
        ),
      );

  // ── Data Bank Queries ────────────────────────────────────────────────────────

  Future<void> insertDataBankEntry(DataBankEntriesCompanion entry) async {
    if (!entry.id.present) {
      entry = entry.copyWith(id: Value(_uuid.v4()));
    }
    await into(dataBankEntries).insert(entry);
  }

  Future<List<DataBankEntry>> getDataBankEntriesForCharacter(
    String characterId,
  ) => (select(
    dataBankEntries,
  )..where((e) => e.characterId.equals(characterId))).get();

  Future<void> updateDataBankEntry(DataBankEntriesCompanion entry) => (update(
    dataBankEntries,
  )..where((e) => e.id.equals(entry.id.value))).write(entry);

  Future<int> deleteDataBankEntry(String id) =>
      (delete(dataBankEntries)..where((e) => e.id.equals(id))).go();

  Future<int> deleteDataBankEntriesForCharacter(String characterId) => (delete(
    dataBankEntries,
  )..where((e) => e.characterId.equals(characterId))).go();

  // ── Objectives ─────────────────────────────────────────────────────

  Future<List<Objective>> getObjectivesForCharacter(
    String characterId, {
    String? chatId,
  }) =>
      (select(objectives)
            ..where((o) => o.characterId.equals(characterId))
            ..where(
              (o) =>
                  chatId == null ? o.chatId.isNull() : o.chatId.equals(chatId),
            )
            ..orderBy([
              (o) => OrderingTerm(
                expression: o.createdAt,
                mode: OrderingMode.desc,
              ),
            ]))
          .get();

  Future<List<Objective>> getActiveObjectives(
    String characterId, {
    required String chatId,
  }) =>
      (select(objectives)
            ..where(
              (o) =>
                  o.characterId.equals(characterId) &
                  o.chatId.equals(chatId) &
                  o.active.equals(true),
            )
            ..orderBy([
              (o) => OrderingTerm(
                expression: o.isPrimary,
                mode: OrderingMode.desc,
              ),
              (o) =>
                  OrderingTerm(expression: o.createdAt, mode: OrderingMode.asc),
            ]))
          .get();

  Future<void> insertObjective(ObjectivesCompanion entry) async {
    final id = entry.id.present ? entry.id.value : const Uuid().v4();
    await into(objectives).insert(entry.copyWith(id: Value(id)));
  }

  Future<void> updateObjective(ObjectivesCompanion entry) => (update(
    objectives,
  )..where((o) => o.id.equals(entry.id.value))).write(entry);

  Future<int> deleteObjective(String id) =>
      (delete(objectives)..where((o) => o.id.equals(id))).go();

  /// Re-key objectives from one character id to another within a session (used
  /// when a chat collapses group->1:1: the survivor's objectives move from its
  /// group member instance id to the origin library id, preserving the rows).
  Future<int> reassignObjectives(
    String fromCharacterId,
    String toCharacterId, {
    required String chatId,
  }) async {
    final n =
        await (update(objectives)
              ..where((o) => o.characterId.equals(fromCharacterId))
              ..where((o) => o.chatId.equals(chatId)))
            .write(ObjectivesCompanion(characterId: Value(toCharacterId)));
    await bumpSyncVersion();
    return n;
  }

  /// Re-key message embeddings from one character id to another within a session
  /// (used on group->1:1 collapse so the group-era semantic memory, stored under
  /// the `group_id` RAG key, moves to the origin library id and stays
  /// retrievable in 1:1).
  Future<int> reassignEmbeddings(
    String fromCharacterId,
    String toCharacterId, {
    required String chatId,
  }) async {
    final n =
        await (update(messageEmbeddings)
              ..where((e) => e.characterId.equals(fromCharacterId))
              ..where((e) => e.sessionId.equals(chatId)))
            .write(
              MessageEmbeddingsCompanion(characterId: Value(toCharacterId)),
            );
    await bumpSyncVersion();
    return n;
  }

  /// COPY a character's embeddings for one session under a NEW character id +
  /// session id, leaving the originals untouched (fresh row ids are assigned).
  /// Used on 1:1->group fork (`/join`): the host's prior RAG memory is duplicated
  /// into the group's shared `group_<id>` memory pool on the new group session, so
  /// the converted cast can recall pre-conversion events that scrolled out of
  /// context — while the preserved 1:1 keeps its own copy (the revert snapshot).
  /// COPY, not move, exactly like the objectives carry-on-fork; the inverse
  /// (group->1:1 collapse) re-keys in place via [reassignEmbeddings]. Returns the
  /// number of rows copied.
  Future<int> copyEmbeddingsForSession(
    String fromCharacterId,
    String fromSessionId, {
    required String toCharacterId,
    required String toSessionId,
  }) async {
    final rows =
        await (select(messageEmbeddings)
              ..where((e) => e.characterId.equals(fromCharacterId))
              ..where((e) => e.sessionId.equals(fromSessionId)))
            .get();
    if (rows.isEmpty) return 0;
    final copies = rows
        .map(
          (r) => MessageEmbeddingsCompanion(
            sessionId: Value(toSessionId),
            characterId: Value(toCharacterId),
            positionStart: Value(r.positionStart),
            positionEnd: Value(r.positionEnd),
            content: Value(r.content),
            embedding: Value(r.embedding),
            dimensions: Value(r.dimensions),
            memoryType: Value(r.memoryType),
            metadata: Value(r.metadata),
          ),
        )
        .toList();
    await insertEmbeddings(copies); // assigns fresh ids + batches
    await bumpSyncVersion();
    return copies.length;
  }

  Future<int> deleteObjectivesForCharacter(String characterId) => (delete(
    objectives,
  )..where((o) => o.characterId.equals(characterId))).go();

  Future<int> deleteObjectivesForChat(String chatId) =>
      (delete(objectives)..where((o) => o.chatId.equals(chatId))).go();

  // ── Story Project Queries ────────────────────────────────────────────

  Future<List<StoryProject>> getAllStoryProjects() =>
      (select(storyProjects)
            ..where((s) => s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]))
          .get();

  Stream<List<StoryProject>> watchAllStoryProjects() =>
      (select(storyProjects)
            ..where((s) => s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)]))
          .watch();

  Future<StoryProject?> getStoryProjectById(String id) =>
      (select(storyProjects)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<String> insertStoryProject(StoryProjectsCompanion project) async {
    final id = project.id.present ? project.id.value : _uuid.v4();
    project = project.copyWith(id: Value(id));
    await into(storyProjects).insert(project);
    await bumpSyncVersion();
    return id;
  }

  Future<void> updateStoryProject(StoryProjectsCompanion project) async {
    await (update(
      storyProjects,
    )..where((s) => s.id.equals(project.id.value))).write(project);
    await bumpSyncVersion();
  }

  Future<int> deleteStoryProject(String id) async {
    final count = await (delete(
      storyProjects,
    )..where((s) => s.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  // ── Soft Delete Cleanup ─────────────────────────────────────────────

  /// Permanently remove rows soft-deleted more than 30 days ago.
  Future<void> purgeSoftDeletes() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final cutoffEpoch = cutoff.millisecondsSinceEpoch ~/ 1000;
    for (final table in [
      'messages',
      'sessions',
      'characters',
      'folders',
      'groups',
      'personas',
      'worlds',
      'story_projects',
    ]) {
      await customUpdate(
        'DELETE FROM $table WHERE deleted_at IS NOT NULL AND deleted_at < ?',
        variables: [Variable(cutoffEpoch)],
      );
    }
  }
}
