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

import 'package:front_porch_ai/database/database.dart' show GroupMemberRow;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/group_roster_editor.dart';

/// Edit group's cast changes for desktop and phone: on the group's rows
/// ([GroupRosterEditor]), or, while the group is open in [chat], through the
/// chat's own roster so the running chat follows.
class GroupCastOps {
  GroupCastOps({
    required this.editor,
    required this.groups,
    required this.characters,
    this.chat,
  });

  final GroupRosterEditor editor;
  final GroupChatRepository groups;
  final CharacterRepository? characters;
  final ChatService? chat;

  bool isOpen(String groupId) => chat?.activeGroup?.id == groupId;

  /// Adds [card] as a full member. False when the chat refused it.
  Future<bool> add(String groupId, CharacterCard card) async {
    if (isOpen(groupId)) return chat!.addCharacterToGroup(card, groups);
    await editor.add(
      characters: characters!,
      groupId: groupId,
      character: card,
    );
    return true;
  }

  /// Removes member [mid], keeping a copy to bring back. False when the group
  /// would drop below two members or there is no such member.
  Future<bool> remove(String groupId, String mid) async {
    if (await editor.count(groupId) <= GroupRosterEditor.minMembers) {
      return false;
    }
    if (!isOpen(groupId)) return editor.remove(groupId, mid);
    final row = await editor.rowOf(groupId, mid);
    final card = chat!.groupCharacters.where((c) => c.dbId == mid).firstOrNull;
    if (row == null || card == null) return false;
    await editor.keepCopy(groupId, row);
    return chat!.removeCharacterFromGroup(card, groups);
  }

  /// Puts a kept member back (the chat re-adds their copy while it is open).
  Future<void> bringBack(String groupId, GroupMemberRow row) async {
    if (!isOpen(groupId)) return editor.bringBack(groupId, row);
    final card = GroupMember.fromRow(
      row,
    ).toCharacterCard(resolvedImagePath: '');
    await chat!.addCharacterToGroup(card, groups);
    await editor.discardKept(groupId, row);
  }
}
