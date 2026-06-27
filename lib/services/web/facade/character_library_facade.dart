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

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

/// Write-side adapter for the character *library*: folder CRUD, moving cards
/// into/out of folders, duplicating a card, and exporting a card (PNG / JSON).
///
/// Every method delegates to the exact desktop service the home page uses
/// ([FolderService], [CharacterRepository.duplicateCharacter], [V2CardService])
/// so PNG/DB side-effects and parity are identical — this facade only resolves
/// a client-supplied **id** to the server-owned on-disk path and validates it,
/// never trusting a client filesystem path. Distinct from [CharacterFacade]
/// (read/list + create/edit text) so neither file grows a second concern.
class CharacterLibraryFacade {
  CharacterLibraryFacade(this._repo, this._folders);

  final CharacterRepository _repo;
  final FolderService _folders;

  /// Resolve a character by its DB id (in-memory card first, DB fallback), or
  /// null when it doesn't exist.
  Future<CharacterCard?> _resolve(String id) => _repo.getCharacterCardById(id);

  /// True when [folderId] is a real folder — guards every write against a
  /// spoofed/stale folder id before any DB mutation.
  bool _folderExists(String folderId) =>
      _folders.folders.any((f) => f.id == folderId);

  /// A filesystem-safe download base name (no extension) for [name].
  static String safeFileBase(String name) {
    final base = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return base.isEmpty ? 'character' : base;
  }

  /// Create a folder (optionally nested under [parentId]). Returns the new
  /// folder {id, name, parentId?} or null when the name is empty or the parent
  /// id is invalid.
  Future<Map<String, dynamic>?> createFolder(
    String name, {
    String? parentId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final parent = (parentId != null && parentId.isNotEmpty) ? parentId : null;
    if (parent != null && !_folderExists(parent)) return null;
    final folder = await _folders.createFolder(trimmed, parentId: parent);
    return {
      'id': folder.id,
      'name': folder.name,
      if (folder.parentId != null) 'parentId': folder.parentId,
    };
  }

  /// Rename a folder. Returns false when the id is unknown or the name empty.
  Future<bool> renameFolder(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || !_folderExists(id)) return false;
    await _folders.renameFolder(id, trimmed);
    return true;
  }

  /// Delete a folder (FolderService recursively deletes child folders and
  /// unassigns members back to the root). Returns false when the id is unknown.
  Future<bool> deleteFolder(String id) async {
    if (!_folderExists(id)) return false;
    await _folders.deleteFolder(id);
    return true;
  }

  /// Move a character into [folderId], or back to the root when [folderId] is
  /// null/empty. The on-disk path is resolved from the DB row — never trusted
  /// from the client. Returns false when the character or target folder is
  /// unknown.
  Future<bool> moveToFolder(String charId, String? folderId) async {
    final card = await _resolve(charId);
    if (card == null || card.imagePath == null || card.imagePath!.isEmpty) {
      return false;
    }
    final target = (folderId != null && folderId.isNotEmpty) ? folderId : null;
    if (target == null) {
      final current = _folders.getFolderForCharacter(card.imagePath!);
      if (current == null) return true; // already at root — idempotent success
      await _folders.removeFromFolder(current.id, card.imagePath!);
      return true;
    }
    if (!_folderExists(target)) return false;
    await _folders.addToFolder(target, card.imagePath!);
    return true;
  }

  /// Move many characters at once; returns how many actually moved.
  Future<int> bulkMove(List<String> ids, String? folderId) async {
    var moved = 0;
    for (final id in ids) {
      if (await moveToFolder(id, folderId)) moved++;
    }
    return moved;
  }

  /// Duplicate a character (deep-copies extensions + fresh stable id via the
  /// desktop path). Returns the new {id, name} or null.
  Future<Map<String, dynamic>?> duplicate(String charId) async {
    final card = await _resolve(charId);
    if (card == null) return null;
    final dup = await _repo.duplicateCharacter(card);
    if (dup == null) return null;
    return {'id': dup.dbId, 'name': dup.name};
  }

  /// Export a character as a V2 PNG card (bytes encoded in-memory, with the
  /// current avatar as the cover and the full `chara` metadata embedded).
  Future<({List<int> bytes, String filename})?> exportPng(String charId) async {
    final card = await _resolve(charId);
    if (card == null) return null;
    final bytes = await V2CardService().encodeCharacterCardToPngBytes(
      card,
      card.imagePath,
    );
    return (bytes: bytes, filename: '${safeFileBase(card.name)}.png');
  }

  /// Export a character as a standalone V2 `.json` card (same envelope embedded
  /// in PNGs). Reuses [V2CardService.saveCardAsJson] via a temp file so there is
  /// no second serializer.
  Future<({String json, String filename})?> exportJson(String charId) async {
    final card = await _resolve(charId);
    if (card == null) return null;
    final tmp = File(
      p.join(
        Directory.systemTemp.path,
        'fpa_export_${DateTime.now().microsecondsSinceEpoch}.json',
      ),
    );
    try {
      await V2CardService().saveCardAsJson(card, tmp.path);
      final json = await tmp.readAsString();
      return (json: json, filename: '${safeFileBase(card.name)}.json');
    } catch (_) {
      return null;
    } finally {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {}
    }
  }
}
