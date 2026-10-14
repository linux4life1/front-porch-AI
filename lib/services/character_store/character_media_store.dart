// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Avatar-gallery media for the character library: expression and look rows,
// their files under Characters/<safeName>/{avatars,looks}/, and the
// media-folder move a rename needs.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_store/character_row_codec.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart';
import 'package:front_porch_ai/services/storage_service.dart';

class CharacterMediaStore {
  CharacterMediaStore({
    required AppDatabase Function() db,
    required StorageService storage,
    required List<CharacterCard> Function() characters,
    required Future<CharacterCard?> Function(String id) cardById,
    required Future<void> Function(CharacterCard card) saveCardSilently,
  }) : _db = db,
       _storage = storage,
       _characters = characters,
       _cardById = cardById,
       _saveCardSilently = saveCardSilently;

  final AppDatabase Function() _db;
  final StorageService _storage;
  final List<CharacterCard> Function() _characters;
  final Future<CharacterCard?> Function(String id) _cardById;

  /// Persists a card without a change broadcast (portrait bootstrap).
  final Future<void> Function(CharacterCard card) _saveCardSilently;

  Directory _mediaDir(String characterName, String sub) => Directory(
    p.join(_storage.charactersDir.path, mediaFolderName(characterName), sub),
  );

  /// All avatar images for a character from the database.
  Future<List<AvatarImage>> avatarImages(String characterId) async {
    try {
      final driftAvatars = await _db().getAvatarImagesByCharacterId(
        characterId,
      );
      return driftAvatars.map(avatarFromRow).toList();
    } catch (e) {
      debugPrint('[CharacterRepository] Failed to get avatar images: $e');
      return [];
    }
  }

  /// Add a labeled expression avatar (goes to `avatars/`). Returns the new
  /// avatar id.
  Future<String> addAvatar(
    String characterId,
    String characterName,
    Uint8List imageBytes,
    String? label, {
    String? mediaId,
  }) async {
    try {
      if (mediaId != null && await _db().getAvatarById(mediaId) != null) {
        return mediaId;
      }
      debugPrint(
        '[CharacterRepository] addAvatar: started, characterId=$characterId, label=$label',
      );
      final avatarDir = _mediaDir(characterName, 'avatars');
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }
      final filename = 'avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = p.join(avatarDir.path, filename);
      debugPrint('[CharacterRepository] addAvatar: writing file=$filePath');
      await File(filePath).writeAsBytes(imageBytes);
      debugPrint('[CharacterRepository] addAvatar: file written');

      final displayOrder = await _db().countAvatarsForCharacter(characterId);
      final avatarId = mediaId ?? const Uuid().v4();
      debugPrint(
        '[CharacterRepository] addAvatar: inserting DB record, filename=$filename, displayOrder=$displayOrder',
      );
      await _db().insertAvatar(
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
  /// had no face or only a solid-color placeholder.
  Future<String> addLook(
    String characterId,
    String characterName,
    Uint8List imageBytes, {
    bool bootstrapMissingPortrait = true,
    String? mediaId,
  }) async {
    // First real image on a missing/placeholder portrait becomes the portrait
    // alone. Writing a look *and* overwriting the portrait produced a dupe
    // (same face twice in the gallery) and left home stuck on the placeholder
    // until a ★ click forced a different cover path.
    final card = await _cardById(characterId);
    if (card != null && bootstrapMissingPortrait) {
      final needsPortrait =
          !hasUsablePortrait(card, _storage) ||
          await isPlaceholderPortrait(card, _storage);
      if (needsPortrait) {
        final wrote = await bootstrapPortraitIfMissing(
          card: card,
          storage: _storage,
          bytes: imageBytes,
          updateCharacter: _saveCardSilently,
        );
        if (wrote) return '';
      }
    }
    return _writeLook(characterId, characterName, imageBytes, mediaId: mediaId);
  }

  Future<String> _writeLook(
    String characterId,
    String characterName,
    Uint8List imageBytes, {
    String? mediaId,
  }) async {
    if (mediaId != null && await _db().getAvatarById(mediaId) != null) {
      return mediaId;
    }
    final looksDir = _mediaDir(characterName, 'looks');
    if (!await looksDir.exists()) {
      await looksDir.create(recursive: true);
    }
    final filename =
        'look_${mediaId ?? DateTime.now().millisecondsSinceEpoch}.png';
    await File(p.join(looksDir.path, filename)).writeAsBytes(imageBytes);

    final displayOrder = await _db().countAvatarsForCharacter(characterId);
    final avatarId = mediaId ?? const Uuid().v4();
    await _db().insertAvatar(
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

  /// Remove an avatar row and its file.
  Future<void> removeAvatar(String characterId, String avatarId) async {
    try {
      final avatar = await _db().getAvatarById(avatarId);
      if (avatar != null) {
        final char = _characters()
            .where((c) => c.dbId == characterId)
            .firstOrNull;
        if (char != null && char.name.isNotEmpty) {
          // Looks live in `looks/`, expressions in `avatars/` — pick the right
          // folder off the row's own label (single-sourced via
          // AvatarImage.subfolder) so deleting a look doesn't orphan its PNG.
          final model = avatarFromRow(avatar);
          final file = File(
            p.join(_mediaDir(char.name, model.subfolder).path, avatar.filename),
          );
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
      await _db().deleteAvatar(avatarId);
    } catch (e) {
      debugPrint('[CharacterRepository] Failed to remove avatar: $e');
      rethrow;
    }
  }

  Future<void> setPrimeAvatar(String characterId, int primeIndex) async {
    try {
      await _db().updatePrimeAvatarIndex(characterId, primeIndex);
    } catch (e) {
      debugPrint('[CharacterRepository] Failed to set prime avatar: $e');
      rethrow;
    }
  }

  Future<void> updateAvatarLabel(String avatarId, String label) async {
    try {
      await _db().updateAvatarLabel(avatarId, label);
    } catch (e) {
      debugPrint('[CharacterRepository] Failed to update avatar label: $e');
      rethrow;
    }
  }

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
  Future<void> moveMediaFolder(String oldName, String newName) async {
    final oldSafe = mediaFolderName(oldName);
    final newSafe = mediaFolderName(newName);
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
      } catch (_) {
        /* fall through to per-file move */
      }
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

  /// Delete the whole media folder of [character] unless another library
  /// character maps to the same safe name. Best-effort; logs on failure.
  Future<void> deleteMediaFolder(CharacterCard character) async {
    try {
      final safeName = mediaFolderName(character.name);
      // Only delete when NO other character shares this folder — sanitized
      // names collide ("A!" and "A" → same folder), and nuking a shared folder
      // would take another character's gallery with it. When ambiguous, leave
      // it (a small disk leak) rather than risk cross-character data loss.
      final shared = _characters().any(
        (c) => c.dbId != character.dbId && mediaFolderName(c.name) == safeName,
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
  }
}
