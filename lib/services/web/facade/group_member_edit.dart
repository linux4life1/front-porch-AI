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

  /// Whether [groupId] is the group open in the chat.
  bool _open(String groupId) {
    final chat = _chat;
    return chat != null && chat.isGroupMode && chat.activeGroup?.id == groupId;
  }

  /// The group's definition: the open chat's copy (it holds edits Group
  /// Settings has not saved yet) or one read from its row.
  GroupChat? _definition(String groupId, Group? row) {
    if (_open(groupId)) return _chat!.activeGroup;
    if (row == null) return null;
    List<String> ids(String? json) {
      try {
        final v = json == null ? null : jsonDecode(json);
        return v is List ? [for (final e in v) '$e'] : const [];
      } catch (_) {
        return const [];
      }
    }

    return GroupChat(
      id: row.id,
      name: row.name,
      worldIds: ids(row.worldIds),
      loreWorldIds: row.loreWorldIds == null ? null : ids(row.loreWorldIds),
      inheritCharacterLorebooks: row.inheritCharacterLorebooks,
      chaosModeEnabled: row.chaosModeEnabled,
      defaultMemberRealismState: row.defaultMemberRealismState,
      baselineRealismState: row.baselineRealismState,
    );
  }

  /// The group's own switches as a member's editor shows them.
  GroupWideValues? _values(String groupId, GroupChat? g) {
    if (g == null) return null;
    if (_open(groupId)) return groupWideValuesOfChat(_chat!, worlds: _worlds);
    return groupWideValuesOfTemplate(
      defaultMemberJson: g.defaultMemberRealismState,
      baselineJson: g.baselineRealismState,
      chaos: g.chaosModeEnabled,
      settingName: groupSettingNameIn(g, _worlds),
      readsMemberLorebooks: g.inheritCharacterLorebooks,
    );
  }

  /// One line per member for the phone's Group Settings: where each starts
  /// in new chats of the group and their own Afterglow (null while Porch Life
  /// or the group keeps Afterglow off). Null when there is no such group.
  Future<List<Map<String, dynamic>>?> summaries(String groupId) async {
    final row = await _db.getGroupById(groupId);
    final g = _definition(groupId, row);
    if (g == null) return null;
    final values = _values(groupId, g);
    final afterglowShown =
        _storage.realismSettings.afterglowEnabled &&
        (values?.afterglow ?? false);
    return [
      for (final m in await _db.getGroupMembers(groupId))
        () {
          final c = GroupMember.fromRow(
            m,
          ).toCharacterCard(resolvedImagePath: '');
          final ext = c.frontPorchExtensions;
          return {
            'id': m.id,
            'name': c.name,
            'start': groupMemberStartIn(
              g.defaultMemberRealismState,
              m.id,
              card: ext,
              legacyIds: [?GroupMember.fromRow(m).originStableId],
            )?.toJson(),
            'afterglow': afterglowShown ? ext?.afterglowEnabled ?? true : null,
            'lite': c.isLite,
          };
        }(),
    ];
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
    final definition = _definition(groupId, group);
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
      'group': _values(groupId, definition)?.toJson(),
      'start': definition == null
          ? null
          : groupMemberStartIn(
              definition.defaultMemberRealismState,
              memberId,
              card: ext,
              legacyIds: await groupMemberLegacyKeys(_db, groupId, memberId),
            )?.toJson(),
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
    await _saveStart(groupId, memberId, c, fields['groupStart']);
    return true;
  }

  /// A `groupStart` the page sent goes to the group's seed for the member
  /// (never their card), over the start stored now: a field it leaves out
  /// keeps its value. An older page sends none.
  Future<void> _saveStart(
    String groupId,
    String memberId,
    CharacterCard c,
    Object? json,
  ) async {
    if (json is! Map) return;
    final definition = _definition(groupId, await _db.getGroupById(groupId));
    final ext = c.frontPorchExtensions;
    final now = definition == null
        ? null
        : groupMemberStartIn(
            definition.defaultMemberRealismState,
            memberId,
            card: ext,
            legacyIds: await groupMemberLegacyKeys(_db, groupId, memberId),
          );
    if (now == null) return;
    final next = GroupMemberStart.fromJson(json, now);
    if (next == now) return;
    await saveGroupMemberStart(
      _db,
      groupId: groupId,
      mid: memberId,
      start: next,
      card: ext,
      chat: _chat,
    );
  }
}
