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

part of 'character_repository.dart';

/// Card CRUD: create, hard-delete (single + bulk), full update, image-path
/// touch-up, and the per-character memorySources column. Extracted verbatim
/// from `character_repository.dart` (zero behaviour change) to shrink the
/// god file — see the split map for that file. As `part of` the same
/// library, these reach the private DB/storage/list state exactly as the
/// in-class methods did.
extension CharacterRepositoryCrud on CharacterRepository {
  Future<void> addCharacter(CharacterCard character) async {
    // Store basename only in DB for cross-platform portability
    final dbImagePath = character.imagePath != null
        ? _toBasename(character.imagePath!)
        : null;
    final dbId = await _db.insertCharacterReturningId(
      CharactersCompanion(
        name: Value(character.name),
        description: Value(character.description),
        personality: Value(character.personality),
        scenario: Value(character.scenario),
        firstMessage: Value(character.firstMessage),
        mesExample: Value(character.mesExample),
        systemPrompt: Value(character.systemPrompt),
        postHistoryInstructions: Value(character.postHistoryInstructions),
        alternateGreetings: Value(jsonEncode(character.alternateGreetings)),
        tags: Value(jsonEncode(character.tags)),
        imagePath: Value(dbImagePath),
        ttsVoice: Value(character.ttsVoice),
        lorebook: Value(
          character.lorebook != null
              ? jsonEncode(character.lorebook!.toJson())
              : null,
        ),
        worldNames: Value(jsonEncode(character.worldNames)),
      ),
    );
    character.dbId = dbId;
    _characters.add(character);
    _notify();
  }

  Future<void> deleteCharacter(
    CharacterCard character, {
    WorldRepository? worldRepo,
    Directory? chatsDir,
  }) async {
    _clearCoverCache();
    // Remove from in-memory list
    _characters.remove(character);
    _notify();

    // Delete from database (soft-delete the character row so the deletion flag
    // propagates through cloud DB sync + merge and prevents resurrection).
    if (character.dbId != null) {
      await _db.softDeleteCharacterById(character.dbId!);
    }

    // Delete the PNG file from disk
    if (character.imagePath != null) {
      try {
        final file = File(character.imagePath!);
        if (await file.exists()) {
          await file.delete();
          print('AG_DEBUG: Deleted character file: ${character.imagePath}');
        }
      } catch (e) {
        print('Error deleting character file: $e');
      }

      // Delete associated chat history folder
      if (chatsDir != null) {
        try {
          final charId = p.basenameWithoutExtension(character.imagePath!);
          final chatFolder = Directory('${chatsDir.path}/$charId');
          if (await chatFolder.exists()) {
            await chatFolder.delete(recursive: true);
            print('AG_DEBUG: Deleted chat folder: ${chatFolder.path}');
          }
        } catch (e) {
          print('Error deleting chat folder: $e');
        }
      }
    }

    // Delete the avatar-gallery media folder (Characters/<safeName>/ holding
    // avatars/ + looks/) — the PNG is already hard-deleted above, so leaving
    // this behind just leaks gallery images on disk (a full pack is ~28 files)
    // for every deleted character. Best-effort; name-keyed like the write path.
    try {
      final safeName = _mediaFolderName(character.name);
      // Only delete when NO other character shares this folder — sanitized
      // names collide ("A!" and "A" → same folder), and nuking a shared folder
      // would take another character's gallery with it. When ambiguous, leave
      // it (a small disk leak) rather than risk cross-character data loss.
      final shared = _characters.any(
        (c) => c.dbId != character.dbId && _mediaFolderName(c.name) == safeName,
      );
      if (safeName.isNotEmpty && !shared) {
        final mediaDir = Directory(
          p.join(_storage.charactersDir.path, safeName),
        );
        if (await mediaDir.exists()) {
          await mediaDir.delete(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('[CharacterRepository] delete media folder failed: $e');
    }

    // Remove any linked world
    if (worldRepo != null) {
      final linkedWorld = worldRepo.worlds
          .where((w) => w.linkedCharacterName == character.name)
          .toList();
      for (final world in linkedWorld) {
        await worldRepo.deleteWorld(world);
      }
    }
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

  /// [notify] = false persists silently (DB + PNG still written): the Avatar
  /// Gallery's ★ writes per click, and broadcasting each one repainted the
  /// whole home grid behind the open dialog. Silent callers MUST follow up
  /// with [notifyCharactersChanged] when their surface closes.
  Future<void> updateCharacter(CharacterCard card, {bool notify = true}) async {
    if (card.imagePath == null) return;
    _clearCoverCache(); // avatar files may have changed under a stable key
    _bumpCoverEpoch();

    if (notify) {
      _isLoading = true;
      _notify();
    }

    try {
      final v2Service = V2CardService();

      // Resolve imagePath to a real filesystem path before any I/O.
      // In-memory CharacterCards are supposed to carry full absolute paths
      // (see loadCharacters + the convention documented in chat_page.dart:2381).
      // However, defensive handling here prevents crashes if any caller ever
      // passes a bare basename (as the full-page editor used to do before the
      // fix in edit_character_page.dart). We also normalize the card so that
      // after updateCharacter the object always holds a full path.
      final fsPath = p.isAbsolute(card.imagePath!)
          ? card.imagePath!
          : _resolveImagePath(card.imagePath!);
      card.imagePath = fsPath;

      // Ensure stableId before embedding (carries for existing, generates for legacy on touch).
      card.frontPorchExtensions?.ensureStableId();

      // Overwrite the existing file with updated data (now using a guaranteed
      // absolute path that lands in the correct Characters/ directory).
      await v2Service.saveCardAsPng(card, fsPath, fsPath);

      // Update in database — store basename only for cross-platform portability
      if (card.dbId != null) {
        // A rename must carry the avatar-gallery media with it: expression and
        // look PNGs live under Characters/<safeName>/{avatars,looks}/, keyed on
        // the CURRENT name at both write and read time. Capture the OLD name
        // before the DB write so we can move the folder AFTER it — DB-first so
        // a failed move leaves the (pre-existing) blank-gallery bug (logged),
        // never the worse split-brain of "DB says new name, files under old".
        String? oldNameForMove;
        String? oldImagePath;
        try {
          final existing = await _db.getCharacterById(card.dbId!);
          oldNameForMove = existing.name;
          oldImagePath = existing.imagePath;
        } catch (_) {
          oldNameForMove = null;
        }

        final dbImagePath = card.imagePath != null
            ? _toBasename(card.imagePath!)
            : null;
        final fromId = stableGroupIdFrom(
          oldImagePath,
          oldNameForMove ?? card.name,
        );
        final toId = stableGroupIdFrom(dbImagePath, card.name);
        await _db.transaction(() async {
          await _db.updateCharacter(
            CharactersCompanion(
              id: Value(card.dbId!),
              name: Value(card.name),
              description: Value(card.description),
              personality: Value(card.personality),
              scenario: Value(card.scenario),
              firstMessage: Value(card.firstMessage),
              mesExample: Value(card.mesExample),
              systemPrompt: Value(card.systemPrompt),
              postHistoryInstructions: Value(card.postHistoryInstructions),
              alternateGreetings: Value(jsonEncode(card.alternateGreetings)),
              tags: Value(jsonEncode(card.tags)),
              imagePath: Value(dbImagePath),
              ttsVoice: Value(card.ttsVoice),
              lorebook: Value(
                card.lorebook != null
                    ? jsonEncode(card.lorebook!.toJson())
                    : null,
              ),
              worldNames: Value(jsonEncode(card.worldNames)),
              updatedAt: Value(DateTime.now()),
            ),
          );
          // Portrait basename IS the portable id for quests / RAG / Data Bank
          // / Journal / Growth. Changing it without a re-key is the cleanup
          // wipe the gallery used to trigger on "Replace portrait".
          if (fromId != toId && fromId.isNotEmpty && toId.isNotEmpty) {
            await _db.rekeyStableCharacterId(fromId, toId);
          }
        });

        // Move the gallery media to match the new name, AFTER the DB commit.
        // Best-effort: a failure here must not block the rename (the card text
        // is what the user asked to save) — it only logs, leaving the media
        // stranded (recoverable) rather than risking loss.
        if (oldNameForMove != null) {
          try {
            await _moveCharacterMediaFolder(oldNameForMove, card.name);
          } catch (e) {
            debugPrint('[CharacterRepository] Avatar folder move skipped: $e');
          }
        }
      }

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
      if (notify) _notify();
    } catch (e) {
      print('Error updating character: $e');
      rethrow;
    } finally {
      if (notify) {
        _isLoading = false;
        _notify();
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
    final fsPath = p.isAbsolute(imagePath)
        ? imagePath
        : _resolveImagePath(imagePath);
    card.imagePath = fsPath;
    await _db.updateCharacterImagePath(id, _toBasename(fsPath));

    final index = _characters.indexWhere((candidate) => candidate.dbId == id);
    if (index != -1) {
      _characters[index].imagePath = fsPath;
    }
    if (notify) _notify();
  }

  /// Update a character's image path and persist to DB + PNG.
  Future<void> setCharacterImagePath(
    CharacterCard card,
    String imagePath,
  ) async {
    card.imagePath = imagePath;
    await updateCharacter(card);
  }

  /// Read the JSON-encoded [memorySources] list for a character.
  Future<List<String>> getMemorySources(String characterDbId) async {
    try {
      final dbChar = await _db.getCharacterById(characterDbId);
      final ms = dbChar.memorySources;
      if (ms.isEmpty || ms == '[]') return [];
      return List<String>.from(
        (jsonDecode(ms) as List).map((e) => e.toString()),
      );
    } catch (e) {
      debugPrint('[CharacterRepository] Failed to get memorySources: $e');
      return [];
    }
  }

  /// Write memorySources for a character (JSON-encoded list of character IDs).
  Future<void> setMemorySources(
    String characterDbId,
    List<String> sources,
  ) async {
    try {
      await _db.updateCharacter(
        CharactersCompanion(
          id: Value(characterDbId),
          memorySources: Value(jsonEncode(sources)),
        ),
      );
    } catch (e) {
      debugPrint('[CharacterRepository] Failed to set memorySources: $e');
      rethrow;
    }
  }
}
