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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
import 'package:front_porch_ai/services/web/facade/character/character.dart';

/// The web editor for a group member: the desktop member editor's twin. A
/// member is the group's own copy of a character, so the edit saves to its
/// group_members row and never reaches the library card or its other chats.
/// While the group is open in the chat, the chat's own copy is the one edited,
/// and a changed Afterglow switch is set through the chat (which clears the
/// member's Lust), as the desktop sidebar's editor does.
class GroupMemberEdit {
  GroupMemberEdit(this._db, this._storage, this._chat, this._worlds);

  final AppDatabase _db;
  final StorageService _storage;
  final ChatService? _chat;
  final WorldRepository? _worlds;

  /// The open chat's copy of the member when [groupId] is the group open in
  /// the chat; otherwise one loaded from the member's row.
  Future<CharacterCard?> _card(String groupId, String memberId) async {
    final chat = _chat;
    if (chat != null && chat.isGroupMode && chat.activeGroup?.id == groupId) {
      for (final c in chat.groupCharacters) {
        if (c.dbId == memberId) return c;
      }
    }
    for (final row in await _db.getGroupMembers(groupId)) {
      if (row.id == memberId) {
        return GroupMember.fromRow(row).toCharacterCard(resolvedImagePath: '');
      }
    }
    return null;
  }

  /// The member's card in the library editor's `/detail` shape, plus
  /// `groupId` and `groupName` for the page's banner. Null when the group has
  /// no such member.
  Future<Map<String, dynamic>?> detail(String groupId, String memberId) async {
    final c = await _card(groupId, memberId);
    if (c == null) return null;
    final group = await _db.getGroupById(groupId);
    final ext = c.frontPorchExtensions;
    final voice = readNarrativeVoice(c);
    return {
      'id': memberId,
      'groupId': groupId,
      'groupName': group?.name ?? '',
      'name': c.name,
      'description': c.description,
      'personality': c.personality,
      'scenario': c.scenario,
      'firstMessage': c.firstMessage,
      'mesExample': c.mesExample,
      'systemPrompt': c.systemPrompt,
      'postHistoryInstructions': c.postHistoryInstructions,
      'alternateGreetings': c.alternateGreetings,
      'tags': c.tags,
      'worldNames': c.worldNames,
      'worlds': ?characterWorldsJson(c, _worlds),
      'lorebook': normalizeLorebookJson(
        c.lorebook == null ? null : jsonEncode(c.lorebook!.toJson()),
      ),
      'ttsVoice': c.ttsVoice,
      'realism': ext != null
          ? frontPorchToJson(
              ext,
              needsSimWhenSilent: _storage.realismSettings.needsSimDefault,
            )
          : null,
      'narrativePerspective': voice.perspective,
      'narrativeTense': voice.tense,
      'sex': voice.sex,
    };
  }

  /// Apply the editor's [fields] to the member and save their row. False when
  /// the group has no such member.
  Future<bool> update(
    String groupId,
    String memberId,
    Map<String, dynamic> fields,
  ) async {
    final c = await _card(groupId, memberId);
    if (c == null) return false;
    final afterglowBefore = c.frontPorchExtensions?.afterglowEnabled ?? true;
    // The page always posts its Realism fields. Over extensions the app could
    // not read they are only defaults; the save keeps what is stored.
    applyCharacterFields(
      c,
      fields,
      needsSimDefault: _storage.realismSettings.needsSimDefault,
    );
    applyCharacterWorlds(c, fields['worlds'], _worlds);
    await saveGroupMemberCard(_db, c);
    final chat = _chat;
    if (chat != null && isOpenGroupMember(chat, c)) {
      chat.refreshActiveCharacterCard(c);
      await settleMemberAfterglow(chat, c, afterglowBefore);
    }
    return true;
  }
}
