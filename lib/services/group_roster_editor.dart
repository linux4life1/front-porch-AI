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

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/database/database.dart'
    show AppDatabase, AppDatabaseGroupQueries, GroupMemberRow;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/doors/entry/group_member_rows.dart';

/// Edit group's cast changes, made on the group's rows whether or not its
/// chat is open (the chat's own roster uses the same two row writers,
/// [insertGroupMemberRow] and [deleteGroupMemberRows]). A removed member's
/// copy is kept beside the group, so "Bring back a removed member" has
/// something to bring back.
class GroupRosterEditor {
  GroupRosterEditor({required this.db, required this.groupsDir});

  final AppDatabase db;
  final Directory groupsDir;

  /// A group is a group while it has at least this many members.
  static const minMembers = 2;

  Directory _removedDir(String groupId) =>
      Directory(path.join(groupsDir.path, groupId, 'removed'));

  /// Adds [character] to [groupId] as a full member with a copy of its card.
  Future<String> add({
    required CharacterRepository characters,
    required String groupId,
    required CharacterCard character,
  }) => insertGroupMemberRow(
    db: db,
    groupsDir: groupsDir,
    characters: characters,
    groupId: groupId,
    character: character,
  );

  /// Keeps a copy of [row] (and its avatar) beside the group, for
  /// [removedMembers].
  Future<void> keepCopy(String groupId, GroupMemberRow row) async {
    final dir = _removedDir(groupId);
    await dir.create(recursive: true);
    final avatar = row.avatarFilename;
    if (avatar != null) {
      final src = File(path.join(groupsDir.path, groupId, 'avatars', avatar));
      if (await src.exists()) await src.copy(path.join(dir.path, avatar));
    }
    await File(
      path.join(dir.path, '${row.id}.json'),
    ).writeAsString(jsonEncode(row.toJson()));
  }

  /// Forgets the kept copy of [row] (it was brought back another way).
  Future<void> discardKept(String groupId, GroupMemberRow row) async {
    final dir = _removedDir(groupId);
    for (final name in [row.avatarFilename, '${row.id}.json']) {
      if (name == null) continue;
      final f = File(path.join(dir.path, name));
      if (await f.exists()) await f.delete();
    }
  }

  /// The row of member [mid] in [groupId], or null.
  Future<GroupMemberRow?> rowOf(String groupId, String mid) async =>
      (await db.getGroupMembers(groupId)).where((r) => r.id == mid).firstOrNull;

  /// How many members [groupId] has.
  Future<int> count(String groupId) async =>
      (await db.getGroupMembers(groupId)).length;

  /// Removes member [mid]. False, and nothing changes, when that would leave
  /// fewer than [minMembers]. The member's copy and avatar are kept for
  /// [removedMembers].
  Future<bool> remove(String groupId, String mid) async {
    final rows = await db.getGroupMembers(groupId);
    final row = rows.where((r) => r.id == mid).firstOrNull;
    if (row == null || rows.length <= minMembers) return false;
    await keepCopy(groupId, row);
    await deleteGroupMemberRows(
      db: db,
      groupsDir: groupsDir,
      groupId: groupId,
      mid: mid,
      avatarFilename: row.avatarFilename,
    );
    return true;
  }

  /// The members removed from [groupId] and kept, oldest first.
  Future<List<GroupMemberRow>> removedMembers(String groupId) async {
    final dir = _removedDir(groupId);
    if (!await dir.exists()) return const [];
    final out = <GroupMemberRow>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        out.add(
          GroupMemberRow.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>,
          ),
        );
      } catch (e) {
        debugPrint('[Roster] a kept member could not be read: $e');
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// Puts [row] back in [groupId] as it was, avatar included, and drops the
  /// kept copy.
  Future<void> bringBack(String groupId, GroupMemberRow row) async {
    final dir = _removedDir(groupId);
    final avatar = row.avatarFilename;
    if (avatar != null) {
      final kept = File(path.join(dir.path, avatar));
      if (await kept.exists()) {
        final avDir = Directory(path.join(groupsDir.path, groupId, 'avatars'));
        await avDir.create(recursive: true);
        await kept.copy(path.join(avDir.path, avatar));
        await kept.delete();
      }
    }
    await db.insertGroupMember(
      row.toCompanion(true).copyWith(groupId: Value(groupId)),
    );
    final json = File(path.join(dir.path, '${row.id}.json'));
    if (await json.exists()) await json.delete();
  }
}
