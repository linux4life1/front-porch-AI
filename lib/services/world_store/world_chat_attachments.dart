// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chat attachments (chat_worlds) and biome spans for [WorldRepository].
// Reads and writes go back through the repository's public members so a
// subclass override still sees every call.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart' hide World;
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/utils.dart';

class WorldChatAttachments {
  WorldChatAttachments(this._repo, this._db);

  final WorldRepository _repo;
  final AppDatabase Function() _db;

  List<String> _resolveRefs(List<String> refs, List<String> unresolved) {
    final worlds = _repo.worlds;
    return resolveWorldRefsToIds(
      refs: refs,
      nameToId: {for (final w in worlds) w.name: w.id},
      validIds: {for (final w in worlds) w.id},
      unresolved: unresolved,
    );
  }

  Future<List<String>> chatWorldIds(String chatId) =>
      _db().getWorldIdsForChat(chatId);

  Future<ChatPlaceSlots> chatWorldAttachments(String chatId) =>
      _db().getChatWorldAttachments(chatId);

  Future<List<model.World>> chatWorlds(String chatId) async {
    final ids = await _repo.getChatWorldIds(chatId);
    return [
      for (final id in ids)
        if (_repo.worldById(id) != null) _repo.worldById(id)!,
    ];
  }

  Future<void> setAttachments(
    String chatId, {
    String? primaryId,
    List<String> loreIds = const [],
  }) async {
    final db = _db();
    await db.setChatWorldAttachments(
      chatId,
      primaryId: primaryId,
      loreIds: loreIds,
    );
    await db.markChatWorldsInitialized(chatId);
    _repo.notify();
  }

  Future<void> setFlat(
    String chatId,
    List<String> worldIds, {
    bool startAtStar = true,
  }) async {
    // Seed-style flat write: first climate-enabled → Primary, rest → Lore.
    await _repo.ready;
    // A world with a starred place starts the chat there: the place takes
    // the world's slot (its chain still brings the world's lore and
    // weather) and may hold the Setting even when it inherits its climate
    // or the world is lore-only, because the author chose it as the start.
    final starts = <String>{};
    final ids = <String>[];
    for (final id in worldIds) {
      final start = startAtStar ? _repo.startingPlaceFor(id) : null;
      if (start != null && start.id != id) {
        starts.add(start.id);
        ids.add(start.id);
      } else {
        ids.add(id);
      }
    }
    final slots = partitionLinkedPlaces(
      worldIds: ids,
      isClimateEnabled: (id) =>
          starts.contains(id) || (_repo.worldById(id)?.climateEnabled ?? false),
    );
    await _repo.setChatWorldAttachments(
      chatId,
      primaryId: slots.primaryId,
      loreIds: slots.loreIds,
    );
  }

  Future<void> markDecided(String chatId) =>
      _db().markChatWorldsInitialized(chatId);

  Future<bool> backfillFromCharacter({
    required String chatId,
    required List<String> characterWorldRefs,
  }) async {
    if (characterWorldRefs.isEmpty) return false;
    if (await _db().chatWorldsInitialized(chatId)) return false;
    if ((await _repo.getChatWorldIds(chatId)).isNotEmpty) {
      await _db().markChatWorldsInitialized(chatId);
      return false;
    }
    await _repo.ready;
    final ids = _resolveRefs(characterWorldRefs, <String>[]);
    if (ids.isEmpty) return false;
    await _repo.setChatWorlds(chatId, ids); // partitions + marks decided
    debugPrint('[Worlds] back-filled chat $chatId from its character');
    return true;
  }

  Future<List<String>> applyAddedCharacterWorlds({
    required String characterId,
    required List<String> addedRefs,
  }) async {
    if (addedRefs.isEmpty) return const [];
    await _repo.ready;
    final unresolved = <String>[];
    final ids = _resolveRefs(addedRefs, unresolved);
    if (unresolved.isNotEmpty) {
      debugPrint(
        '[Worlds] unresolved refs on character $characterId: $unresolved',
      );
    }
    if (ids.isEmpty) return const [];

    final touched = <String>[];
    for (final session in await _db().getSessionsForCharacter(characterId)) {
      final existing = await _repo.getChatWorldIds(session.id);
      if (existing.isNotEmpty) continue; // the chat has its own opinion
      await _repo.setChatWorlds(session.id, ids);
      touched.add(session.id);
    }
    if (touched.isNotEmpty) {
      debugPrint(
        '[Worlds] character $characterId worlds applied to '
        '${touched.length} existing chat(s)',
      );
    }
    return touched;
  }

  Future<void> applyTemplate(
    String chatId,
    List<String> templateWorldIds, {
    bool startAtStar = true,
  }) async {
    // New-session seeding can fire moments after a cold launch; resolving
    // against a not-yet-loaded cache would silently seed nothing, permanently.
    await _repo.ready;
    final unresolved = <String>[];
    final ids = _resolveRefs(templateWorldIds, unresolved);
    if (unresolved.isNotEmpty) {
      debugPrint(
        '[Worlds] template had unresolved refs for chat $chatId: $unresolved',
      );
    }
    await _repo.setChatWorlds(chatId, ids, startAtStar: startAtStar);
  }

  Future<void> setBiome({
    required String chatId,
    required int dayCount,
    required Biome biome,
  }) async {
    await _db().insertBiomeSpan(
      chatId: chatId,
      effectiveFromDay: dayCount,
      biomeJson: biome.toJsonString(),
    );
  }

  Future<List<({int effectiveFromDay, String biomeJson})>> biomeSpanRows(
    String chatId,
  ) async {
    final spans = await _db().getBiomeSpansForChat(chatId);
    return [
      for (final s in spans)
        (effectiveFromDay: s.effectiveFromDay, biomeJson: s.biomeJson),
    ];
  }

  Future<Biome> biomeAt({
    required String chatId,
    required int day,
    Biome? worldDefault,
  }) async {
    final rows = await _repo.getChatBiomeSpanRows(chatId);
    return BiomeSchedule.fromJsonSpans(
      rows: rows,
      worldDefault: worldDefault,
    ).biomeAt(day);
  }
}
