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

part of 'expression_pack_dialog.dart';

/// The best on-disk portrait for [characterDbId]: the prime (else first)
/// expression avatar when any exist, else the character's MAIN card avatar
/// ([CharacterCard.imagePath]). The card avatar is the load-bearing case —
/// a character about to get their first expression pack has no expression
/// images yet (creating them is the whole point), but almost always has a
/// card portrait. Null only when the character has no image at all.
Future<Uint8List?> _primeAvatarBytes(
  CharacterRepository repository,
  StorageService storage,
  String characterDbId,
  String characterName,
) async {
  CharacterCard? card;
  for (final c in repository.characters) {
    if (c.dbId == characterDbId) {
      card = c;
      break;
    }
  }

  final avatars = await repository.getAvatarImages(characterDbId);
  if (avatars.isNotEmpty) {
    // primeAvatarIndex is 1-based; clamp handles stale indices.
    final primeIdx = ((card?.primeAvatarIndex ?? 1) - 1).clamp(
      0,
      avatars.length - 1,
    );
    final dirPath = storage.characterAvatarDir(characterName).path;
    for (final avatar in [avatars[primeIdx], ...avatars]) {
      final file = avatar.file(dirPath);
      if (await file.exists()) return file.readAsBytes();
    }
  }

  final imagePath = card?.imagePath;
  if (imagePath != null && imagePath.isNotEmpty) {
    final file = File(imagePath);
    if (await file.exists()) return file.readAsBytes();
  }
  return null;
}
