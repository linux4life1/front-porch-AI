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

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_store/character_store.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart'
    show promoteLookOverPortrait;
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/utils/utils.dart';

class CharacterRepository extends ChangeNotifier {
  AppDatabase _db;
  final StorageService _storage;
  final List<CharacterCard> _characters = [];
  bool _isLoading = false;

  /// Test-only stall after a load marks itself in flight. Null in the app,
  /// so production loads do not wait. Lets a test hold the constructor's
  /// load open instead of hoping the database is slow.
  @visibleForTesting
  static Future<void> Function()? debugPauseLoad;

  Future<void>? _loadInFlight;
  bool _reloadAfterFlight = false;

  List<CharacterCard> get characters => List.unmodifiable(_characters);
  bool get isLoading => _isLoading;

  /// The library load in flight, or a finished future when none is. Waits
  /// without starting another pass (a second [loadCharacters] would).
  Future<void> get whenLoaded => _loadInFlight ?? Future<void>.value();

  /// True when the last load pass read the library: no database error, and
  /// the storage root was known when the portraits were read (without it
  /// they resolve under the wrong folder, so cards have no settings).
  bool get libraryLoaded => _libraryLoaded;
  bool _libraryLoaded = false;

  /// All unique tags across all characters (for autocomplete)
  List<String> get allTags {
    final tags = <String>{};
    for (final c in _characters) {
      tags.addAll(c.tags);
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  /// Returns a CharacterCard by DB UUID (prefers in-memory list for freshness,
  /// falls back to DB query + parse). Used by export flows.
  Future<CharacterCard?> getCharacterCardById(String id) async {
    // Prefer in-memory (may have unsaved edits in edge cases, though normally DB is authoritative)
    for (final c in _characters) {
      if (c.dbId == id) return c;
    }
    // Fallback: query DB and parse (keeps export working even during partial loads)
    try {
      final row = await _db.getCharacterById(id);
      return characterFromRow(row);
    } catch (_) {
      return null;
    }
  }

  CharacterRepository(this._db, this._storage) {
    loadCharacters();
  }

  late final _loader = CharacterLibraryLoader(_storage);
  late final _media = CharacterMediaStore(
    db: () => _db,
    storage: _storage,
    characters: () => _characters,
    cardById: getCharacterCardById,
    saveCardSilently: (card) => updateCharacter(card, notify: false),
  );
  late final _writer = CharacterCardWriter(
    db: () => _db,
    media: _media,
    resolveImagePath: _loader.resolveImagePath,
  );
  // Callbacks go through the members so subclass overrides still apply.
  late final _importer = CharacterImporter(
    db: () => _db,
    storage: _storage,
    characters: () => _characters,
    findByStableId: findByStableId,
    updateCharacter: (card) => updateCharacter(card),
    clearGalleryLooks: clearGalleryLooks,
    addToLibrary: _characters.add,
  );

  /// Update the database reference after a library swap replaces the DB file.
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  /// Loads the library. A call that arrives while one is already running
  /// waits for it, then runs one more pass so the await cannot return
  /// against an empty or partial list.
  Future<void> loadCharacters() {
    if (_loadInFlight != null) {
      _reloadAfterFlight = true;
      return _loadInFlight!;
    }
    _loadInFlight = _loadPasses();
    return _loadInFlight!;
  }

  Future<void> _loadPasses() async {
    try {
      do {
        _reloadAfterFlight = false;
        await _loadCharactersOnce();
      } while (_reloadAfterFlight);
    } finally {
      _loadInFlight = null;
    }
  }

  Future<void> _loadCharactersOnce() async {
    // Import paths set _isLoading themselves and do not take _loadInFlight.
    // Skipping here keeps those passes from interleaving a second clear/fill.
    if (_isLoading) return;

    // Full reload = the path that picks up EXTERNAL changes (Character
    // Card Forge writes files/DB directly, manual PNG swaps, the toolbar
    // refresh) — the cover cache must not survive it, or a file replaced
    // on disk under an unchanged star/portrait key would render stale.
    _clearCoverCache();

    _isLoading = true;
    notifyListeners();
    final pause = debugPauseLoad;
    if (pause != null) await pause();
    final traceStart = DateTime.now();

    try {
      _libraryLoaded = await _loader.loadInto(_db, _characters);
    } catch (e) {
      _libraryLoaded = false;
      debugPrint('[CharacterRepository] Error loading characters from DB: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      StartupTrace.mark(
        'CharacterRepository.loadCharacters DONE — ${_characters.length} chars'
        ' in ${DateTime.now().difference(traceStart).inMilliseconds}ms'
        ' (home grid is now populated)',
      );
    }
  }

  /// Delete PNG files in the Characters directory that are not referenced
  /// by any loaded character. Cleans up orphans left when the database is
  /// swapped or a character is deleted without its file.
  ///
  /// Returns 0 and deletes nothing while a load is in flight. The in-memory
  /// list is empty or partial then, and a sweep would treat live portraits
  /// as orphans.
  Future<int> cleanOrphanedPngs() async {
    if (isLoading) return 0;
    return _loader.cleanOrphanedPngs(_characters);
  }

  /// Library characters whose display name equals [name] (exact match).
  /// Used by the single-file import collision dialog.
  List<CharacterCard> charactersWithName(String name) {
    return _characters.where((c) => c.name == name).toList(growable: false);
  }

  /// Library character whose PNG-carried stableId matches [stableId], if any.
  CharacterCard? findByStableId(String? stableId) {
    if (stableId == null || stableId.isEmpty) return null;
    for (final c in _characters) {
      if (c.frontPorchExtensions?.stableId == stableId) return c;
    }
    return null;
  }

  /// One deferred broadcast for surfaces that persisted silently
  /// (updateCharacter notify: false) — fired when their dialog closes.
  void notifyCharactersChanged() {
    _clearCoverCache();
    _bumpCoverEpoch();
    notifyListeners();
  }

  late final _covers = CharacterCoverCache(_storage);

  /// Bumped whenever cover bytes may have changed under a stable path (in-place
  /// portrait overwrite). Home grid [Image.file] keys include this so Done
  /// after gallery bootstrap refreshes the face without needing a ★ re-click.
  int coverEpoch = 0;

  void _clearCoverCache() => _covers.clear();

  void _bumpCoverEpoch() => coverEpoch++;

  /// The file to bake as the character's exported / Stoop card cover: the ★
  /// starred avatar (a gallery look OR an expression image) when it's set and
  /// present on disk, else the library portrait (`imagePath`). Null when neither
  /// resolves. Lets a user pick their best render (an outfit, a mood) as the
  /// card's face without touching the in-app portrait.
  ///
  /// [card] must be a HYDRATED library card (`avatarImages` loaded) for the star
  /// to resolve — a bare card silently falls back to the portrait. Every PNG
  /// bake / upload path should route through this so the star works everywhere.
  File? coverImageFileFor(CharacterCard card) =>
      _covers.fileFor(card, epoch: coverEpoch);

  // ── Card CRUD ─────────────────────────────────────────────────────────

  Future<void> addCharacter(CharacterCard character) async {
    character.dbId = await _writer.insert(character);
    _characters.add(character);
    notifyListeners();
  }

  Future<void> deleteCharacter(
    CharacterCard character, {
    WorldRepository? worldRepo,
    Directory? chatsDir,
  }) async {
    _clearCoverCache();
    _characters.remove(character);
    notifyListeners();
    await _writer.deleteStored(
      character,
      worldRepo: worldRepo,
      chatsDir: chatsDir,
    );
  }

  /// Bulk delete (mass select / delete-folder-with-characters). Same pipeline
  /// as [deleteCharacter] per card — soft-delete row, remove PNG, remove chat
  /// history, drop linked worlds — with progress reported per card so the UI
  /// can show a counter over a 100+ card purge (the accidental-bulk-import
  /// case this exists for). Returns how many were deleted.
  Future<int> deleteCharacters(
    List<CharacterCard> cards, {
    WorldRepository? worldRepo,
    Directory? chatsDir,
    void Function(int done, int total)? onProgress,
  }) async {
    var done = 0;
    for (final card in cards) {
      await deleteCharacter(card, worldRepo: worldRepo, chatsDir: chatsDir);
      done++;
      onProgress?.call(done, cards.length);
    }
    return done;
  }

  Future<void> _updateCharacter(
    CharacterCard card, {
    required bool notify,
  }) async {
    _clearCoverCache(); // avatar files may have changed under a stable key
    _bumpCoverEpoch();

    if (notify) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      await _writer.persistUpdate(card);

      // Update the list entry. Prefer dbId (stable) so a first-time
      // imagePath assignment still replaces the list row that was loaded
      // with a null path — path-only match used to leave a stale null-path
      // entry and made addLook think the card still had no portrait.
      final index = _characters.indexWhere(
        (c) =>
            (card.dbId != null && c.dbId == card.dbId) ||
            (card.imagePath != null && c.imagePath == card.imagePath),
      );
      if (index != -1) {
        _characters[index] = card;
      }
      if (notify) notifyListeners();
    } catch (e) {
      print('Error updating character: $e');
      rethrow;
    } finally {
      if (notify) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Persist only [card]'s image path, without serializing its other fields
  /// into either SQLite or the PNG.
  ///
  /// This is the gallery portrait-replacement path: the portrait writer has
  /// already preserved the existing PNG `chara` payload. The database helper
  /// re-keys filename-owned rows when a missing/external portrait requires a
  /// genuinely new basename.
  Future<void> updateCharacterImagePathOnly(
    CharacterCard card, {
    bool notify = true,
  }) async {
    final id = card.dbId;
    final imagePath = card.imagePath;
    if (id == null || imagePath == null) return;

    _clearCoverCache();
    _bumpCoverEpoch();
    final fsPath = _writer.absoluteImagePath(imagePath);
    card.imagePath = fsPath;
    await evictPortraitImage(File(fsPath));
    await _db.updateCharacterImagePath(id, toBasename(fsPath));

    final index = _characters.indexWhere((candidate) => candidate.dbId == id);
    if (index != -1) {
      _characters[index].imagePath = fsPath;
    }
    if (notify) notifyListeners();
  }

  Future<void> setCharacterImagePath(
    CharacterCard card,
    String imagePath,
  ) async {
    card.imagePath = imagePath;
    await evictPortraitImage(File(_writer.absoluteImagePath(imagePath)));
    await updateCharacter(card);
  }

  Future<List<String>> getMemorySources(String characterDbId) =>
      _writer.memorySources(characterDbId);

  /// Write memorySources for a character (JSON-encoded list of character IDs).
  Future<void> setMemorySources(String characterDbId, List<String> sources) =>
      _writer.setMemorySources(characterDbId, sources);

  // ── Import / duplicate ────────────────────────────────────────────────

  /// Import a character card file (V2 PNG or standalone V2 JSON).
  ///
  /// Update-in-place happens only when:
  /// - the incoming card's [FrontPorchExtensions.stableId] matches a library
  ///   character (FP reimport / realism edit path — preserves chats), or
  /// - [forceReplaceTarget] is set (user chose "Replace existing" in the
  ///   single-file name-collision dialog).
  ///
  /// Same display name alone never overwrites or soft-deletes. Bulk import
  /// and silent callers omit [forceReplaceTarget] so variants land as
  /// separate library entries (issue #161).
  Future<CharacterCard?> importCharacter(
    File file, {
    CharacterCard? forceReplaceTarget,
  }) => _whileLoading(
    () => _importer.importFile(file, forceReplaceTarget: forceReplaceTarget),
  );

  /// Bulk import multiple character PNG files.
  /// [onProgress] is called after each file with (current, total, cardName, error).
  /// Returns a summary map: `{imported: int, failed: int, errors: List<String>}`.
  Future<Map<String, dynamic>> importCharacters(
    List<File> files, {
    void Function(int current, int total, String name, String? error)?
    onProgress,
    bool Function()? isCancelled,
  }) => CharacterImporter.importAll(
    files,
    importOne: importCharacter,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );

  /// With [targetDirOverride] + [skipLibraryInsert] this clones into the
  /// caller's dir (decoupled group private copies, e.g.
  /// `groups/<gid>/avatars/`) without touching the library DB or list.
  /// AI Enhance passes [newNameOverride] (`'<Name> (Enhanced)'`).
  Future<CharacterCard?> duplicateCharacter(
    CharacterCard card, {
    String? targetDirOverride,
    String? forcedBasename,
    bool skipLibraryInsert = false,
    String? newNameOverride,
  }) => _whileLoading(() async {
    try {
      return await _importer.duplicate(
        card,
        targetDirOverride: targetDirOverride,
        forcedBasename: forcedBasename,
        skipLibraryInsert: skipLibraryInsert,
        newNameOverride: newNameOverride,
      );
    } catch (e) {
      debugPrint('[Duplicate] Error duplicating character: $e');
      rethrow;
    }
  });

  Future<T> _whileLoading<T>(Future<T> Function() body) async {
    _isLoading = true;
    notifyListeners();
    try {
      return await body();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Avatar-gallery media ──────────────────────────────────────────────

  /// Get all avatar images for a character from the database.
  Future<List<AvatarImage>> getAvatarImages(String characterId) =>
      _media.avatarImages(characterId);

  /// Add a labeled expression avatar (goes to `avatars/`). Returns the new
  /// avatar id so callers can roll back a partial batch on failure.
  Future<String> addAvatar(
    String characterId,
    String characterName,
    Uint8List imageBytes,
    String? label,
  ) => _media.addAvatar(characterId, characterName, imageBytes, label);

  /// Add a gallery LOOK — a plain alternate avatar (a new outfit, a scene), NOT
  /// an expression image. Non-destructive: written to the character's SEPARATE
  /// `looks/` folder and tagged [AvatarImage.lookLabel] so it stays out of the
  /// emotion pipeline. Returns the new avatar id, or `''` when the bytes were
  /// applied as the **portrait only** (no gallery look row) because the card
  /// had no face or only a solid-color placeholder. Selecting a look (per chat)
  /// remains the caller's job when a real look id is returned.
  Future<String> addLook(
    String characterId,
    String characterName,
    Uint8List imageBytes,
  ) => _media.addLook(characterId, characterName, imageBytes);

  /// Delete gallery looks (`isLook`) for [characterId]. Expression avatars stay.
  Future<void> clearGalleryLooks(String characterId) async {
    for (final img in await getAvatarImages(characterId)) {
      if (img.isLook) await removeAvatar(characterId, img.id);
    }
  }

  /// Remove an avatar image for a character.
  Future<void> removeAvatar(String characterId, String avatarId) =>
      _media.removeAvatar(characterId, avatarId);

  /// Set the prime avatar index for a character.
  Future<void> setPrimeAvatar(String characterId, int primeIndex) =>
      _media.setPrimeAvatar(characterId, primeIndex);

  /// Update the label for an avatar image.
  Future<void> updateAvatarLabel(String avatarId, String label) =>
      _media.updateAvatarLabel(avatarId, label);

  /// Deletes the canonical portrait; a gallery look is promoted in its place.
  /// Returns the promoted look's id (callers clean their own cascades).
  Future<String> deletePortraitPromotingLook(CharacterCard card) =>
      promoteLookOverPortrait(
        card: card,
        storage: _storage,
        updateCharacter: updateCharacter,
        removeAvatar: removeAvatar,
        addLook: addLook,
      );
}

/// Static dispatch keeps a pathless card a no-op on test doubles too.
extension CharacterRepositoryUpdate on CharacterRepository {
  /// [notify] = false persists silently (DB + PNG still written): the Avatar
  /// Gallery's ★ writes per click, and broadcasting each one repainted the
  /// whole home grid behind the open dialog. Silent callers MUST follow up
  /// with [notifyCharactersChanged] when their surface closes.
  Future<void> updateCharacter(CharacterCard card, {bool notify = true}) async {
    if (card.imagePath == null) return;
    await _updateCharacter(card, notify: notify);
  }
}
