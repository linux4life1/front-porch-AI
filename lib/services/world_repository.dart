// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Living Worlds repository: UUID identity, .fpworld export/import, chat
// attachment (chat_worlds), biome fields. Rename no longer cascades — refs
// are ids.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart';
// `World` here means the Drift row from database.dart; the model type is
// reached through the `model.` prefix below.
import 'package:front_porch_ai/models/models.dart' hide World;
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorldRepository extends ChangeNotifier {
  final StorageService _storageService;
  AppDatabase _db;
  final List<model.World> _worlds = [];
  bool _isLoading = false;
  CharacterRepository? _characterRepository;
  GroupChatRepository? _groupRepository;
  static const _uuid = Uuid();
  static const _purgePrefKey = 'purged_character_linked_worlds_v1';

  List<model.World> get worlds => List.unmodifiable(_worlds);
  bool get isLoading => _isLoading;

  /// Places only — excludes legacy character-lore clones (should be empty after purge).
  List<model.World> get placeWorlds =>
      List.unmodifiable(_worlds.where((w) => !isCharacterLinkedWorld(w)));

  WorldRepository(this._storageService, this._db) {
    _firstLoad = loadWorlds();
  }

  /// Completes when the initial DB load has filled the in-memory cache.
  /// Await before resolving refs at times that can race app startup (e.g.
  /// seeding a brand-new chat's worlds moments after a cold launch) — the
  /// cache-only resolvers silently drop every ref while the list is empty.
  late final Future<void> _firstLoad;
  Future<void> get ready => _firstLoad;

  void setCharacterRepository(CharacterRepository repo) {
    _characterRepository = repo;
    loadWorlds();
  }

  void setGroupChatRepository(GroupChatRepository repo) {
    _groupRepository = repo;
  }

  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  model.World? worldById(String id) {
    for (final w in _worlds) {
      if (w.id == id) return w;
    }
    return null;
  }

  model.World? worldByName(String name) {
    for (final w in _worlds) {
      if (w.name == name) return w;
    }
    return null;
  }

  /// Resolve by UUID first, then by name (character.worldNames still use names).
  model.World? resolveWorld(String idOrName) {
    return worldById(idOrName) ?? worldByName(idOrName);
  }

  void _resolveAvatarPaths(List<model.World> worlds) {
    if (_characterRepository == null) return;
    for (final world in worlds) {
      CharacterCard? character;
      final charId = world.linkedCharacterId;
      if (charId != null && charId.isNotEmpty) {
        character = _characterRepository!.characters
            .where((c) => c.dbId == charId)
            .firstOrNull;
      }
      if (character == null && world.linkedCharacterName != null) {
        character = _characterRepository!.characters
            .where((c) => c.name == world.linkedCharacterName)
            .firstOrNull;
      }
      if (character != null && character.imagePath != null) {
        world.avatarPath = character.imagePath;
      }
    }
  }

  model.World _fromRow(World row) {
    Lorebook lorebook;
    if (row.lorebook != null) {
      try {
        lorebook = Lorebook.fromJson(jsonDecode(row.lorebook!));
      } catch (_) {
        lorebook = Lorebook(entries: []);
      }
    } else {
      lorebook = Lorebook(entries: []);
    }
    return model.World(
      id: row.id,
      name: row.name,
      description: row.description,
      lorebook: lorebook,
      linkedCharacterName: row.linkedCharacterName,
      linkedCharacterId: row.linkedCharacterId,
      coverImage: row.coverImage,
      sourceId: row.sourceId,
      formatVersion: row.formatVersion,
      biomeId: row.biomeId,
      biomeJson: row.biomeJson,
      injectDescription: row.injectDescription,
      climateEnabled: row.climateEnabled,
      placeTraits: _tryDecodeMap(row.placeTraits),
    );
  }

  /// Defensive JSON-map decode for the place_traits column (null/garbage →
  /// null → all-default traits).
  static Map<String, dynamic>? _tryDecodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  WorldsCompanion _toCompanion(model.World world) {
    return WorldsCompanion(
      id: Value(world.id),
      name: Value(world.name),
      description: Value(world.description),
      lorebook: Value(jsonEncode(world.lorebook.toJson())),
      linkedCharacterName: Value(world.linkedCharacterName),
      linkedCharacterId: Value(world.linkedCharacterId),
      coverImage: Value(world.coverImage),
      sourceId: Value(world.sourceId),
      formatVersion: Value(world.formatVersion),
      biomeId: Value(world.biomeId),
      biomeJson: Value(world.biomeJson),
      injectDescription: Value(world.injectDescription),
      climateEnabled: Value(world.climateEnabled),
      placeTraits: Value(
        world.placeTraits.isEmpty ? null : jsonEncode(world.placeTraits),
      ),
    );
  }

  Future<void> loadWorlds() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _storageService.initialized;
      final dbWorlds = await _db.getAllWorlds();
      _worlds
        ..clear()
        ..addAll(dbWorlds.map(_fromRow));
      _resolveAvatarPaths(_worlds);
      // One-time: drop legacy "Aerin's Lorebook" clones so Worlds = places.
      await _maybePurgeCharacterLinkedWorlds();
    } catch (e) {
      debugPrint('Error loading worlds: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _maybePurgeCharacterLinkedWorlds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_purgePrefKey) == true) return;
      final result = await purgeCharacterLinkedWorlds();
      // Only mark the one-shot done when every clone was exported+deleted —
      // a skipped world (failed recovery export) must be retried next launch,
      // not stranded forever behind the pref.
      if (result.skipped == 0) {
        await prefs.setBool(_purgePrefKey, true);
      } else {
        debugPrint(
          '[Worlds] purge left ${result.skipped} world(s) in place '
          '(recovery export failed) — retrying next launch',
        );
      }
      final n = result.deleted;
      if (n > 0) {
        final recovery = p.join(
          _storageService.worldsDir.path,
          'recovered_character_lore_clones',
        );
        debugPrint(
          '[Worlds] Purged $n character-linked lore clones '
          '(character card lore untouched; any edits that lived only on the '
          'world were saved as .fpworld under $recovery)',
        );
      }
    } catch (e) {
      debugPrint('[Worlds] character-linked purge skipped: $e');
    }
  }

  /// Delete every legacy character-world clone and strip references from
  /// characters / groups / chat_worlds. Character card lorebooks are untouched.
  ///
  /// **Safety:** each doomed world is exported as `.fpworld` into
  /// `worlds/recovered_character_lore_clones/` *before* the hard delete, so
  /// users who edited "Aerin's Lorebook" in the Worlds tab (edits that never
  /// flowed back to the card) can re-import those packages. A world whose
  /// export FAILS is not deleted — it stays in place and the caller retries
  /// on a later launch. Returns how many worlds were deleted and how many
  /// were skipped that way.
  Future<({int deleted, int skipped})> purgeCharacterLinkedWorlds() async {
    final doomed = _worlds.where(isCharacterLinkedWorld).toList();
    if (doomed.isEmpty) return (deleted: 0, skipped: 0);

    // Lossless edge case: export before hard delete (Claude review 2026-07-28).
    final recoveryDir = Directory(
      p.join(_storageService.worldsDir.path, 'recovered_character_lore_clones'),
    );
    try {
      await recoveryDir.create(recursive: true);
    } catch (e) {
      debugPrint('[Worlds] could not create recovery dir: $e');
    }

    final exportedWorlds = <model.World>[];
    var skipped = 0;
    for (final w in doomed) {
      // The export may be the user's only copy of world-only lore edits, so
      // a failed export means this world is NOT touched this launch.
      try {
        final safe = _safeFileStem(w.name);
        final idShort = w.id.length >= 8 ? w.id.substring(0, 8) : w.id;
        final out = p.join(recoveryDir.path, '${safe}_$idShort.fpworld');
        await exportFpWorld(w, out);
      } catch (e) {
        debugPrint(
          '[Worlds] recovery export failed for "${w.name}" (${w.id}) — '
          'keeping the world: $e',
        );
        skipped++;
        continue;
      }
      exportedWorlds.add(w);
    }
    if (exportedWorlds.isEmpty) {
      debugPrint(
        '[Worlds] purge: 0/${doomed.length} clones exportable '
        '($skipped kept) → ${recoveryDir.path}',
      );
      return (deleted: 0, skipped: skipped);
    }
    final ids = {for (final w in exportedWorlds) w.id};
    final names = {for (final w in exportedWorlds) w.name};

    // Strip refs BEFORE deleting rows (Grok review): if the strip throws,
    // nothing has been deleted yet, so the next launch re-dooms the same
    // worlds and retries the whole purge. Strip-after-delete had a pref-lock
    // hole — a partial run deleted worlds, the next launch saw no doomed
    // rows, reported clean, and locked the one-shot pref with dangling
    // character/group refs never stripped.
    await _db.stripWorldRefsFromCharactersAndGroups(ids: ids, names: names);

    // Keep in-memory character/group lists in sync without a full app restart.
    final charRepo = _characterRepository;
    if (charRepo != null) {
      for (final c in charRepo.characters) {
        final before = c.worldNames.length;
        c.worldNames = [
          for (final ref in c.worldNames)
            if (!ids.contains(ref) && !names.contains(ref)) ref,
        ];
        if (c.worldNames.length != before) {
          try {
            await charRepo.updateCharacter(c);
          } catch (e) {
            debugPrint('[Worlds] strip worldNames on ${c.name}: $e');
          }
        }
      }
    }
    final groupRepo = _groupRepository;
    if (groupRepo != null) {
      for (final g in List.of(groupRepo.groups)) {
        final before = g.worldIds.length;
        g.worldIds = [
          for (final ref in g.worldIds)
            if (!ids.contains(ref) && !names.contains(ref)) ref,
        ];
        if (g.worldIds.length != before) {
          try {
            await groupRepo.save(g);
          } catch (e) {
            debugPrint('[Worlds] strip worldIds on group ${g.name}: $e');
          }
        }
      }
    }

    // Delete only now that refs are gone. A failed delete leaves an
    // unreferenced clone row that the next launch re-dooms and retries.
    var deleted = 0;
    for (final w in exportedWorlds) {
      await _db.deleteChatWorldLinksForWorld(w.id);
      await _db.deleteWorldById(w.id);
      deleted++;
    }
    _worlds.removeWhere((w) => ids.contains(w.id));
    debugPrint(
      '[Worlds] purged $deleted/${doomed.length} clones '
      '($skipped kept on failed export) → ${recoveryDir.path}',
    );

    notifyListeners();
    return (deleted: deleted, skipped: skipped);
  }

  /// Filesystem-safe stem for recovery exports (no path separators).
  static String _safeFileStem(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return 'world';
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  }

  /// Rename display name only — attachments use UUID and need no cascade.
  Future<void> renameWorld(model.World world, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == world.name) return;
    if (await _db.getWorldByName(trimmed) != null) {
      throw StateError('A world named "$trimmed" already exists.');
    }
    world.name = trimmed;
    await _db.updateWorld(_toCompanion(world));
    notifyListeners();
  }

  Future<void> saveWorld(model.World world) async {
    if (world.id.isEmpty) {
      world.id = _uuid.v4();
    }
    // Places only — never re-create character-linked clones via save.
    world.linkedCharacterName = null;
    world.linkedCharacterId = null;
    if (world.description.trim().toLowerCase().startsWith(
      'auto-imported from character card',
    )) {
      world.description = '';
    }
    final existing = await _db.getWorldById(world.id);
    if (existing != null) {
      await _db.updateWorld(_toCompanion(world));
    } else {
      // Name collision on create → auto-rename (Keep both).
      final taken = await _db.getWorldByName(world.name);
      if (taken != null && taken.id != world.id) {
        world.name = uniqueWorldName(
          world.name,
          (n) => _worlds.any((w) => w.name == n && w.id != world.id),
        );
      }
      await _db.insertWorld(_toCompanion(world));
    }

    final index = _worlds.indexWhere((w) => w.id == world.id);
    if (index != -1) {
      _worlds[index] = world;
    } else {
      _worlds.add(world);
    }
    if (world.linkedCharacterName != null || world.linkedCharacterId != null) {
      _resolveAvatarPaths([world]);
    }
    notifyListeners();
  }

  Future<void> deleteWorld(model.World world) async {
    await _db.deleteWorldById(world.id);
    await _db.deleteChatWorldLinksForWorld(world.id);
    _worlds.removeWhere((w) => w.id == world.id);
    notifyListeners();
  }

  /// Import .fpworld or bare lorebook from a file. See [importWorldJson].
  Future<model.World> importWorld(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('World file must be a JSON object');
    }
    return importWorldJson(Map<String, dynamic>.from(decoded));
  }

  /// The ONE full-package import path (desktop file picker AND the web
  /// facade): keeps climate, place traits, and lore. Always creates a new
  /// row (Keep both on name collision); preserves the package id as
  /// [model.World.sourceId] and assigns a fresh local id.
  Future<model.World> importWorldJson(Map<String, dynamic> json) async {
    final package = decodeFpWorld(json);
    final world = package.world;

    // Fresh local identity; remember provenance.
    world.sourceId ??= world.id.isNotEmpty ? world.id : null;
    world.id = _uuid.v4();
    world.name = uniqueWorldName(
      world.name,
      (n) => _worlds.any((w) => w.name == n),
    );

    if (package.biome != null) {
      final biome = Biome.fromJson(package.biome!);
      if (Biome.builtInById(biome.id) != null) {
        world.biomeId = biome.id;
        world.biomeJson = null;
      } else {
        world.biomeId = biome.id;
        world.biomeJson = biome.toJsonString();
      }
    }

    await saveWorld(world);
    return world;
  }

  /// The ONE .fpworld envelope builder (file export AND Stoop upload): embeds
  /// the resolved biome so importers get climate without built-ins, plus place
  /// traits, lore, and the cover image already carried by [model.World].
  Map<String, dynamic> fpWorldJson(model.World world) {
    final biome = world.climateEnabled
        ? Biome.resolve(
            biomeId: world.biomeId,
            biomeJson: world.biomeJson,
          ).toJson()
        : null;
    return encodeFpWorld(world: world, biome: biome);
  }

  /// Export as .fpworld (full place package). Prefer this over ST-only.
  Future<void> exportFpWorld(model.World world, String outputPath) async {
    final file = File(outputPath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(fpWorldJson(world)),
    );
  }

  /// Legacy ST world-info export (lore only).
  Future<void> exportWorld(model.World world, String outputPath) async {
    final file = File(outputPath);
    await file.writeAsString(
      jsonEncode(
        encodeStWorldInfo(
          world.lorebook,
          name: world.name,
          description: world.description,
        ),
      ),
    );
  }

  // ── Chat attachments ────────────────────────────────────────────────

  Future<List<String>> getChatWorldIds(String chatId) =>
      _db.getWorldIdsForChat(chatId);

  Future<List<model.World>> getChatWorlds(String chatId) async {
    final ids = await getChatWorldIds(chatId);
    return [
      for (final id in ids)
        if (worldById(id) != null) worldById(id)!,
    ];
  }

  Future<void> setChatWorlds(String chatId, List<String> worldIds) async {
    await _db.setChatWorlds(chatId, worldIds);
    // Whatever the user chose — including an empty list — is now this chat's
    // decision, and nothing may back-fill over it later.
    await _db.markChatWorldsInitialized(chatId);
    notifyListeners();
  }

  /// Record that a chat's world attachments are settled without changing them.
  Future<void> markChatWorldsDecided(String chatId) =>
      _db.markChatWorldsInitialized(chatId);

  /// Give a chat the worlds its character carries, but ONLY if the chat has
  /// never had that decision made. Returns true when it seeded.
  /// This is what rescues chats created before their character had a world:
  /// they predate any attachment, so their empty list is "undecided", not
  /// "the user removed them".
  Future<bool> backfillChatWorldsFromCharacter({
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
    await setChatWorlds(chatId, ids); // marks it decided
    debugPrint('[Worlds] back-filled chat $chatId from its character');
    return true;
  }

  Future<void> attachWorldToChat(String chatId, String worldId) async {
    final ids = await getChatWorldIds(chatId);
    if (ids.contains(worldId)) return;
    await setChatWorlds(chatId, [...ids, worldId]);
  }

  Future<void> detachWorldFromChat(String chatId, String worldId) async {
    final ids = await getChatWorldIds(chatId);
    await setChatWorlds(chatId, [
      for (final id in ids)
        if (id != worldId) id,
    ]);
  }

  /// Attach worlds newly added to a CHARACTER onto that character's existing
  /// chats that don't have any yet.
  ///
  /// Creation-time seeding only covers chats made *after* the character had a
  /// world, so a chat opened first and given a world later kept its temperate
  /// default forever — the climate, the Setting prose and the Places panel all
  /// read chat attachments, not the character's list.
  ///
  /// Only [addedRefs] (the diff from this edit) propagate, and only onto chats
  /// with an EMPTY attachment list. That keeps two things true: editing a
  /// character for unrelated reasons never re-attaches anything, and a chat the
  /// user deliberately sent somewhere else is never dragged back.
  /// Returns the ids of the chats that changed, so a live session can refresh.
  Future<List<String>> applyAddedCharacterWorldsToChats({
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

  /// Copy template world refs (group template ids or character world names)
  /// onto a new chat (session). Refs may be UUIDs or names; unresolved refs
  /// are dropped with a debug note.
  Future<void> applyTemplateWorldsToChat(
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

  // ── Biome spans (phase 1) ───────────────────────────────────────────

  Future<void> setChatBiome({
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

  /// Raw span rows for [BiomeSchedule] hydrate (ordered by day ASC).
  Future<List<({int effectiveFromDay, String biomeJson})>> getChatBiomeSpanRows(
    String chatId,
  ) async {
    final spans = await _db.getBiomeSpansForChat(chatId);
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
    final rows = await getChatBiomeSpanRows(chatId);
    return BiomeSchedule.fromJsonSpans(
      rows: rows,
      worldDefault: worldDefault,
    ).biomeAt(day);
  }
}
