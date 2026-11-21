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
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_io.dart'
    show SpritePackResult, SpritePackTooLarge, decodeSpritePack;
import 'package:front_porch_ai/utils/emotion_labels.dart';
import 'package:front_porch_ai/utils/portrait_image_cache.dart';

/// Write-side adapter for character authoring beyond create/edit: delete and
/// avatar (expression image) management. Thin over [CharacterRepository] — the
/// exact desktop methods (`deleteCharacter`, `addAvatar`, `removeAvatar`,
/// `setPrimeAvatar`) so PNG/DB side-effects and parity are identical.
class CharacterAuthoringFacade {
  CharacterAuthoringFacade(this._repo, this._storage);

  final CharacterRepository _repo;
  final StorageService _storage;

  /// Delete a character (soft-delete row + remove PNG + chat history), reusing
  /// the desktop delete path. Returns false if not found.
  Future<bool> delete(String id) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return false;
    await _repo.deleteCharacter(card, chatsDir: _storage.chatsDir);
    return true;
  }

  /// List a character's avatars as JSON. `isLook` partitions gallery looks
  /// (`looks/`) from expression images (`avatars/`); `isFavorite` marks the ★
  /// (the export cover + default opening face, from `favoriteAvatarId`).
  Future<List<Map<String, dynamic>>> avatars(String id) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return const [];
    final images = await _repo.getAvatarImages(id);
    final favoriteId = card.frontPorchExtensions?.favoriteAvatarId;
    return images
        .map(
          (a) => {
            'id': a.id,
            // A look's label is the internal '__look__' sentinel — never show
            // it as a user-facing caption (isLook already marks looks).
            'label': a.isLook ? '' : (a.label ?? ''),
            'displayOrder': a.displayOrder,
            'isPrime': a.displayOrder + 1 == card.primeAvatarIndex,
            'isLook': a.isLook,
            'isFavorite': a.id == favoriteId,
          },
        )
        .toList();
  }

  /// Add an EXPRESSION avatar from uploaded bytes (goes to `avatars/`, labeled).
  /// Returns false if the character is gone.
  Future<bool> addAvatar(String id, List<int> bytes, String? label) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return false;
    // Reject the internal look sentinel as an expression label — an upload with
    // ?label=__look__ would write the file to avatars/ but mark the row a look
    // (AvatarImage.isLook), so it resolves/deletes from the wrong folder: a
    // broken tile + an orphaned PNG. Treat it as unlabeled.
    final clean =
        (label == null ||
            label.trim().isEmpty ||
            label.trim() == AvatarImage.lookLabel)
        ? null
        : label;
    await _repo.addAvatar(id, card.name, Uint8List.fromList(bytes), clean);
    return true;
  }

  /// Add a gallery LOOK from uploaded bytes (goes to `looks/`, look-labeled —
  /// never touches `imagePath`). Mirrors desktop `addLook`. False if gone.
  Future<bool> addLook(String id, List<int> bytes) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return false;
    await _repo.addLook(id, card.name, Uint8List.fromList(bytes));
    return true;
  }

  /// Set [bytes] as the card's portrait: written over the existing in-app
  /// portrait file IN PLACE (folders key members by its basename) or a fresh
  /// file when none exists, then re-embedded via `updateCharacter`. The web
  /// twin of `AvatarCreationController.applyPortrait`.
  Future<bool> attachPortrait(String id, List<int> bytes) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return false;
    final target = portraitWriteTarget(card: card, storage: _storage);
    await target.writeAsBytes(bytes);
    await evictPortraitImage(target);
    await _repo.updateCharacter(card);
    return true;
  }

  /// Re-tag one expression image. [label] must be empty (clear) or one of
  /// [EmotionLabels.all]; the avatar must belong to [id] and not be a look.
  /// False when the card or avatar is gone (a bad label is the route's 400).
  Future<bool> setAvatarLabel(String id, String avatarId, String label) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return false;
    final images = await _repo.getAvatarImages(id);
    if (!images.any((a) => a.id == avatarId && !a.isLook)) return false;
    final clean = label.trim();
    if (clean.isNotEmpty && !EmotionLabels.all.contains(clean)) return false;
    await _repo.updateAvatarLabel(avatarId, clean);
    return true;
  }

  /// Cap on the unpacked size of a ZIP sprite pack from the web. The body is
  /// already capped at 32 MiB compressed; a zip can expand far past that, and
  /// this route is internet-exposed (the desktop's picker is local-only).
  static const int maxExpressionZipUnpackedBytes = 64 * 1024 * 1024;

  /// Import an emotion-named ZIP sprite pack: each image whose base name is an
  /// emotion label becomes an expression avatar, and a non-empty import flips
  /// the expression engine on (the desktop's `importExpressionZip`). Returns
  /// how many landed and how many files were not recognised, null when the
  /// card is gone, and `tooLarge` when the unpacked pack passes the cap.
  Future<({int added, int unrecognized, bool tooLarge})?> importExpressionZip(
    String id,
    List<int> bytes,
  ) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return null;
    final SpritePackResult result;
    try {
      result = decodeSpritePack(
        Uint8List.fromList(bytes),
        maxUnpackedBytes: maxExpressionZipUnpackedBytes,
      );
    } on SpritePackTooLarge {
      return (added: 0, unrecognized: 0, tooLarge: true);
    }
    var added = 0;
    for (final e in result.entries) {
      await _repo.addAvatar(id, card.name, e.bytes, e.emotion);
      added++;
    }
    if (added > 0 && !_storage.expressionSettings.expressionEnabled) {
      await _storage.expressionSettings.setExpressionEnabled(true);
    }
    return (added: added, unrecognized: result.unrecognized, tooLarge: false);
  }

  /// Web mirror of the desktop portrait delete: promotes the ★ (else first)
  /// gallery look into the portrait via the shared portrait_promotion leaf.
  /// False when the card is missing or has no looks — the UI hides the
  /// button then, but a stale client may still call.
  Future<bool> deletePortrait(String id) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return false;
    card.avatarImages = await _repo.getAvatarImages(id);
    if (!card.avatarImages!.any((a) => a.isLook)) return false;
    await _repo.deletePortraitPromotingLook(card);
    return true;
  }

  Future<bool> removeAvatar(String id, String avatarId) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return false;
    // Cascade to match desktop (avatar_gallery_controller.remove): capture
    // whether this avatar was the ★ favorite (export cover / default face)
    // and/or the prime BEFORE deleting, then heal both pointers after — the
    // web path previously left a dangling favorite id and a prime index still
    // pointing at the deleted expression.
    final wasFavorite = card.frontPorchExtensions?.favoriteAvatarId == avatarId;
    final before = await _repo.getAvatarImages(id);
    final removed = before.where((a) => a.id == avatarId).firstOrNull;
    final removedPrimeIdx = removed != null ? removed.displayOrder + 1 : -1;

    await _repo.removeAvatar(id, avatarId);

    if (wasFavorite) await setFavorite(id, null); // → portrait
    if (card.primeAvatarIndex == removedPrimeIdx) {
      final remaining =
          (await _repo.getAvatarImages(id)).where((a) => !a.isLook).toList()
            ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      final newPrime = remaining.isNotEmpty
          ? remaining.first.displayOrder + 1
          : 1;
      await _repo.setPrimeAvatar(id, newPrime);
      card.primeAvatarIndex = newPrime;
    }
    return true;
  }

  /// Mark the avatar [avatarId] as the prime (default) one. The DB stores a
  /// 1-based index (`displayOrder + 1`), matching the desktop avatars dialog.
  Future<bool> setPrime(String id, String avatarId) async {
    final images = await _repo.getAvatarImages(id);
    AvatarImage? target;
    for (final a in images) {
      if (a.id == avatarId) {
        target = a;
        break;
      }
    }
    if (target == null) return false;
    final primeIndex = target.displayOrder + 1;
    await _repo.setPrimeAvatar(id, primeIndex);
    // Keep the in-memory card in sync (the desktop avatars dialog does the same)
    // so a subsequent read reflects the new prime without a reload.
    final card = await _repo.getCharacterCardById(id);
    if (card != null) card.primeAvatarIndex = primeIndex;
    return true;
  }

  /// Resolve an avatar image file for serving, or null if absent.
  Future<File?> avatarFile(String id, String avatarId) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return null;
    final images = await _repo.getAvatarImages(id);
    AvatarImage? target;
    for (final a in images) {
      if (a.id == avatarId) {
        target = a;
        break;
      }
    }
    if (target == null) return null;
    final safeName = card.name
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');
    // Look-aware: resolveFile joins <base>/<subfolder>/<filename>, so a look
    // serves from looks/ and an expression from avatars/ (the old avatars-only
    // path couldn't serve a look at all).
    final characterBaseDir = p.join(_storage.charactersDir.path, safeName);
    final file = target.resolveFile(characterBaseDir);
    return file.existsSync() ? file : null;
  }

  /// Set (or clear) the ★ favorite avatar — the export cover + default opening
  /// face. Pass the avatar id, or null/'' to clear back to the portrait. Pointer
  /// only when a portrait already exists; if the card has no usable portrait,
  /// the starred image is bootstrapped into `imagePath` so the extensions write
  /// can land (desktop parity for issue #171).
  Future<bool> setFavorite(String id, String? avatarId) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return false;
    final clean = (avatarId == null || avatarId.trim().isEmpty)
        ? null
        : avatarId;
    final ext = card.frontPorchExtensions ?? FrontPorchExtensions();
    ext.favoriteAvatarId = clean;
    card.frontPorchExtensions = ext;
    card.avatarImages = await _repo.getAvatarImages(id);
    if (clean != null && !hasUsablePortrait(card, _storage)) {
      AvatarImage? target;
      for (final a in card.avatarImages ?? const <AvatarImage>[]) {
        if (a.id == clean) {
          target = a;
          break;
        }
      }
      if (target != null) {
        final file = target.resolveFile(
          _storage.characterBaseDir(card.name).path,
        );
        if (file.existsSync()) {
          await bootstrapPortraitIfMissing(
            card: card,
            storage: _storage,
            bytes: await file.readAsBytes(),
            updateCharacter: _repo.updateCharacter,
          );
          return true;
        }
      }
    }
    await _repo.updateCharacter(card);
    return true;
  }
}
