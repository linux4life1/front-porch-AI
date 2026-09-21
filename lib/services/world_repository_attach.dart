// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chat attachments (chat_worlds) and biome spans. World CRUD stays on the
// repository shell.

part of 'world_repository.dart';

extension WorldRepositoryAttach on WorldRepository {
  Future<List<String>> _getChatWorldIdsImpl(String chatId) =>
      _db.getWorldIdsForChat(chatId);

  Future<ChatPlaceSlots> _getChatWorldAttachmentsImpl(String chatId) =>
      _db.getChatWorldAttachments(chatId);

  Future<List<model.World>> _getChatWorldsImpl(String chatId) async {
    final ids = await getChatWorldIds(chatId);
    return [
      for (final id in ids)
        if (worldById(id) != null) worldById(id)!,
    ];
  }

  Future<void> _setChatWorldAttachmentsImpl(
    String chatId, {
    String? primaryId,
    List<String> loreIds = const [],
  }) async {
    await _db.setChatWorldAttachments(
      chatId,
      primaryId: primaryId,
      loreIds: loreIds,
    );
    await _db.markChatWorldsInitialized(chatId);
    notify();
  }

  Future<void> _setChatWorldsImpl(String chatId, List<String> worldIds) async {
    // Seed-style flat write: first climate-enabled → Primary, rest → Lore.
    await ready;
    final slots = partitionLinkedPlaces(
      worldIds: worldIds,
      isClimateEnabled: (id) => worldById(id)?.climateEnabled ?? false,
    );
    await setChatWorldAttachments(
      chatId,
      primaryId: slots.primaryId,
      loreIds: slots.loreIds,
    );
  }

  Future<void> _markChatWorldsDecidedImpl(String chatId) =>
      _db.markChatWorldsInitialized(chatId);

  Future<bool> _backfillChatWorldsFromCharacterImpl({
    required String chatId,
    required List<String> characterWorldRefs,
  }) async {
    if (characterWorldRefs.isEmpty) return false;
    if (await _db.chatWorldsInitialized(chatId)) return false;
    if ((await getChatWorldIds(chatId)).isNotEmpty) {
      await _db.markChatWorldsInitialized(chatId);
      return false;
    }
    await ready;
    final ids = resolveWorldRefsToIds(
      refs: characterWorldRefs,
      nameToId: {for (final w in _worlds) w.name: w.id},
      validIds: {for (final w in _worlds) w.id},
      unresolved: <String>[],
    );
    if (ids.isEmpty) return false;
    await setChatWorlds(chatId, ids); // partitions + marks decided
    debugPrint('[Worlds] back-filled chat $chatId from its character');
    return true;
  }

  Future<void> _attachWorldToChatImpl(
    String chatId,
    String worldId, {
    bool? asPrimary,
  }) async {
    final slots = await getChatWorldAttachments(chatId);
    if (slots.allIds.contains(worldId)) return;
    final useAsSetting = asPrimary ?? !slots.hasPrimary;
    if (useAsSetting) {
      final lore = [
        if (slots.primaryId != null) slots.primaryId!,
        ...slots.loreIds,
      ];
      await setChatWorldAttachments(chatId, primaryId: worldId, loreIds: lore);
    } else {
      await setChatWorldAttachments(
        chatId,
        primaryId: slots.primaryId,
        loreIds: [...slots.loreIds, worldId],
      );
    }
  }

  Future<void> _detachWorldFromChatImpl(String chatId, String worldId) async {
    final slots = await getChatWorldAttachments(chatId);
    final primary = slots.primaryId == worldId ? null : slots.primaryId;
    final lore = [
      for (final id in slots.loreIds)
        if (id != worldId) id,
    ];
    await setChatWorldAttachments(chatId, primaryId: primary, loreIds: lore);
  }

  Future<List<String>> _applyAddedCharacterWorldsToChatsImpl({
    required String characterId,
    required List<String> addedRefs,
  }) async {
    if (addedRefs.isEmpty) return const [];
    await ready;
    final unresolved = <String>[];
    final ids = resolveWorldRefsToIds(
      refs: addedRefs,
      nameToId: {for (final w in _worlds) w.name: w.id},
      validIds: {for (final w in _worlds) w.id},
      unresolved: unresolved,
    );
    if (unresolved.isNotEmpty) {
      debugPrint(
        '[Worlds] unresolved refs on character $characterId: $unresolved',
      );
    }
    if (ids.isEmpty) return const [];

    final touched = <String>[];
    for (final session in await _db.getSessionsForCharacter(characterId)) {
      final existing = await getChatWorldIds(session.id);
      if (existing.isNotEmpty) continue; // the chat has its own opinion
      await setChatWorlds(session.id, ids);
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

  Future<void> _applyTemplateWorldsToChatImpl(
    String chatId,
    List<String> templateWorldIds,
  ) async {
    // New-session seeding can fire moments after a cold launch; resolving
    // against a not-yet-loaded cache would silently seed nothing, permanently.
    await ready;
    final unresolved = <String>[];
    final ids = resolveWorldRefsToIds(
      refs: templateWorldIds,
      nameToId: {for (final w in _worlds) w.name: w.id},
      validIds: {for (final w in _worlds) w.id},
      unresolved: unresolved,
    );
    if (unresolved.isNotEmpty) {
      debugPrint(
        '[Worlds] template had unresolved refs for chat $chatId: $unresolved',
      );
    }
    await setChatWorlds(chatId, ids);
  }

  Future<void> _setChatBiomeImpl({
    required String chatId,
    required int dayCount,
    required Biome biome,
  }) async {
    await _db.insertBiomeSpan(
      chatId: chatId,
      effectiveFromDay: dayCount,
      biomeJson: biome.toJsonString(),
    );
  }

  Future<List<({int effectiveFromDay, String biomeJson})>>
  _getChatBiomeSpanRowsImpl(String chatId) async {
    final spans = await _db.getBiomeSpansForChat(chatId);
    return [
      for (final s in spans)
        (effectiveFromDay: s.effectiveFromDay, biomeJson: s.biomeJson),
    ];
  }

  Future<Biome> _biomeAtImpl({
    required String chatId,
    required int day,
    Biome? worldDefault,
  }) async {
    final rows = await getChatBiomeSpanRows(chatId);
    return BiomeSchedule.fromJsonSpans(
      rows: rows,
      worldDefault: worldDefault,
    ).biomeAt(day);
  }
}
