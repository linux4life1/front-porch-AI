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

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Deletes a character's canonical portrait by PROMOTING a gallery look in
/// its place: the ★ starred look when the star points at one, else the first
/// look. Extracted leaf (CharacterRepository delegates here — the repository
/// is far over the file-size cap).
///
/// The promoted bytes OVERWRITE the old portrait file in place when it lives
/// in app storage: folders and the home-grid folder filter key members by the
/// portrait's basename, so a renamed file would silently orphan the character
/// from its folder. The image cache is evicted so the same path shows the new
/// pixels. Only an external/missing old portrait (e.g. an import still
/// pointing at the user's original file — not ours to touch) gets a fresh
/// in-app file and a changed imagePath.
///
/// A star that pointed at the promoted look clears to null (the new portrait
/// IS that image; null star = portrait-is-default). Returns the promoted
/// look's id so callers can clean their own cascades (per-chat selection).
/// Throws [StateError] when the card has no looks — callers hide the delete
/// affordance in that case.
Future<String> promoteLookOverPortrait({
  required CharacterCard card,
  required StorageService storage,
  required Future<void> Function(CharacterCard card) updateCharacter,
  required Future<void> Function(String characterId, String avatarId)
  removeAvatar,
}) async {
  final looks = [
    for (final a in card.avatarImages ?? const <AvatarImage>[])
      if (a.isLook) a,
  ];
  if (looks.isEmpty) {
    throw StateError('Cannot delete the portrait with no gallery avatars');
  }
  final favId = card.frontPorchExtensions?.favoriteAvatarId;
  final promoted = looks.firstWhere(
    (l) => l.id == favId,
    orElse: () => looks.first,
  );
  final bytes = await promoted
      .resolveFile(storage.characterBaseDir(card.name).path)
      .readAsBytes();

  final target = portraitWriteTarget(card: card, storage: storage);
  await target.writeAsBytes(bytes);
  // Same path, new bytes — evict so Image.file doesn't serve stale pixels.
  await FileImage(target).evict();

  if (favId == promoted.id) {
    (card.frontPorchExtensions ??= FrontPorchExtensions()).favoriteAvatarId =
        null;
  }
  await updateCharacter(card);
  await removeAvatar(card.dbId!, promoted.id);
  return promoted.id;
}

/// The file a character's portrait PIXELS should be written to — the shared
/// rule behind look-promotion and the creator's portrait apply.
///
/// When the card already has an in-app portrait file, that file is the target
/// (overwrite IN PLACE: folders and the home-grid folder filter key members
/// by the portrait's basename, so a renamed file silently orphans the
/// character from its folder). When it doesn't — an external import whose
/// original file isn't ours to touch, or a creator card saved without an
/// avatar yet — a fresh `Characters/<safeName>_<epoch>.png` is created and
/// its path stamped onto the card. Callers write the bytes, evict the image
/// cache, and persist via updateCharacter (which re-embeds the V2 card data).
File portraitWriteTarget({
  required CharacterCard card,
  required StorageService storage,
}) {
  final oldPath = card.imagePath;
  if (oldPath != null && oldPath.isNotEmpty) {
    final old = storage.resolveCharacterImage(oldPath);
    if (p.isWithin(storage.charactersDir.path, old.path) && old.existsSync()) {
      return old;
    }
  }
  final safe = card.name
      .replaceAll(RegExp(r'[^\w\s\-]'), '')
      .replaceAll(' ', '_');
  storage.charactersDir.createSync(recursive: true);
  final target = File(
    p.join(
      storage.charactersDir.path,
      '${safe}_${DateTime.now().millisecondsSinceEpoch}.png',
    ),
  );
  card.imagePath = target.path;
  return target;
}

/// Whether [card] has an on-disk portrait file that can be opened.
///
/// Null/empty [CharacterCard.imagePath] or a missing resolved file both count
/// as "no usable portrait" — the case the Avatar Gallery can bootstrap from a
/// newly-added look (issue #171: Add avatar + ★ left Edit Character on
/// "No avatar" because nothing ever wrote `imagePath`).
bool hasUsablePortrait(CharacterCard card, StorageService storage) {
  final path = card.imagePath;
  if (path == null || path.isEmpty) return false;
  return storage.resolveCharacterImage(path).existsSync();
}

/// True when the on-disk portrait is a synthetic solid-color card PNG from
/// [V2CardService] / group import (creator "None for now", JSON import, etc.).
/// Those are always **400×600** with a single fill color. Real photos are kept
/// even if they happen to be flat-colored (different size or any pixel variance).
///
/// Returns false when there is no file, the file won't decode, size differs,
/// or any sample differs.
Future<bool> isPlaceholderPortrait(
  CharacterCard card,
  StorageService storage,
) async {
  if (!hasUsablePortrait(card, storage)) return false;
  try {
    final file = storage.resolveCharacterImage(card.imagePath!);
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) return false;
    // V2 / group-import synthesizer always emits this exact size.
    if (decoded.width != 400 || decoded.height != 600) return false;
    // 5×5 grid of samples — all identical RGB ⇒ solid placeholder.
    int? r0, g0, b0;
    for (final yf in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
      for (final xf in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final x = (xf * (decoded.width - 1)).round();
        final y = (yf * (decoded.height - 1)).round();
        final px = decoded.getPixel(x, y);
        final r = px.r.toInt();
        final g = px.g.toInt();
        final b = px.b.toInt();
        if (r0 == null) {
          r0 = r;
          g0 = g;
          b0 = b;
        } else if (r != r0 || g != g0 || b != b0) {
          return false;
        }
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Write [bytes] as the card portrait when there is no usable portrait **or**
/// the current one is a solid-color placeholder. Overwrites the portrait file
/// in place when possible. Returns true when the portrait was written.
///
/// Used by [CharacterRepository.addLook] (portrait-only path — no gallery look
/// row, so the first real upload does not dupe as portrait + look) and by
/// ★-persist so a character created without art still gets a real card face.
Future<bool> bootstrapPortraitIfMissing({
  required CharacterCard card,
  required StorageService storage,
  required List<int> bytes,
  required Future<void> Function(CharacterCard card) updateCharacter,
}) async {
  if (bytes.isEmpty) return false;
  // Refuse garbage that isn't a decodable image — updateCharacter re-embeds
  // via saveCardAsPng, and a 4-byte stub used to throw inside the PSD probe.
  try {
    if (img.decodeImage(Uint8List.fromList(bytes)) == null) return false;
  } catch (_) {
    return false;
  }
  if (hasUsablePortrait(card, storage)) {
    if (!await isPlaceholderPortrait(card, storage)) return false;
  }
  final target = portraitWriteTarget(card: card, storage: storage);
  await target.writeAsBytes(bytes);
  await FileImage(target).evict();
  await updateCharacter(card);
  return true;
}
