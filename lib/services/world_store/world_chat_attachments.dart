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
import 'package:front_porch_ai/services/world_chain.dart';
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
    // weather) and may hold the Setting even when the world is lore-only,
    // because the author chose it as the start. An older link that names a
    // place inside a world starts there the same way. Otherwise the Setting
    // goes to the first id whose chain authors a climate, inherited or not.
    final starts = <String>{};
    final ids = <String>[];
    for (final id in worldIds) {
      final start = startAtStar ? _repo.startingPlaceFor(id) : null;
      if (start != null && _isPlace(start)) {
        starts.add(start.id);
        ids.add(start.id);
      } else {
        ids.add(id);
      }
    }
    final slots = partitionLinkedPlaces(
      worldIds: ids,
      isClimateEnabled: (id) =>
          starts.contains(id) || _repo.climateAuthorFor(id) != null,
    );
    await _repo.setChatWorldAttachments(
      chatId,
      primaryId: slots.primaryId,
      loreIds: slots.loreIds,
    );
  }

  bool _isPlace(model.World w) => topWorldOf(w, _repo.worldById).id != w.id;

  Future<void> markDecided(String chatId) =>
      _db().markChatWorldsInitialized(chatId);

  Future<bool> backfillFromCharacter({
    required String chatId,
    required List<String> characterWorldRefs,
    List<String>? characterLoreRefs,
  }) async {
    if (characterWorldRefs.isEmpty && (characterLoreRefs?.isEmpty ?? true)) {
      return false;
    }
    if (await _db().chatWorldsInitialized(chatId)) return false;
    if ((await _repo.getChatWorldIds(chatId)).isNotEmpty) {
      await _db().markChatWorldsInitialized(chatId);
      return false;
    }
    await _repo.ready;
    if (characterLoreRefs != null) {
      // A split card seeds its Setting and Lore apart, as a new chat does.
      await applyTemplate(
        chatId,
        characterWorldRefs,
        loreRefs: characterLoreRefs,
      );
      debugPrint('[Worlds] back-filled chat $chatId from its character');
      return true;
    }
    final ids = _resolveRefs(characterWorldRefs, <String>[]);
    if (ids.isEmpty) return false;
    await _repo.setChatWorlds(chatId, ids); // partitions + marks decided
    debugPrint('[Worlds] back-filled chat $chatId from its character');
    return true;
  }

  Future<List<String>> applyAddedCharacterWorlds({
    required String characterId,
    required List<String> addedRefs,
    List<String>? addedLoreRefs,
  }) async {
    if (addedRefs.isEmpty && (addedLoreRefs?.isEmpty ?? true)) {
      return const [];
    }
    await _repo.ready;
    final unresolved = <String>[];
    final ids = _resolveRefs(addedRefs, unresolved);
    final lore = addedLoreRefs == null
        ? null
        : _resolveRefs(addedLoreRefs, unresolved);
    if (unresolved.isNotEmpty) {
      debugPrint(
        '[Worlds] unresolved refs on character $characterId: $unresolved',
      );
    }
    if (ids.isEmpty && (lore?.isEmpty ?? true)) return const [];

    final touched = <String>[];
    for (final session in await _db().getSessionsForCharacter(characterId)) {
      final existing = await _repo.getChatWorldIds(session.id);
      if (existing.isNotEmpty) continue; // the chat has its own opinion
      if (lore != null) {
        // A split card keeps each added world in its role.
        await applyTemplate(session.id, ids, loreRefs: lore);
      } else {
        await _repo.setChatWorlds(session.id, ids);
      }
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
    List<String>? loreRefs,
  }) async {
    // New-session seeding can fire moments after a cold launch; resolving
    // against a not-yet-loaded cache would silently seed nothing, permanently.
    await _repo.ready;
    final unresolved = <String>[];
    final ids = _resolveRefs(templateWorldIds, unresolved);
    final lore = loreRefs == null ? null : _resolveRefs(loreRefs, unresolved);
    if (unresolved.isNotEmpty) {
      debugPrint(
        '[Worlds] template had unresolved refs for chat $chatId: $unresolved',
      );
    }
    if (lore == null) {
      await _repo.setChatWorlds(chatId, ids, startAtStar: startAtStar);
      return;
    }
    // A split template names its Setting outright, so climate never moves
    // it. A world starts at its star; a place the author picked starts
    // there. Lore worlds map to their star exactly as the flat seed does,
    // so a legacy group re-saved unchanged seeds the same slots.
    final setting = ids.isEmpty
        ? null
        : (_isPlace(_repo.worldById(ids.first)!)
              ? ids.first
              : _startOf(ids.first));
    final loreIds = <String>[];
    for (final id in lore) {
      final slot = _startOf(id);
      if (slot != setting && !loreIds.contains(slot)) loreIds.add(slot);
    }
    await _repo.setChatWorldAttachments(
      chatId,
      primaryId: setting,
      loreIds: loreIds,
    );
  }

  /// The slot a template ref takes: its starred place when it has one.
  String _startOf(String id) {
    final start = _repo.startingPlaceFor(id);
    return start != null && _isPlace(start) ? start.id : id;
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

  /// Copy every climate changeover from [fromChatId] onto [toChatId], for a
  /// new session that continues the same story (1:1 -> group conversion).
  Future<void> copyBiomeSpans(String fromChatId, String toChatId) async {
    final db = _db();
    for (final s in await db.getBiomeSpansForChat(fromChatId)) {
      await db.insertBiomeSpan(
        chatId: toChatId,
        effectiveFromDay: s.effectiveFromDay,
        biomeJson: s.biomeJson,
      );
    }
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
