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

import 'package:front_porch_ai/models/avatar_image.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';

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

  /// List a character's avatars as JSON (id, label, displayOrder, isPrime).
  Future<List<Map<String, dynamic>>> avatars(String id) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return const [];
    final images = await _repo.getAvatarImages(id);
    return images
        .map((a) => {
              'id': a.id,
              'label': a.label ?? '',
              'displayOrder': a.displayOrder,
              'isPrime': a.displayOrder + 1 == card.primeAvatarIndex,
            })
        .toList();
  }

  /// Add an avatar from uploaded bytes. Returns false if the character is gone.
  Future<bool> addAvatar(String id, List<int> bytes, String? label) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return false;
    await _repo.addAvatar(
      id,
      card.name,
      Uint8List.fromList(bytes),
      (label != null && label.trim().isEmpty) ? null : label,
    );
    return true;
  }

  Future<bool> removeAvatar(String id, String avatarId) async {
    final card = await _repo.getCharacterCardById(id);
    if (card == null) return false;
    await _repo.removeAvatar(id, avatarId);
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
    final dir = p.join(_storage.charactersDir.path, safeName, 'avatars');
    final file = target.file(dir);
    return file.existsSync() ? file : null;
  }
}
