// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World, chat-world attachment, and biome-span queries (Living Worlds).

part of 'database.dart';

/// World, chat-world attachment, and biome-span queries (Living Worlds).
extension AppDatabaseWorldQueries on AppDatabase {
  // ── World Queries ───────────────────────────────────────────────────

  Future<List<World>> getAllWorlds() =>
      (select(worlds)..where((w) => w.deletedAt.isNull())).get();

  Future<String> insertWorld(WorldsCompanion world) async {
    final id = world.id.present ? world.id.value : _uuid.v4();
    world = world.copyWith(id: Value(id));
    await into(worlds).insert(world);
    await bumpSyncVersion();
    return id;
  }

  Future<bool> updateWorld(WorldsCompanion world) async {
    final result = await update(worlds).replace(world);
    await bumpSyncVersion();
    return result;
  }

  Future<int> deleteWorldById(String id) async {
    final count = await (delete(worlds)..where((w) => w.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  /// Delete re-root (docs/design/locations-within-worlds.md §3): clear
  /// [worldId] from its children's parent column so they become roots.
  /// Climate flags stay exactly as they were. Returns how many moved.
  Future<int> reRootWorldChildren(String worldId) async {
    final count =
        await (update(worlds)..where((w) => w.parentWorldId.equals(worldId)))
            .write(const WorldsCompanion(parentWorldId: Value(null)));
    if (count > 0) await bumpSyncVersion();
    return count;
  }

  Future<World?> getWorldByName(String name) =>
      (select(worlds)..where((w) => w.name.equals(name) & w.deletedAt.isNull()))
          .getSingleOrNull();

  Future<World?> getWorldById(String id) => (select(
    worlds,
  )..where((w) => w.id.equals(id) & w.deletedAt.isNull())).getSingleOrNull();

  // ── Chat worlds / biome spans (Living Worlds) ───────────────────────

  /// Primary-first then lore (sort_order). Compatible with lore collectors.
  Future<List<String>> getWorldIdsForChat(String chatId) async {
    final slots = await getChatWorldAttachments(chatId);
    return slots.allIds;
  }

  /// Setting + Lore attachments for a chat.
  Future<ChatPlaceSlots> getChatWorldAttachments(String chatId) async {
    final rows =
        await (select(chatWorlds)
              ..where((t) => t.chatId.equals(chatId))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
            .get();
    String? primaryId;
    final loreIds = <String>[];
    for (final r in rows) {
      if (r.isPrimary && primaryId == null) {
        primaryId = r.worldId;
      } else {
        loreIds.add(r.worldId);
      }
    }
    return ChatPlaceSlots(primaryId: primaryId, loreIds: loreIds);
  }

  /// Write Setting + Lore roles. Primary uses sort_order -1; lore is 0..N.
  /// Empty primaryId + empty loreIds = decided empty (no ghost group fallback).
  Future<void> setChatWorldAttachments(
    String chatId, {
    String? primaryId,
    List<String> loreIds = const [],
  }) async {
    // Drop primary from lore if duplicated.
    final cleanLore = [
      for (final id in loreIds)
        if (id.isNotEmpty && id != primaryId) id,
    ];
    final primary = (primaryId != null && primaryId.isNotEmpty)
        ? primaryId
        : null;
    await transaction(() async {
      await (delete(chatWorlds)..where((t) => t.chatId.equals(chatId))).go();
      if (primary != null) {
        await into(chatWorlds).insert(
          ChatWorldsCompanion.insert(
            id: _uuid.v4(),
            chatId: chatId,
            worldId: primary,
            sortOrder: const Value(-1),
            isPrimary: const Value(true),
          ),
        );
      }
      var order = 0;
      for (final wid in cleanLore) {
        await into(chatWorlds).insert(
          ChatWorldsCompanion.insert(
            id: _uuid.v4(),
            chatId: chatId,
            worldId: wid,
            sortOrder: Value(order++),
            isPrimary: const Value(false),
          ),
        );
      }
    });
    await bumpSyncVersion();
  }

  /// Legacy flat writer — partitions by climate_enabled for seed callers.
  /// Prefer [setChatWorldAttachments] when roles are known.
  Future<void> setChatWorlds(String chatId, List<String> worldIds) async {
    // Resolve climate flags for partition (seed / backfill path).
    final climateOn = <String>{};
    if (worldIds.isNotEmpty) {
      final worlds = await (select(
        this.worlds,
      )..where((w) => w.id.isIn(worldIds))).get();
      for (final w in worlds) {
        if (w.climateEnabled) climateOn.add(w.id);
      }
    }
    final slots = partitionLinkedPlaces(
      worldIds: worldIds,
      isClimateEnabled: climateOn.contains,
    );
    await setChatWorldAttachments(
      chatId,
      primaryId: slots.primaryId,
      loreIds: slots.loreIds,
    );
  }

  Future<void> deleteChatWorldLinksForWorld(String worldId) async {
    await (delete(chatWorlds)..where((t) => t.worldId.equals(worldId))).go();
    await bumpSyncVersion();
  }

  /// Remove [ids] and [names] from every characters.world_names and
  /// groups.world_ids JSON array (Living Worlds: purge character clones).
  Future<int> stripWorldRefsFromCharactersAndGroups({
    required Set<String> ids,
    required Set<String> names,
  }) {
    if (ids.isEmpty && names.isEmpty) return Future.value(0);
    return rewriteWorldRefsInCharactersAndGroups(
      (refs) => [
        for (final r in refs)
          if (!ids.contains(r) && !names.contains(r)) r,
      ],
    );
  }

  /// Run [rewrite] over every live characters.world_names and
  /// groups.world_ids JSON array, writing back only the rows it changed.
  /// Returns how many rows changed.
  Future<int> rewriteWorldRefsInCharactersAndGroups(
    List<String> Function(List<String> refs) rewrite,
  ) async {
    var touched = 0;
    Future<void> sweep(String table, String column) async {
      final rows = await customSelect(
        'SELECT id, $column FROM $table WHERE deleted_at IS NULL',
      ).get();
      for (final row in rows) {
        final id = row.data['id']?.toString();
        final raw = row.data[column]?.toString() ?? '[]';
        final next = _rewriteWorldRefJson(raw, rewrite);
        if (next == null) continue;
        await customStatement('UPDATE $table SET $column = ? WHERE id = ?', [
          next,
          id,
        ]);
        touched++;
      }
    }

    await sweep('characters', 'world_names');
    await sweep('groups', 'world_ids');
    if (touched > 0) await bumpSyncVersion();
    return touched;
  }

  /// The new JSON array string when [rewrite] changed it, else null
  /// (unchanged or unreadable).
  String? _rewriteWorldRefJson(
    String raw,
    List<String> Function(List<String> refs) rewrite,
  ) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final refs = [
        for (final e in decoded)
          if ((e?.toString() ?? '').isNotEmpty) e.toString(),
      ];
      final next = rewrite(refs);
      final before = [for (final e in decoded) e?.toString()];
      return listEquals(next, before) ? null : jsonEncode(next);
    } catch (e) {
      debugPrint('[Worlds] world ref list unreadable, left as is: $e');
      return null;
    }
  }

  /// Chats that have places attached but no Setting.
  Future<List<String>> chatIdsWithoutSetting() async {
    final rows = await customSelect(
      'SELECT chat_id FROM chat_worlds GROUP BY chat_id '
      'HAVING MAX(is_primary) = 0',
    ).get();
    return [for (final r in rows) r.data['chat_id'].toString()];
  }

  /// Upsert semantics per (chat, day): switching climate twice on the same
  /// story day REPLACES the earlier span instead of stacking a duplicate row
  /// whose winner would depend on incidental row order (spans are read back
  /// ordered by effective_from_day only). Transactional so a failure between
  /// delete and insert can't silently drop the day's span.
  Future<void> insertBiomeSpan({
    required String chatId,
    required int effectiveFromDay,
    required String biomeJson,
  }) async {
    await transaction(() async {
      await (delete(chatBiomeSpans)..where(
            (t) =>
                t.chatId.equals(chatId) &
                t.effectiveFromDay.equals(effectiveFromDay),
          ))
          .go();
      await into(chatBiomeSpans).insert(
        ChatBiomeSpansCompanion.insert(
          id: _uuid.v4(),
          chatId: chatId,
          effectiveFromDay: effectiveFromDay,
          biomeJson: biomeJson,
        ),
      );
      await bumpSyncVersion();
    });
  }

  Future<List<ChatBiomeSpan>> getBiomeSpansForChat(String chatId) async {
    return (select(chatBiomeSpans)
          ..where((t) => t.chatId.equals(chatId))
          ..orderBy([(t) => OrderingTerm.asc(t.effectiveFromDay)]))
        .get();
  }
}
