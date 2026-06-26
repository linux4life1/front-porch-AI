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
import 'package:front_porch_ai/models/world.dart' as world_model;
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/cloud_sync_service.dart';
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
    CloudSyncService? cloudSyncService,
  }) async {
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

      // Delete from cloud storage (best-effort immediate cleanup while online).
      // The authoritative cleanup happens later in CloudSyncService._reconcileDeletedAssets
      // during the next fullSync, using the DB as source of truth.
      if (cloudSyncService != null) {
        final charId = p.basenameWithoutExtension(character.imagePath!);
        final pngName = p.basename(character.imagePath!);
        await cloudSyncService.deleteRemoteCharacter(charId, pngName);
      }
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

  Future<CharacterCard?> importCharacter(
    File file, {
    WorldRepository? worldRepo,
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
        worldRepo: worldRepo,
      );
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Internal helper that persists an already-parsed CharacterCard (from file or from
  /// embedded group card data). Handles collision detection (now by stableId when present,
  /// falling back to name), update-in-place reuse of dbId+PNG for matching identity (so
  /// sessions/chat history survive realism/needs edits), or fresh insert.
  /// Only true non-matched name dups still get soft-deleted.
  ///
  /// Ensures stableId is present before embedding via saveCardAsPng.
  ///
  /// When [sourceFileForCopy] is provided we use it as visual source for V2 embed.
  /// Otherwise we expect [card.imagePath] ...
  Future<CharacterCard?> _persistImportedCharacterCard(
    CharacterCard card, {
    File? sourceFileForCopy,
    WorldRepository? worldRepo,
  }) async {
    final charDir = _storage.charactersDir;
    if (!await charDir.exists()) {
      await charDir.create(recursive: true);
    }

    final safeName = card.name
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');

    // Collision handling: prefer stableId match (from PNG realism_engine) for identity
    // preservation across edits/reimports; fallback to name for legacy cards.
    // Refactored from always-nuke to update-in-place reuse of dbId for target match.
    // Only non-target name dups (extra collisions) are soft-deleted + removed.
    final incomingStable = card.frontPorchExtensions?.stableId;
    CharacterCard? stableMatch;
    final cardName = card.name;
    final nameMatches = _characters.where((c) => c.name == cardName).toList();
    if (incomingStable != null && incomingStable.isNotEmpty) {
      for (final c in _characters) {
        if (c.frontPorchExtensions?.stableId == incomingStable) {
          stableMatch = c;
          break;
        }
      }
    }
    final target =
        stableMatch ?? (nameMatches.isNotEmpty ? nameMatches.first : null);

    // Soft-delete + remove ONLY non-target name collisions (true dups or old name-only)
    // Note: stableMatch may have different .name than incoming (name drift); we still reuse
    // its dbId via target and replace in list by dbId later. nameMatches snapshot + remove by ref is safe here.
    for (final oldChar in nameMatches) {
      if (target != null && oldChar.dbId == target.dbId) {
        continue; // preserve the matched target; we will update it in place
      }
      if (oldChar.dbId != null) {
        try {
          await _db.softDeleteCharacterById(oldChar.dbId!);
          debugPrint(
            '[Import] Soft-deleted old character row for name collision: ${oldChar.name} (id=${oldChar.dbId})',
          );
        } catch (e) {
          debugPrint('[Import] Could not soft-delete old character row: $e');
        }
      }
      if (oldChar.imagePath != null) {
        try {
          final oldFile = File(oldChar.imagePath!);
          if (await oldFile.exists()) {
            await oldFile.delete();
            debugPrint(
              '[Import] Deleted old PNG for ${card.name}: ${p.basename(oldChar.imagePath!)}',
            );
          }
        } catch (e) {
          debugPrint('[Import] Could not delete old PNG: $e');
        }
      }
      _characters.remove(oldChar);
    }

    // Ensure stableId is generated/carried before any save/embed (for new or update paths).
    // (Harmless if later write fails; in-memory card gets identity, which is fine and matches plan.)
    card.frontPorchExtensions ??= FrontPorchExtensions();
    card.frontPorchExtensions!.ensureStableId();

    String destPath;
    // For stable target match, prefer reusing the existing target's imagePath (overwrite in place)
    // to avoid unnecessary filename churn on reimport of edited cards (e.g. realism settings).
    // Fallback to fresh timestamped name for new entries or non-matches (historical).
    if (target != null && target.imagePath != null) {
      destPath = target.imagePath!;
    } else if (sourceFileForCopy != null) {
      destPath =
          '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';
      // Do NOT raw copy here; use v2 saveCardAsPng below to embed stable + FP data
      // (pixels preserved by resolve logic inside saveCardAsPng using source).
    } else if (card.imagePath != null) {
      // Already have a file (e.g. from group card member extraction)
      destPath =
          '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';
    } else {
      // No image at all — create a tiny placeholder (will be overwritten by savePng)
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
      // Update-in-place for stable or name match: reuse dbId (prevents data loss)
      // Delete old PNG only if its basename differs from the (new) dest we wrote.
      if (target.imagePath != null) {
        final oldBase = _toBasename(target.imagePath!);
        final newBase = _toBasename(destPath);
        if (oldBase != newBase) {
          try {
            final oldFile = File(target.imagePath!);
            if (await oldFile.exists()) {
              await oldFile.delete();
              debugPrint(
                '[Import] Deleted previous PNG for matched identity ' +
                    card.name +
                    ' (old=' +
                    oldBase +
                    ')',
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

      // Reuse updateCharacter for the DB update (exact companion + updatedAt) + list replace.
      // (png already embedded above via saveCardAsPng for stable; update will re-embed same, harmless).
      // This eliminates the inlined companion duplication. Minor: double notify/_isLoading possible in import context but semantics/observables unchanged.
      await updateCharacter(card);
    } else {
      // No match: fresh insert path (original behavior)
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

    if (card.lorebook != null &&
        card.lorebook!.entries.isNotEmpty &&
        worldRepo != null) {
      final world = world_model.World(
        avatarPath: card.imagePath,
        name: "${card.name}'s world lore",
        description: 'Auto-imported from character card: ${card.name}',
        lorebook: Lorebook(entries: List.from(card.lorebook!.entries)),
        linkedCharacterName: card.name,
      );
      await worldRepo.saveWorld(world);
    }

    // Note: list management (add or replace) happens inside the target/!target branches above
    // so that we reuse dbId for matches without duplication.
    return card;
  }

  /// Bulk import multiple character PNG files.
  /// [onProgress] is called after each file with (current, total, cardName, error).
  /// Returns a summary map: `{imported: int, failed: int, errors: List<String>}`.
  Future<Map<String, dynamic>> importCharacters(
    List<File> files, {
    WorldRepository? worldRepo,
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
        final card = await importCharacter(file, worldRepo: worldRepo);
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

  Future<void> updateCharacter(
    CharacterCard card, {
    WorldRepository? worldRepo,
  }) async {
    if (card.imagePath == null) return;

    _isLoading = true;
    notifyListeners();

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
      }

      // Sync lorebook to linked world if it exists
      if (worldRepo != null &&
          card.lorebook != null &&
          card.lorebook!.entries.isNotEmpty) {
        final linkedWorld = worldRepo.worlds
            .where((w) => w.linkedCharacterName == card.name)
            .firstOrNull;
        if (linkedWorld != null) {
          linkedWorld.lorebook = Lorebook(
            entries: List.from(card.lorebook!.entries),
          );
          await worldRepo.saveWorld(linkedWorld);
        }
      }

      // Update the list entry
      final index = _characters.indexWhere(
        (c) => c.imagePath == card.imagePath,
      );
      if (index != -1) {
        _characters[index] = card;
      }
      notifyListeners();
    } catch (e) {
      print('Error updating character: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
  Future<void> addAvatar(
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
    } catch (e) {
      debugPrint('[CharacterRepository] addAvatar: ERROR: $e');
      rethrow;
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
          final avatarDir = Directory(
            p.join(_storage.charactersDir.path, safeName, 'avatars'),
          );
          final file = File(p.join(avatarDir.path, avatar.filename));
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

  /// Set the character's TTS voice (null = global default) and persist.
  Future<void> setTtsVoice(CharacterCard card, String? voiceId) async {
    card.ttsVoice = voiceId;
    await updateCharacter(card);
  }
}
