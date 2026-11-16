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

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart'
    show AppDatabase, AppDatabaseGroupQueries;

/// "Duplicate Group": a copy of the group's definition and nothing it has
/// lived through. The copy is named "NAME (copy)", gets a fresh id and
/// stable id, and every member gets a fresh member id with its own avatar
/// file under the new group's directory. Every group setting (including the
/// ones added since), the group lorebook, worlds, and the per-member prompts,
/// notes and starting feelings come over; chats, memories and journals do
/// not, and no file is shared with the original.
class GroupDuplicator {
  GroupDuplicator({required this.db, required this.groupsDir});

  final AppDatabase db;
  final Directory groupsDir;

  /// The new group's id, or null when [groupId] is not a live group.
  Future<String?> duplicate(String groupId) async {
    final g = await db.getGroupById(groupId);
    if (g == null || g.deletedAt != null) return null;
    final members = await db.getGroupMembers(groupId);
    final newId = await _freshId();
    final newMemberIds = {for (final m in members) m.id: const Uuid().v4()};

    // Per-member settings are keyed by member id inside JSON text: carry
    // them over under the new ids.
    String remap(String s) {
      var out = s;
      newMemberIds.forEach((old, fresh) => out = out.replaceAll(old, fresh));
      return out;
    }

    String? remapN(String? s) => s == null ? null : remap(s);

    final now = DateTime.now();
    final avatarsFrom = Directory(
      path.join(groupsDir.path, groupId, 'avatars'),
    );
    final avatarsTo = Directory(path.join(groupsDir.path, newId, 'avatars'));
    try {
      for (final m in members) {
        final file = m.avatarFilename;
        if (file == null) continue;
        final src = File(path.join(avatarsFrom.path, file));
        if (!await src.exists()) continue;
        await avatarsTo.create(recursive: true);
        await src.copy(path.join(avatarsTo.path, file));
      }
      await db.insertGroup(
        g
            .toCompanion(false)
            .copyWith(
              id: Value(newId),
              name: Value('${g.name} (copy)'),
              stableId: const Value(null),
              defaultMemberRealismState: Value(
                remap(g.defaultMemberRealismState),
              ),
              baselineRealismState: Value(remap(g.baselineRealismState)),
              characterSystemPrompts: Value(remap(g.characterSystemPrompts)),
              characterAuthorNotes: Value(remap(g.characterAuthorNotes)),
              updatedAt: Value(now),
            ),
      );
      for (final m in members) {
        await db.insertGroupMember(
          m
              .toCompanion(false)
              .copyWith(
                id: Value(newMemberIds[m.id]!),
                groupId: Value(newId),
                memberState: Value(remap(m.memberState)),
                frontPorchExtensions: Value(remapN(m.frontPorchExtensions)),
                updatedAt: Value(now),
                createdAt: Value(now.millisecondsSinceEpoch),
              ),
        );
      }
    } catch (_) {
      // Leave nothing half-made behind: no files, no group row.
      final dir = Directory(path.join(groupsDir.path, newId));
      if (await dir.exists()) await dir.delete(recursive: true);
      await db.deleteGroupById(newId);
      rethrow;
    }
    return newId;
  }

  Future<String> _freshId() async {
    var stamp = DateTime.now().millisecondsSinceEpoch;
    while (await db.getGroupById('group_$stamp') != null) {
      stamp++;
    }
    return 'group_$stamp';
  }
}
