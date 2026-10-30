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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// "Extract Characters": copy every group member that has a private avatar
/// into the library as an independent character. The copies land in the
/// folder the group lives in, so they appear right where the user is looking
/// instead of on the home top level. Shared by the desktop card menu and the
/// web `/api/groups/<id>/extract` route; the one extraction rule.
class GroupMemberExtractor {
  GroupMemberExtractor(this._groups, this._storage, this._repo, this._folders);

  final GroupChatRepository _groups;
  final StorageService _storage;
  final CharacterRepository _repo;

  /// Null in boots with no folder tree; copies then stay on the top level.
  final FolderService? _folders;

  /// Returns how many members were extracted. Members without an avatar file
  /// on disk are skipped, and one failing member does not abort the batch.
  Future<int> extract(String groupId) async {
    final members = await _groups.getMembersForGroup(groupId);
    final copies = <String>[];
    var extracted = 0;
    for (final m in members) {
      try {
        final name = m.avatarFilename;
        if (name == null) continue;
        final avatar = p.join(
          _storage.groupsDir.path,
          groupId,
          'avatars',
          name,
        );
        if (!await File(avatar).exists()) continue;
        final copy = await _repo.duplicateCharacter(
          m.toCharacterCard(resolvedImagePath: avatar),
        );
        if (copy == null) continue;
        extracted++;
        final path = copy.imagePath;
        if (path != null) copies.add(path);
      } catch (e) {
        debugPrint('[Extract] Failed to extract ${m.name}: $e');
      }
    }
    final folder = _folders?.getFolderForGroup(groupId);
    if (folder != null && copies.isNotEmpty) {
      await _folders!.moveMany(folderId: folder.id, characterPaths: copies);
    }
    return extracted;
  }
}
