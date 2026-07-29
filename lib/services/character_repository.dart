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

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/models/avatar_image.dart';
import 'package:front_porch_ai/database/database.dart' hide AvatarImage;

class CharacterRepository extends ChangeNotifier {
  AppDatabase _db;
  final StorageService _storage;
  final List<CharacterCard> _characters = [];
  bool _isLoading = false;

  List<CharacterCard> get characters => List.unmodifiable(_characters);
  bool get isLoading => _isLoading;

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
      return _characterFromRow(row);
    } catch (_) {
      return null;
    }
  }

  CharacterRepository(this._db, this._storage) {
    loadCharacters();
  }

  /// Extract the basename from a potentially full path (handles / and \).
  /// Returns the input unchanged if it's already a basename.
  static String _toBasename(String path) {
    return path.split(RegExp(r'[/\\]')).last;
  }

  /// Resolve a stored image path (basename or full path) to the local full path.
  String _resolveImagePath(String stored) {
    final basename = _toBasename(stored);
    return '${_storage.charactersDir.path}/$basename';
  }

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  Future<void> loadCharacters() async {
    // Re-entrancy guard: the toolbar refresh button (and other callers) can trigger
    // rapid or concurrent calls. Skip redundant work while a load is already in flight.
    // This prevents interleaved _characters mutations and flickering isLoading state.
    // A skipped call also skips the initial _isLoading=true/notify (no spurious flicker for that caller).
    // Fire-and-forget callers (e.g. some web server paths) may be dropped when busy;
    // the in-flight load will still deliver the final update to listeners.
    if (_isLoading) return;

    // Full reload = the path that picks up EXTERNAL changes (Character
    // Card Forge writes files/DB directly, manual PNG swaps, the toolbar
    // refresh) — the cover cache must not survive it, or a file replaced
    // on disk under an unchanged star/portrait key would render stale.
    _clearCoverCache();

    _isLoading = true;
    notifyListeners();

    try {
      final dbChars = await _db.getAllCharacters();

      _characters.clear();

      final missingPngNames = <String>[];

      for (final c in dbChars) {
        final card = _characterFromRow(c);

        // Normalize DB path to basename-only (one-time migration for old full paths).
        // Then resolve to local full path for runtime use.
        if (card.imagePath != null) {
          final basename = _toBasename(card.imagePath!);
          if (basename != card.imagePath) {
            // DB still has a full path — strip it to basename for portability
            if (card.dbId != null) {
              await _db.updateCharacterImagePath(card.dbId!, basename);
            }
          }
          // Always resolve to local full path for runtime use
          card.imagePath = _resolveImagePath(basename);

          // Always read extensions fresh from PNG.
          // V2.5 extensions live only in the PNG tEXt chunk (not in DB).
          // We intentionally do NOT cache previous in-memory values here:
          // the old cache caused edits to be silently overwritten by stale
          // pre-edit values whenever loadCharacters() ran after an edit.
          try {
            final v2Service = V2CardService();
            final reloaded = await v2Service.readCard(card.imagePath!);
            if (reloaded != null) {
              card.frontPorchExtensions = reloaded.frontPorchExtensions;
              card.rawExtensions = reloaded.rawExtensions;
              debugPrint(
                '[CharacterRepository] Loaded PNG extensions for ${card.name}: '
                'realismEnabled=${reloaded.frontPorchExtensions?.realismEnabled}',
              );
            } else {
              debugPrint(
                '[CharacterRepository] No card data found in PNG for ${card.name}',
              );
            }
          } catch (e) {
            if (e is PathNotFoundException ||
                e.toString().contains('No such file')) {
              missingPngNames.add(card.name);
            } else {
              debugPrint(
                '[CharacterRepository] Failed to load PNG for ${card.name}: $e',
              );
            }
          }
        }

        // Load avatar images from DB so they survive hot reloads
        if (card.dbId != null) {
          try {
            final driftAvatars = await _db.getAvatarImagesByCharacterId(
              card.dbId!,
            );
            if (driftAvatars.isNotEmpty) {
              card.avatarImages = driftAvatars
                  .map(
                    (a) => AvatarImage(
                      id: a.id,
                      characterId: a.characterId,
                      filename: a.filename,
                      label: a.label,
                      displayOrder: a.displayOrder,
                      createdAt: a.createdAt,
                    ),
                  )
                  .toList();
              debugPrint(
                '[CharacterRepository] Loaded ${card.avatarImages!.length} avatar images for ${card.name}',
              );
            }
          } catch (e) {
            debugPrint(
              '[CharacterRepository] Failed to load avatar images for ${card.name}: $e',
            );
          }
        }

        _characters.add(card);
      }

      // Summarize missing PNGs once (common when developing from source or after cloud deletes)
      if (missingPngNames.isNotEmpty) {
        debugPrint(
          '[CharacterRepository] ${missingPngNames.length} characters have missing local PNG files '
          '(they can be restored via Cloud Sync): ${missingPngNames.join(", ")}',
        );
      }
    } catch (e) {
      debugPrint('[CharacterRepository] Error loading characters from DB: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete PNG files in the Characters directory that are not referenced
  /// by any character in the database. This cleans up orphans left behind
  /// when the DB is replaced via cloud sync or characters are deleted
  /// without their file being removed.
  Future<int> cleanOrphanedPngs() async {
    try {
      final charDir = _storage.charactersDir;
      if (!await charDir.exists()) return 0;

      // Collect all imagePaths currently referenced by loaded characters
      final referencedPaths = <String>{};
      for (final c in _characters) {
        if (c.imagePath != null) {
          referencedPaths.add(c.imagePath!);
        }
      }

      int deletedCount = 0;
      await for (final entity in charDir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
          if (!referencedPaths.contains(entity.path)) {
            debugPrint(
              '[Cleanup] Deleting orphaned PNG: ${p.basename(entity.path)}',
            );
            await entity.delete();
            deletedCount++;
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint('[Cleanup] Deleted $deletedCount orphaned character PNG(s)');
      }
      return deletedCount;
    } catch (e) {
      debugPrint('[Cleanup] Error cleaning orphaned PNGs: $e');
      return 0;
    }
  }

  /// Convert a DB row into a CharacterCard model.
  CharacterCard _characterFromRow(Character c) {
    List<String> altGreetings = [];
    try {
      altGreetings = List<String>.from(jsonDecode(c.alternateGreetings));
    } catch (_) {}

    List<String> tags = [];
    try {
      tags = List<String>.from(jsonDecode(c.tags));
    } catch (_) {}

    List<String> worldNames = [];
    try {
      worldNames = List<String>.from(jsonDecode(c.worldNames));
    } catch (_) {}

    Lorebook? lorebook;
    if (c.lorebook != null) {
      try {
        lorebook = Lorebook.fromJson(jsonDecode(c.lorebook!));
      } catch (_) {}
    }

    final card = CharacterCard(
      name: c.name,
      description: c.description,
      personality: c.personality,
      scenario: c.scenario,
      firstMessage: c.firstMessage,
      mesExample: c.mesExample,
      systemPrompt: c.systemPrompt,
      postHistoryInstructions: c.postHistoryInstructions,
      alternateGreetings: altGreetings,
      tags: tags,
      imagePath: c.imagePath,
      ttsVoice: c.ttsVoice,
      lorebook: lorebook,
      worldNames: worldNames,
    );
    // Store DB id for lookups
    card.dbId = c.id;
    // Library "date added" — used by the home-screen "Import Date" sort. Reading
    // the real DB column (instead of parsing a timestamp out of the image
    // filename) means cards without the legacy `<name>_<epoch>.png` naming
    // (JSON imports, Chub downloads, renamed files) still sort correctly.
    card.createdAt = c.createdAt;
    card.primeAvatarIndex = c.primeAvatarIndex;
    return card;
  }

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
    notifyListeners();
  }

  void removeCharacter(CharacterCard character) {
    _characters.remove(character);
    notifyListeners();
  }

  Future<void> deleteCharacter(
    CharacterCard character, {
    WorldRepository? worldRepo,
    Directory? chatsDir,
  }) async {
    _clearCoverCache();
    // Remove from in-memory list
    _characters.remove(character);
    notifyListeners();

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
        (c) =>
            c.dbId != character.dbId && _mediaFolderName(c.name) == safeName,
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
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final v2Service = V2CardService();

      // A standalone Character Card V2 `.json` file carries no avatar, so we
      // parse it as text and let the placeholder image be generated on persist.
      // PNG cards embed the same JSON in their `chara` chunk.
      final isJson = file.path.toLowerCase().endsWith('.json');

      CharacterCard? card = isJson
          ? await v2Service.readCardFromJsonFile(file.path)
          : await v2Service.readCard(file.path);

      // Fallback if no card data could be parsed
      card ??= CharacterCard(
        name: p.basenameWithoutExtension(file.path),
        description: '',
        imagePath: isJson ? null : file.path,
      );

      return await _persistImportedCharacterCard(
        card,
        // JSON has no image to copy; persist synthesizes a placeholder instead.
        sourceFileForCopy: isJson ? null : file,
        forceReplaceTarget: forceReplaceTarget,
      );
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Internal helper that persists an already-parsed CharacterCard.
  ///
  /// Collision policy (issue #161 + history-preserving reimport):
  /// - **stableId match** → update in place (reuse dbId + PNG path; chats kept)
  /// - **[forceReplaceTarget]** → same update path when the user explicitly
  ///   chose Replace on a same-name card that has no stableId match
  /// - **name-only collision** → fresh insert (never soft-delete peers)
  ///
  /// Ensures stableId is present before embedding via saveCardAsPng.
  /// When [sourceFileForCopy] is provided we use it as visual source for V2 embed.
  Future<CharacterCard?> _persistImportedCharacterCard(
    CharacterCard card, {
    File? sourceFileForCopy,
    CharacterCard? forceReplaceTarget,
  }) async {
    final charDir = _storage.charactersDir;
    if (!await charDir.exists()) {
      await charDir.create(recursive: true);
    }

    final safeName = card.name
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');

    // Identity: stableId only. Name is never enough to overwrite or delete.
    // forceReplaceTarget is the explicit single-file "Replace existing" path.
    final stableMatch =
        findByStableId(card.frontPorchExtensions?.stableId);
    CharacterCard? target = stableMatch;
    if (target == null && forceReplaceTarget != null) {
      // Resolve against the live list by dbId so we don't hold a stale ref.
      final rid = forceReplaceTarget.dbId;
      if (rid != null) {
        for (final c in _characters) {
          if (c.dbId == rid) {
            target = c;
            break;
          }
        }
      }
      target ??= forceReplaceTarget;
    }

    // Ensure stableId before embed. On force-replace of a no-id incoming card,
    // carry the library character's stableId so future FP reimports still match.
    card.frontPorchExtensions ??= FrontPorchExtensions();
    final incomingStable = card.frontPorchExtensions!.stableId;
    if ((incomingStable == null || incomingStable.isEmpty) &&
        target != null) {
      final keep = target.frontPorchExtensions?.stableId;
      if (keep != null && keep.isNotEmpty) {
        card.frontPorchExtensions!.stableId = keep;
      }
    }
    card.frontPorchExtensions!.ensureStableId();

    String destPath;
    // Reuse the target's PNG path on update-in-place to avoid filename churn.
    // Fresh timestamped name for new library entries.
    if (target != null && target.imagePath != null) {
      destPath = target.imagePath!;
    } else if (sourceFileForCopy != null) {
      destPath =
          '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';
    } else if (card.imagePath != null) {
      destPath =
          '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';
    } else {
      destPath =
          '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';
    }

    final v2Service = V2CardService();
    final sourcePathForEmbed = sourceFileForCopy?.path ?? card.imagePath;
    await v2Service.saveCardAsPng(card, destPath, sourcePathForEmbed);

    final destFile = File(destPath);
    if (!destFile.existsSync() || destFile.lengthSync() == 0) {
      debugPrint('[Import] Written file missing or empty: $destPath');
    }

    card.imagePath = destPath;

    final dbImagePath = card.imagePath != null
        ? _toBasename(card.imagePath!)
        : null;

    if (target != null) {
      // Update-in-place: reuse dbId so sessions/chat history survive.
      if (target.imagePath != null) {
        final oldBase = _toBasename(target.imagePath!);
        final newBase = _toBasename(destPath);
        if (oldBase != newBase) {
          try {
            final oldFile = File(target.imagePath!);
            if (await oldFile.exists()) {
              await oldFile.delete();
              debugPrint(
                '[Import] Deleted previous PNG for matched identity '
                '${card.name} (old=$oldBase)',
              );
            }
          } catch (e) {
            debugPrint(
              '[Import] Could not delete previous PNG on reimport: $e',
            );
          }
        }
      }
      card.dbId = target.dbId;

      // updateCharacter does DB companion + list replace (re-embeds PNG; harmless).
      await updateCharacter(card);
    } else {
      final dbId = await _db.insertCharacterReturningId(
        CharactersCompanion(
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
            card.lorebook != null ? jsonEncode(card.lorebook!.toJson()) : null,
          ),
          worldNames: Value(jsonEncode(card.worldNames)),
        ),
      );
      card.dbId = dbId;

      _characters.add(card);
    }

    // Imported lore stays on the card only (no auto-linked World).
    return card;
  }

  /// Bulk import multiple character PNG files.
  /// [onProgress] is called after each file with (current, total, cardName, error).
  /// Returns a summary map: `{imported: int, failed: int, errors: List<String>}`.
  Future<Map<String, dynamic>> importCharacters(
    List<File> files, {
    void Function(int current, int total, String name, String? error)?
    onProgress,
    bool Function()? isCancelled,
  }) async {
    int imported = 0;
    int failed = 0;
    final List<String> errors = [];

    for (int i = 0; i < files.length; i++) {
      // Check cancellation
      if (isCancelled != null && isCancelled()) break;

      final file = files[i];
      final fileName = file.path.split(Platform.pathSeparator).last;
      try {
        final card = await importCharacter(file);
        if (card != null) {
          imported++;
          onProgress?.call(i + 1, files.length, card.name, null);
        } else {
          failed++;
          final err = 'No card data found in $fileName';
          errors.add(err);
          onProgress?.call(i + 1, files.length, fileName, err);
        }
      } catch (e) {
        failed++;
        final err = '$fileName: $e';
        errors.add(err);
        onProgress?.call(i + 1, files.length, fileName, e.toString());
      }
    }

    return {'imported': imported, 'failed': failed, 'errors': errors};
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
      notifyListeners();
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
        try {
          oldNameForMove = (await _db.getCharacterById(card.dbId!)).name;
        } catch (_) {
          oldNameForMove = null;
        }

        final dbImagePath = card.imagePath != null
            ? _toBasename(card.imagePath!)
            : null;
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

  /// One deferred broadcast for surfaces that persisted silently
  /// (updateCharacter notify: false) — fired when their dialog closes.
  void notifyCharactersChanged() {
    _clearCoverCache();
    _bumpCoverEpoch();
    notifyListeners();
  }

  Future<CharacterCard?> duplicateCharacter(
    CharacterCard card, {
    // Generalized for decoupled group private copies (per plan "reuse duplicateCharacter pattern").
    // When targetDirOverride provided + skipLibraryInsert, performs clone + file copy + V2 re-embed
    // into the caller's dir (e.g. groups/<gid>/avatars/) without touching library DB or _characters list.
    String? targetDirOverride,
    String? forcedBasename,
    bool skipLibraryInsert = false,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final newName = '${card.name} (duplicate)';

      // Clone the card model
      final clonedCard = CharacterCard(
        name: newName,
        description: card.description,
        personality: card.personality,
        scenario: card.scenario,
        firstMessage: card.firstMessage,
        mesExample: card.mesExample,
        systemPrompt: card.systemPrompt,
        postHistoryInstructions: card.postHistoryInstructions,
        alternateGreetings: List.from(card.alternateGreetings),
        tags: List.from(card.tags),
        ttsVoice: card.ttsVoice,
        lorebook: card.lorebook != null
            ? Lorebook(entries: List.from(card.lorebook!.entries))
            : null,
        worldNames: List.from(card.worldNames),
        // Deep copy realism extensions (not just reference copy)
        frontPorchExtensions: card.frontPorchExtensions != null
            ? card.frontPorchExtensions!.copyWith()
            : null,
        rawExtensions: card.rawExtensions != null
            ? Map<String, dynamic>.from(card.rawExtensions!)
            : null,
      );

      // Force a fresh stableId for the duplicate (new library identity + independent history).
      // CopyWith would have carried source's; explicit new UUID here per plan.
      if (clonedCard.frontPorchExtensions != null) {
        clonedCard.frontPorchExtensions!.stableId = const Uuid().v4();
      }

      // Handle image file duplication if exists (generalized target)
      if (card.imagePath != null) {
        final originalFile = File(card.imagePath!);
        if (await originalFile.exists()) {
          final charDir = targetDirOverride != null
              ? Directory(targetDirOverride)
              : _storage.charactersDir;
          if (!await charDir.exists()) {
            await charDir.create(recursive: true);
          }
          final baseForName = forcedBasename ?? newName;
          final safeName = baseForName
              .replaceAll(RegExp(r'[^\w\s\-]'), '')
              .replaceAll(' ', '_');
          final destPath = targetDirOverride != null
              ? '${charDir.path}/$safeName.png' // caller controls exact name (e.g. uuid)
              : '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';
          await originalFile.copy(destPath);
          clonedCard.imagePath = destPath;

          // Now write the V2 card data to the *new* PNG (always, for fidelity on extract)
          final v2Service = V2CardService();
          debugPrint(
            '[Duplicate] Saving PNG with extensions: ${clonedCard.frontPorchExtensions != null ? 'realism=${clonedCard.frontPorchExtensions!.realismEnabled}, bond=${clonedCard.frontPorchExtensions!.shortTermBond}' : 'none'}',
          );
          await v2Service.saveCardAsPng(clonedCard, destPath, destPath);
        }
      }

      // Guarantee a valid PNG always exists for the duplicate (protection for source
      // characters that have no avatar at all — common with older imports or stripped cards).
      // This ensures private group members are never dropped at load time and always
      // have something displayable (the V2CardService placeholder + full embedded metadata).
      if (clonedCard.imagePath == null) {
        final charDir = targetDirOverride != null
            ? Directory(targetDirOverride)
            : _storage.charactersDir;
        if (!await charDir.exists()) {
          await charDir.create(recursive: true);
        }
        final baseForName = forcedBasename ?? newName;
        final safeName = baseForName
            .replaceAll(RegExp(r'[^\w\s\-]'), '')
            .replaceAll(' ', '_');
        final destPath = targetDirOverride != null
            ? '${charDir.path}/$safeName.png'
            : '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';

        final v2Service = V2CardService();
        debugPrint(
          '[Duplicate] Source had no usable avatar — generating placeholder PNG for $newName at $destPath',
        );
        await v2Service.saveCardAsPng(clonedCard, destPath, null);
        clonedCard.imagePath = destPath;
      }

      if (!skipLibraryInsert) {
        // Insert into database (library path only)
        final dbImagePath = clonedCard.imagePath != null
            ? _toBasename(clonedCard.imagePath!)
            : null;
        final dbId = await _db.insertCharacterReturningId(
          CharactersCompanion(
            name: Value(clonedCard.name),
            description: Value(clonedCard.description),
            personality: Value(clonedCard.personality),
            scenario: Value(clonedCard.scenario),
            firstMessage: Value(clonedCard.firstMessage),
            mesExample: Value(clonedCard.mesExample),
            systemPrompt: Value(clonedCard.systemPrompt),
            postHistoryInstructions: Value(clonedCard.postHistoryInstructions),
            alternateGreetings: Value(
              jsonEncode(clonedCard.alternateGreetings),
            ),
            tags: Value(jsonEncode(clonedCard.tags)),
            imagePath: Value(dbImagePath),
            ttsVoice: Value(clonedCard.ttsVoice),
            lorebook: Value(
              clonedCard.lorebook != null
                  ? jsonEncode(clonedCard.lorebook!.toJson())
                  : null,
            ),
            worldNames: Value(jsonEncode(clonedCard.worldNames)),
          ),
        );
        clonedCard.dbId = dbId;

        _characters.add(clonedCard);
      }
      return clonedCard;
    } catch (e) {
      debugPrint('[Duplicate] Error duplicating character: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get all avatar images for a character from the database.
  Future<List<AvatarImage>> getAvatarImages(String characterId) async {
    try {
      final driftAvatars = await _db.getAvatarImagesByCharacterId(characterId);
      return driftAvatars
          .map(
            (a) => AvatarImage(
              id: a.id,
              characterId: a.characterId,
              filename: a.filename,
              label: a.label,
              displayOrder: a.displayOrder,
              createdAt: a.createdAt,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('[CharacterRepository] Failed to get avatar images: $e');
      return [];
    }
  }

  /// Add a new avatar image for a character.
  /// Add a labeled expression avatar (goes to `avatars/`). Returns the new
  /// avatar id so callers can roll back a partial batch on failure.
  Future<String> addAvatar(
    String characterId,
    String characterName,
    Uint8List imageBytes,
    String? label,
  ) async {
    try {
      debugPrint(
        '[CharacterRepository] addAvatar: started, characterId=$characterId, label=$label',
      );
      final safeName = characterName
          .replaceAll(RegExp(r'[^\w\s\-]'), '')
          .replaceAll(' ', '_');
      final avatarDir = Directory(
        p.join(_storage.charactersDir.path, safeName, 'avatars'),
      );
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }
      final filename = 'avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = p.join(avatarDir.path, filename);
      debugPrint('[CharacterRepository] addAvatar: writing file=$filePath');
      await File(filePath).writeAsBytes(imageBytes);
      debugPrint('[CharacterRepository] addAvatar: file written');

      final displayOrder = await _db.countAvatarsForCharacter(characterId);
      final avatarId = const Uuid().v4();
      debugPrint(
        '[CharacterRepository] addAvatar: inserting DB record, filename=$filename, displayOrder=$displayOrder',
      );
      await _db.insertAvatar(
        AvatarImagesCompanion(
          id: Value(avatarId),
          characterId: Value(characterId),
          filename: Value(filename),
          label: Value(label),
          displayOrder: Value(displayOrder),
        ),
      );
      debugPrint('[CharacterRepository] addAvatar: DB insert done');
      return avatarId;
    } catch (e) {
      debugPrint('[CharacterRepository] addAvatar: ERROR: $e');
      rethrow;
    }
  }

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
  ) async {
    // First real image on a missing/placeholder portrait becomes the portrait
    // alone. Writing a look *and* overwriting the portrait produced a dupe
    // (same face twice in the gallery) and left home stuck on the placeholder
    // until a ★ click forced a different cover path.
    final card = await getCharacterCardById(characterId);
    if (card != null) {
      final needsPortrait = !hasUsablePortrait(card, _storage) ||
          await isPlaceholderPortrait(card, _storage);
      if (needsPortrait) {
        final wrote = await bootstrapPortraitIfMissing(
          card: card,
          storage: _storage,
          bytes: imageBytes,
          updateCharacter: (c) => updateCharacter(c, notify: false),
        );
        if (wrote) return '';
      }
    }

    final safeName = characterName
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');
    final looksDir = Directory(
      p.join(_storage.charactersDir.path, safeName, 'looks'),
    );
    if (!await looksDir.exists()) {
      await looksDir.create(recursive: true);
    }
    final filename = 'look_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(p.join(looksDir.path, filename)).writeAsBytes(imageBytes);

    final displayOrder = await _db.countAvatarsForCharacter(characterId);
    final avatarId = const Uuid().v4();
    await _db.insertAvatar(
      AvatarImagesCompanion(
        id: Value(avatarId),
        characterId: Value(characterId),
        filename: Value(filename),
        label: Value(AvatarImage.lookLabel),
        displayOrder: Value(displayOrder),
      ),
    );
    return avatarId;
  }

  /// Character-name → on-disk media folder name (same rule used everywhere an
  /// avatar/look path is built). Centralized so the rename move can't drift
  /// from the write/read/delete sites.
  static String _mediaFolderName(String characterName) => characterName
      .replaceAll(RegExp(r'[^\w\s\-]'), '')
      .replaceAll(' ', '_');

  /// Move a character's avatar-gallery media folder when a rename changes its
  /// safe name. Renames the whole dir when the target is free; otherwise merges
  /// the avatars/ + looks/ files into the existing target.
  ///
  /// NON-DESTRUCTIVE by construction: a file whose destination already exists
  /// (safe-name collision — `Alice`, `Alice!`, `Bob Smith`, `Bob_Smith` all
  /// map to one folder) is LEFT at the source and logged, never overwritten
  /// and never deleted. The source tree is only ever pruned by removing files
  /// this method itself just moved (and then empty dirs) — it never runs a
  /// blanket recursive delete, so an un-merged file can't be destroyed.
  /// No-op when the safe name is unchanged or the source is absent.
  Future<void> _moveCharacterMediaFolder(String oldName, String newName) async {
    final oldSafe = _mediaFolderName(oldName);
    final newSafe = _mediaFolderName(newName);
    if (oldSafe.isEmpty || newSafe.isEmpty || oldSafe == newSafe) return;

    final base = _storage.charactersDir.path;
    final oldDir = Directory(p.join(base, oldSafe));
    if (!await oldDir.exists()) return;

    final newDir = Directory(p.join(base, newSafe));
    if (!await newDir.exists()) {
      // Target free — try an atomic directory rename first. It fails across
      // devices / some network FS; fall through to the per-file merge then.
      try {
        await oldDir.rename(newDir.path);
        debugPrint('[CharacterRepository] Moved media $oldSafe → $newSafe');
        return;
      } catch (_) {/* fall through to per-file move */}
    }

    var conflicts = 0;
    for (final sub in const ['avatars', 'looks']) {
      final from = Directory(p.join(oldDir.path, sub));
      if (!await from.exists()) continue;
      final to = Directory(p.join(newDir.path, sub));
      if (!await to.exists()) await to.create(recursive: true);
      await for (final entity in from.list()) {
        if (entity is! File) continue;
        final dest = p.join(to.path, p.basename(entity.path));
        if (await File(dest).exists()) {
          // Collision: leave the source file untouched (it is NOT lost, just
          // stranded under the old folder) rather than overwrite or delete.
          conflicts++;
          continue;
        }
        await entity.rename(dest);
      }
      // Only remove the source subfolder if we emptied it (no conflicts left).
      try {
        if (await from.exists() && await from.list().isEmpty) {
          await from.delete();
        }
      } catch (_) {}
    }
    // Remove the old top-level dir ONLY if nothing remains in it.
    try {
      if (await oldDir.exists() && await oldDir.list().isEmpty) {
        await oldDir.delete();
      }
    } catch (_) {}
    if (conflicts > 0) {
      debugPrint(
        '[CharacterRepository] Merged media $oldSafe → $newSafe with '
        '$conflicts conflict(s) left in place (safe-name collision).',
      );
    } else {
      debugPrint('[CharacterRepository] Merged media $oldSafe → $newSafe');
    }
  }

  /// Remove an avatar image for a character.
  Future<void> removeAvatar(String characterId, String avatarId) async {
    try {
      final avatar = await _db.getAvatarById(avatarId);
      if (avatar != null) {
        final char = _characters
            .where((c) => c.dbId == characterId)
            .firstOrNull;
        if (char != null && char.name.isNotEmpty) {
          final safeName = char.name
              .replaceAll(RegExp(r'[^\w\s\-]'), '')
              .replaceAll(' ', '_');
          // Looks live in `looks/`, expressions in `avatars/` — pick the right
          // folder off the row's own label (single-sourced via
          // AvatarImage.subfolder) so deleting a look doesn't orphan its PNG.
          final model = AvatarImage(
            id: avatar.id,
            characterId: avatar.characterId,
            filename: avatar.filename,
            label: avatar.label,
            displayOrder: avatar.displayOrder,
            createdAt: avatar.createdAt,
          );
          final file = File(
            p.join(_storage.charactersDir.path, safeName, model.subfolder, avatar.filename),
          );
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
      await _db.deleteAvatar(avatarId);
    } catch (e) {
      debugPrint('[CharacterRepository] Failed to remove avatar: $e');
      rethrow;
    }
  }

  /// Set the prime avatar index for a character.
  Future<void> setPrimeAvatar(String characterId, int primeIndex) async {
    try {
      await _db.updatePrimeAvatarIndex(characterId, primeIndex);
    } catch (e) {
      debugPrint('[CharacterRepository] Failed to set prime avatar: $e');
      rethrow;
    }
  }

  /// Update the label for an avatar image.
  Future<void> updateAvatarLabel(String avatarId, String label) async {
    try {
      await _db.updateAvatarLabel(avatarId, label);
    } catch (e) {
      debugPrint('[CharacterRepository] Failed to update avatar label: $e');
      rethrow;
    }
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

  /// Update a character's image path and persist to DB + PNG.
  Future<void> setCharacterImagePath(
    CharacterCard card,
    String imagePath,
  ) async {
    card.imagePath = imagePath;
    await updateCharacter(card);
  }

  /// Deletes the canonical portrait; a gallery look is promoted in its place.
  /// Returns the promoted look's id (callers clean their own cascades). Logic
  /// lives in the portrait_promotion leaf — this file is over the size cap.
  Future<String> deletePortraitPromotingLook(CharacterCard card) =>
      promoteLookOverPortrait(
        card: card,
        storage: _storage,
        updateCharacter: updateCharacter,
        removeAvatar: removeAvatar,
      );

  /// The file to bake as the character's exported / Stoop card cover: the ★
  /// starred avatar (a gallery look OR an expression image) when it's set and
  /// present on disk, else the library portrait (`imagePath`). Null when neither
  /// resolves. Lets a user pick their best render (an outfit, a mood) as the
  /// card's face without touching the in-app portrait.
  ///
  /// [card] must be a HYDRATED library card (`avatarImages` loaded) for the star
  /// to resolve — a bare card silently falls back to the portrait. Every PNG
  /// bake / upload path should route through this so the star works everywhere.
  /// Memo for [coverImageFileFor]: chat message bubbles resolve the cover
  /// on EVERY rebuild (dozens of bubbles × every streaming token batch),
  /// and the uncached path does a synchronous existsSync per call — near
  /// free on macOS/APFS, but 10-100x slower on Windows where Defender
  /// intercepts file stats. Field-reported as "the app got sluggish" in
  /// the 20260716 nightly. The key embeds the star id and portrait path,
  /// so changing either self-invalidates; mutations also clear the whole
  /// cache (updateCharacter / delete / notifyCharactersChanged) to cover
  /// files changing on disk under an unchanged key.
  final Map<String, File?> _coverCache = {};

  /// Bumped whenever cover bytes may have changed under a stable path (in-place
  /// portrait overwrite). Home grid [Image.file] keys include this so Done
  /// after gallery bootstrap refreshes the face without needing a ★ re-click.
  int coverEpoch = 0;

  void _clearCoverCache() => _coverCache.clear();

  void _bumpCoverEpoch() => coverEpoch++;

  File? coverImageFileFor(CharacterCard card) {
    final favId = card.frontPorchExtensions?.favoriteAvatarId;
    final key = '${card.name}|$favId|${card.imagePath}|$coverEpoch';
    if (_coverCache.containsKey(key)) return _coverCache[key];
    if (_coverCache.length > 512) _coverCache.clear();

    File? result;
    if (favId != null) {
      for (final a in card.avatarImages ?? const <AvatarImage>[]) {
        if (a.id == favId) {
          final f = a.resolveFile(_storage.characterBaseDir(card.name).path);
          if (f.existsSync()) result = f;
          break;
        }
      }
    }
    if (result == null) {
      final img = card.imagePath;
      if (img != null && img.isNotEmpty) {
        result = _storage.resolveCharacterImage(img);
      }
    }
    _coverCache[key] = result;
    return result;
  }

  /// Set the character's TTS voice (null = global default) and persist.
  Future<void> setTtsVoice(CharacterCard card, String? voiceId) async {
    card.ttsVoice = voiceId;
    await updateCharacter(card);
  }
}
