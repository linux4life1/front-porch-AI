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
/// member's Lust), as the desktop sidebar's editor does. The group's own
/// switches come with the detail, read-only (the open chat's, or the group's
/// for new chats), and the member's start (`groupStart`) saves to the
/// group's seed for them.
class GroupMemberEdit {
  GroupMemberEdit(
    this._db,
    this._storage,
    this._chat,
    this._worlds, [
    this._groups,
  ]);

  final AppDatabase _db;
  final StorageService _storage;
  final ChatService? _chat;
  final WorldRepository? _worlds;
  final GroupChatRepository? _groups;

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

  /// Whether [groupId] is the group open in the chat.
  bool _open(String groupId) {
    final chat = _chat;
    return chat != null && chat.isGroupMode && chat.activeGroup?.id == groupId;
  }

  /// The group as stored (the open chat's copy while it is open, which
  /// Edit group's Save keeps current), or null when there is none.
  GroupChat? _definition(String groupId) {
    if (_open(groupId)) return _chat!.activeGroup;
    return _groups?.getById(groupId);
  }

  /// The member's card in the library editor's `/detail` shape, plus
  /// `groupId` and `groupName` for the page's banner, the group's own
  /// switches (`group`), the member's start in its new chats (`start`, null
  /// when they start without Realism) and `lite`. Null when the group has no
  /// such member.
  Future<Map<String, dynamic>?> detail(String groupId, String memberId) async {
    final c = await _card(groupId, memberId);
    if (c == null) return null;
    final group = await _db.getGroupById(groupId);
    final definition = _definition(groupId);
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
      // What the editor adds in member mode: the group's shared scene
      // (greyed Time & Day), the other members, and the group's values for
      // this member (the same store Edit group shows).
      if (definition != null) ...{
        'scene': {
          'timeOfDay': groupSceneOf(definition).timeOfDay,
          'dayCount': groupSceneOf(definition).dayCount,
          'storyStartDate': groupSceneOf(definition).storyStartDate,
          'storyStartTime': groupSceneOf(definition).storyStartTime,
        },
        'others': [
          for (final m in await _db.getGroupMembers(groupId))
            if (m.id != memberId) {'id': m.id, 'name': m.name},
        ],
        'groupValues': () {
          final v = groupMemberValuesOf(definition, memberId);
          return {
            'systemPrompt': v.systemPrompt,
            'note': v.note,
            'strength': v.strength,
            'feelings': v.feelings,
          };
        }(),
      },
      'lite': c.isLite,
      // Porch Life's Realism permission: false hides the member's Realism,
      // Needs and Afterglow behind a note, keeping their settings.
      'realismAllowed': _storage.realismSettings.realismAllowed,
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
    await _saveGroupValues(groupId, memberId, fields['groupValues']);
    return true;
  }

  /// The values the page's "In the group" section posted go to the group
  /// (never the card): its system prompt, Author's Note and feelings.
  Future<void> _saveGroupValues(
    String groupId,
    String memberId,
    Object? json,
  ) async {
    final groups = _groups;
    final g = _definition(groupId);
    if (json is! Map || groups == null || g == null) return;
    final now = groupMemberValuesOf(g, memberId);
    final feelings = <String, int>{...now.feelings};
    if (json['feelings'] is Map) {
      for (final e in (json['feelings'] as Map).entries) {
        if (e.value is num) feelings['${e.key}'] = (e.value as num).toInt();
      }
    }
    final next = GroupMemberValues(
      systemPrompt: json['systemPrompt'] is String
          ? json['systemPrompt'] as String
          : now.systemPrompt,
      note: json['note'] is String ? json['note'] as String : now.note,
      strength: json['strength'] is num
          ? (json['strength'] as num).toInt().clamp(1, 10)
          : now.strength,
      feelings: feelings,
    );
    if (next == now) return;
    applyGroupMemberValues(g, memberId, next);
    await groups.save(g);
  }
}
