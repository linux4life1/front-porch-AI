// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Living Worlds repository: UUID identity, .fpworld export/import, chat
// attachment (chat_worlds), biome fields. Rename no longer cascades — refs
// are ids.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_envelopes.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// What a person sees when they try to save a world with no name.
const kWorldNameRequired = 'Give your world a name.';

class WorldRepository extends ChangeNotifier {
  final StorageService _storageService;
  AppDatabase _db;
  final List<model.World> _worlds = [];
  bool _isLoading = false;
  CharacterRepository? _characterRepository;
  GroupChatRepository? _groupRepository;
  static const _uuid = Uuid();

  List<model.World> get worlds => List.unmodifiable(_worlds);
  bool get isLoading => _isLoading;

  /// Places only — excludes legacy character-lore clones (should be empty after purge).
  List<model.World> get placeWorlds =>
      List.unmodifiable(_worlds.where((w) => !isCharacterLinkedWorld(w)));

  WorldRepository(this._storageService, this._db) {
    _attachments = WorldChatAttachments(this, () => _db);
    _purge = CharacterLinkedWorldPurge(
      repo: this,
      db: () => _db,
      storage: _storageService,
      characters: () => _characterRepository,
      groups: () => _groupRepository,
      dropFromCache: (ids) => _worlds.removeWhere((w) => ids.contains(w.id)),
    );
    _firstLoad = loadWorlds();
  }

  late final WorldChatAttachments _attachments;
  late final CharacterLinkedWorldPurge _purge;

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

  Future<void> loadWorlds() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _storageService.initialized;
      final dbWorlds = await _db.getAllWorlds();
      _worlds
        ..clear()
        ..addAll(dbWorlds.map(worldFromRow));
      _resolveAvatarPaths(_worlds);
      // One-time: drop legacy "Aerin's Lorebook" clones so Worlds = places.
      await _purge.maybePurge();
      await repairBarePlaceSettings(this, _db);
    } catch (e) {
      debugPrint('Error loading worlds: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<({int deleted, int skipped})> purgeCharacterLinkedWorlds() =>
      _purge.purge();

  /// Rename display name only — attachments use UUID and need no cascade.
  Future<void> renameWorld(model.World world, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == world.name) return;
    if (await _db.getWorldByName(trimmed) != null) {
      throw StateError('A world named "$trimmed" already exists.');
    }
    world.name = trimmed;
    await _db.updateWorld(worldToCompanion(world));
    notifyListeners();
  }

  /// Saves run one at a time: the create path reads the taken names, picks a
  /// free "Name (n)", then inserts, and two overlapping creates of one name
  /// (a double-clicked Create World) would both pick the same "(n)" and the
  /// second insert would hit the UNIQUE index on `worlds.name`.
  Future<void> _saveChain = Future<void>.value();

  /// Throws [StateError] ([kWorldNameRequired]) for a blank name: a nameless
  /// world shows as "?" and cannot be told apart in any picker.
  Future<void> saveWorld(model.World world) {
    final run = _saveChain.then((_) => _saveWorld(world));
    // The caller gets [run]'s error; the chain only needs to keep going.
    _saveChain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _saveWorld(model.World world) async {
    if (world.name.trim().isEmpty) throw StateError(kWorldNameRequired);
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
    // Locations: the parent must exist and must not be the world itself or
    // one of its descendants. Checked against the database, not the cache —
    // the cache can still be loading, and a swallowed bad parent would
    // strand every room under it.
    if (world.parentWorldId == null || world.parentWorldId!.isEmpty) {
      world.parentWorldId = null;
    } else {
      final rows = await _db.getAllWorlds();
      final rejection = parentRejection(
        worldId: world.id,
        parentId: world.parentWorldId,
        parents: {for (final r in rows) r.id: r.parentWorldId},
      );
      if (rejection != null) throw StateError(rejection);
    }
    final existing = await _db.getWorldById(world.id);
    if (existing != null) {
      await _db.updateWorld(worldToCompanion(world));
    } else {
      world.name = world.name.trim();
      // Name collision on create → auto-rename (Keep both).
      final taken = await _db.getWorldByName(world.name);
      if (taken != null && taken.id != world.id) {
        // The database, not the cache: the cache can still be loading.
        final names = {for (final w in await _db.getAllWorlds()) w.name};
        world.name = uniqueWorldName(world.name, names.contains);
      }
      await _db.insertWorld(worldToCompanion(world));
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

  /// Deleting a world deletes every place inside it (any depth) along with
  /// their chat attachments. Returns how many places went with it, so the
  /// UI can say so.
  Future<int> deleteWorld(model.World world) async {
    final inside = placesInside(world, _worlds, worldById);
    await _db.deleteWorldTree([world.id, for (final p in inside) p.id]);
    final gone = {world.id, for (final p in inside) p.id};
    _worlds.removeWhere((w) => gone.contains(w.id));
    notifyListeners();
    return inside.length;
  }

  /// Location chain leaf-first (`[self, parent, … root]`) through the
  /// loaded cache; empty for an unknown ref. Roots return themselves alone,
  /// so every pre-v61 chat resolves exactly as before.
  List<model.World> chainFor(String idOrName) {
    final leaf = resolveWorld(idOrName);
    if (leaf == null) return const [];
    return worldChain(leaf, worldById);
  }

  /// The nearest climate-enabled ancestor (or the place itself) — the one
  /// whose weather, biome and traits the chain reads. Null ⇒ the whole
  /// chain is lore-only, or its top-level world has weather off, and this
  /// chat's weather stays off.
  model.World? climateAuthorFor(String idOrName) =>
      climateAuthorOf(chainFor(idOrName));

  /// Where a chat starts when [idOrName] is attached as its Setting: the
  /// world's starred place, else the world itself; null for an unknown ref.
  /// Attach paths only. A scene move to the world itself (breadcrumb,
  /// accepted suggestion) lands on the world, never on its star.
  model.World? startingPlaceFor(String idOrName) {
    final world = resolveWorld(idOrName);
    return world == null ? null : startingPlaceOf(world, worldById);
  }

  /// Star [placeId] as where chats attached to [world] start; null clears
  /// it. Refuses a place outside [world], and puts the old star back if the
  /// save fails so the cache never shows a star the database lacks.
  Future<void> setDefaultPlace(model.World world, String? placeId) async {
    final place = placeId == null ? null : worldById(placeId);
    if (placeId != null &&
        (place == null || !isPlaceInside(place, world, worldById))) {
      throw StateError(kWorldDefaultPlaceOutside);
    }
    final prior = world.defaultPlaceId;
    world.defaultPlaceId = placeId;
    try {
      await saveWorld(world);
    } catch (_) {
      world.defaultPlaceId = prior;
      rethrow;
    }
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
    // A parent id from the sender's library means nothing here; the
    // envelope's ROOT is always imported as a root. Children that ride
    // the `locations` array get re-parented by structure below.
    world.parentWorldId = null;
    // A file with no name imports as "Imported World" (uniqueWorldName), so
    // saveWorld's blank-name refusal never blocks an import.
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

    // The sender's star names the sender's id; it is re-pointed at the
    // imported copy of that place once the locations have fresh ids.
    final senderStar = world.defaultPlaceId;
    world.defaultPlaceId = null;
    await saveWorld(world);
    final ids = <String, String>{};
    await _envelopes.importLocations(package.locations, world.id, 1, ids: ids);
    final star = senderStar == null ? null : ids[senderStar];
    if (star != null) await setDefaultPlace(world, star);
    return world;
  }

  /// The codec that shapes export envelopes and re-homes imported
  /// `locations` arrays (slice 5). It reads the live cache through this
  /// repository's public surface and never stores anything itself, so
  /// the save law and the DB stay owned here alone.
  late final WorldEnvelopeCodec _envelopes = WorldEnvelopeCodec(this);

  /// The ONE .fpworld envelope builder (file export AND Stoop upload): embeds
  /// the resolved biome so importers get climate without built-ins, plus place
  /// traits, lore, and the cover image already carried by [model.World].
  ///
  /// The envelope is always a ROOT's and carries its whole tree, even when
  /// [world] is a place inside it. Shaping lives in [WorldEnvelopeCodec].
  Map<String, dynamic> fpWorldJson(model.World world) => _envelopes.tree(world);

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

  void notify() => notifyListeners();

  // A load still in flight at teardown must not notify a disposed repo.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<List<String>> getChatWorldIds(String chatId) =>
      _attachments.chatWorldIds(chatId);

  Future<ChatPlaceSlots> getChatWorldAttachments(String chatId) =>
      _attachments.chatWorldAttachments(chatId);

  Future<List<model.World>> getChatWorlds(String chatId) =>
      _attachments.chatWorlds(chatId);

  /// Canonical writer: Setting (0..1) + Lore (0..N). Empty both = decided empty.
  Future<void> setChatWorldAttachments(
    String chatId, {
    String? primaryId,
    List<String> loreIds = const [],
  }) => _attachments.setAttachments(
    chatId,
    primaryId: primaryId,
    loreIds: loreIds,
  );

  Future<void> setChatWorlds(
    String chatId,
    List<String> worldIds, {
    bool startAtStar = true,
  }) => _attachments.setFlat(chatId, worldIds, startAtStar: startAtStar);

  /// Record that a chat's world attachments are settled without changing them.
  Future<void> markChatWorldsDecided(String chatId) =>
      _attachments.markDecided(chatId);

  /// Give a chat the worlds its character carries, but ONLY if the chat has
  /// never had that decision made. Returns true when it seeded.
  /// This is what rescues chats created before their character had a world:
  /// they predate any attachment, so their empty list is "undecided", not
  /// "the user removed them".
  Future<bool> backfillChatWorldsFromCharacter({
    required String chatId,
    required List<String> characterWorldRefs,
  }) => _attachments.backfillFromCharacter(
    chatId: chatId,
    characterWorldRefs: characterWorldRefs,
  );

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
  }) => _attachments.applyAddedCharacterWorlds(
    characterId: characterId,
    addedRefs: addedRefs,
  );

  /// Copy template world refs (group template ids or character world names)
  /// onto a new chat (session). Refs may be UUIDs or names; unresolved refs
  /// are dropped with a debug note. A world with a starred place starts the
  /// chat there; a fork passes [startAtStar] false to stay where it was.
  /// [loreRefs] non-null means a split group template: [templateWorldIds]
  /// is its Setting and [loreRefs] its Lore slots.
  Future<void> applyTemplateWorldsToChat(
    String chatId,
    List<String> templateWorldIds, {
    bool startAtStar = true,
    List<String>? loreRefs,
  }) => _attachments.applyTemplate(
    chatId,
    templateWorldIds,
    startAtStar: startAtStar,
    loreRefs: loreRefs,
  );

  Future<void> setChatBiome({
    required String chatId,
    required int dayCount,
    required Biome biome,
  }) => _attachments.setBiome(chatId: chatId, dayCount: dayCount, biome: biome);

  Future<void> copyChatBiomeSpans(String fromChatId, String toChatId) =>
      _attachments.copyBiomeSpans(fromChatId, toChatId);

  /// Raw span rows for [BiomeSchedule] hydrate (ordered by day ASC).
  Future<List<({int effectiveFromDay, String biomeJson})>> getChatBiomeSpanRows(
    String chatId,
  ) => _attachments.biomeSpanRows(chatId);

  Future<Biome> biomeAt({
    required String chatId,
    required int day,
    Biome? worldDefault,
  }) => _attachments.biomeAt(
    chatId: chatId,
    day: day,
    worldDefault: worldDefault,
  );
}
