// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Card persistence for the character library: insert, full update (PNG +
// row + stable-id re-key + media move), delete of everything a card owns on
// disk, and the per-character memorySources column. The in-memory list and
// change notification stay on the repository.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_store/character_media_store.dart';
import 'package:front_porch_ai/services/character_store/character_row_codec.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/utils.dart' show stableGroupIdFrom;

class CharacterCardWriter {
  CharacterCardWriter({
    required AppDatabase Function() db,
    required CharacterMediaStore media,
    required String Function(String stored) resolveImagePath,
  }) : _db = db,
       _media = media,
       _resolveImagePath = resolveImagePath;

  final AppDatabase Function() _db;
  final CharacterMediaStore _media;
  final String Function(String stored) _resolveImagePath;

  Future<CharacterCard?> activeCardById(
    String id,
    List<CharacterCard> knownCards,
  ) async {
    final query = _db().select(_db().characters)
      ..where((row) => row.id.equals(id) & row.deletedAt.isNull());
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final card = characterFromRow(row);
    final knownPath = knownCards
        .where((c) => c.dbId == id)
        .firstOrNull
        ?.imagePath;
    if (knownPath != null && toBasename(knownPath) == card.imagePath) {
      card.imagePath = knownPath;
    } else if (card.imagePath != null) {
      card.imagePath = absoluteImagePath(card.imagePath!);
    }
    return card;
  }

  /// Absolute path for [imagePath]; bare basenames resolve into Characters/.
  String absoluteImagePath(String imagePath) =>
      p.isAbsolute(imagePath) ? imagePath : _resolveImagePath(imagePath);

  /// Insert [character]'s row (basename only, for portability); returns its id.
  Future<String> insert(CharacterCard character) {
    final dbImagePath = character.imagePath != null
        ? toBasename(character.imagePath!)
        : null;
    return _db().insertCharacterReturningId(
      characterCompanion(character, dbImagePath: dbImagePath),
    );
  }

  /// Write [card] to its PNG and its row. [card.imagePath] must be set.
  Future<void> persistUpdate(CharacterCard card) async {
    final v2Service = V2CardService();

    // Resolve imagePath to a real filesystem path before any I/O.
    // In-memory CharacterCards are supposed to carry full absolute paths
    // (see loadCharacters). Defensive handling here prevents crashes if any
    // caller ever passes a bare basename (as the full-page editor used to).
    // We also normalize the card so that after updateCharacter the object
    // always holds a full path.
    final fsPath = absoluteImagePath(card.imagePath!);
    card.imagePath = fsPath;

    // Ensure stableId before embedding (carries for existing, generates for legacy on touch).
    card.frontPorchExtensions?.ensureStableId();

    // Overwrite the existing file with updated data (now using a guaranteed
    // absolute path that lands in the correct Characters/ directory).
    await v2Service.saveCardAsPng(card, fsPath, fsPath);

    if (card.dbId == null) return;
    final db = _db();

    // A rename must carry the avatar-gallery media with it: expression and
    // look PNGs live under Characters/<safeName>/{avatars,looks}/, keyed on
    // the CURRENT name at both write and read time. Capture the OLD name
    // before the DB write so we can move the folder AFTER it — DB-first so
    // a failed move leaves the (pre-existing) blank-gallery bug (logged),
    // never the worse split-brain of "DB says new name, files under old".
    String? oldNameForMove;
    String? oldImagePath;
    try {
      final existing = await db.getCharacterById(card.dbId!);
      oldNameForMove = existing.name;
      oldImagePath = existing.imagePath;
    } catch (_) {
      oldNameForMove = null;
    }

    final dbImagePath = card.imagePath != null
        ? toBasename(card.imagePath!)
        : null;
    final fromId = stableGroupIdFrom(oldImagePath, oldNameForMove ?? card.name);
    final toId = stableGroupIdFrom(dbImagePath, card.name);
    await db.transaction(() async {
      await db.updateCharacter(
        characterCompanion(
          card,
          dbImagePath: dbImagePath,
        ).copyWith(id: Value(card.dbId!), updatedAt: Value(DateTime.now())),
      );
      // Portrait basename IS the portable id for quests / RAG / Data Bank
      // / Journal / Growth. Changing it without a re-key is the cleanup
      // wipe the gallery used to trigger on "Replace portrait".
      if (fromId != toId && fromId.isNotEmpty && toId.isNotEmpty) {
        await db.rekeyStableCharacterId(fromId, toId);
      }
    });

    // Move the gallery media to match the new name, AFTER the DB commit.
    // Best-effort: a failure here must not block the rename (the card text
    // is what the user asked to save) — it only logs, leaving the media
    // stranded (recoverable) rather than risking loss.
    if (oldNameForMove != null) {
      try {
        await _media.moveMediaFolder(oldNameForMove, card.name);
      } catch (e) {
        debugPrint('[CharacterRepository] Avatar folder move skipped: $e');
      }
    }
  }

  /// Soft-delete [character]'s row and remove its PNG, chat history folder,
  /// gallery media and linked worlds. Call after it left the in-memory list.
  Future<void> deleteStored(
    CharacterCard character, {
    WorldRepository? worldRepo,
    Directory? chatsDir,
  }) async {
    // Soft-delete the character row so the deletion flag propagates through
    // cloud DB sync + merge and prevents resurrection.
    if (character.dbId != null) {
      await _db().softDeleteCharacterById(character.dbId!);
    }

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

    // The avatar-gallery media folder (Characters/<safeName>/ holding
    // avatars/ + looks/) — leaving it behind leaks gallery images on disk
    // (a full pack is ~28 files) for every deleted character.
    await _media.deleteMediaFolder(character);

    if (worldRepo != null) {
      final linkedWorld = worldRepo.worlds
          .where((w) => w.linkedCharacterName == character.name)
          .toList();
      for (final world in linkedWorld) {
        await worldRepo.deleteWorld(world);
      }
    }
  }

  /// Read the JSON-encoded memorySources list for a character.
  Future<List<String>> memorySources(String characterDbId) async {
    try {
      final dbChar = await _db().getCharacterById(characterDbId);
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

  /// Write memorySources (JSON-encoded list of character IDs).
  Future<void> setMemorySources(
    String characterDbId,
    List<String> sources,
  ) async {
    try {
      await _db().updateCharacter(
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
