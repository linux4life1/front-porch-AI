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

/// Character-name → on-disk media folder name (same rule used everywhere an
/// avatar/look path is built). Centralized so the rename move can't drift
/// from the write/read/delete sites.
String _mediaFolderName(String characterName) =>
    characterName.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_');

/// Avatar-gallery media: the expression/look CRUD, the media-folder rename
/// move, and the portrait-promotion delete. Extracted verbatim from
/// `character_repository.dart` (zero behaviour change) to shrink the god
/// file — see the split map for that file. As `part of` the same library,
/// these reach the private DB/storage/list state — and `getCharacterCardById`
/// / `updateCharacter` in the sibling parts — exactly as the in-class
/// methods did.
extension CharacterRepositoryMedia on CharacterRepository {
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
      final needsPortrait =
          !hasUsablePortrait(card, _storage) ||
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

  /// Delete gallery looks (`isLook`) for [characterId]. Expression avatars stay.
  Future<void> clearGalleryLooks(String characterId) async {
    for (final img in await getAvatarImages(characterId)) {
      if (img.isLook) await removeAvatar(characterId, img.id);
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
            p.join(
              _storage.charactersDir.path,
              safeName,
              model.subfolder,
              avatar.filename,
            ),
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

  /// Deletes the canonical portrait; a gallery look is promoted in its place.
  /// Returns the promoted look's id (callers clean their own cascades). Logic
  /// lives in the portrait_promotion leaf — this file is over the size cap.
  Future<String> deletePortraitPromotingLook(CharacterCard card) =>
      promoteLookOverPortrait(
        card: card,
        storage: _storage,
        updateCharacter: updateCharacter,
        removeAvatar: removeAvatar,
        addLook: addLook,
      );
}
