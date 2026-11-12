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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/character/character.dart'
    show normalizeLorebookJson;
import 'package:front_porch_ai/services/web/util/util.dart';
import 'package:front_porch_ai/database/database.dart'
    show AppDatabase, AppDatabaseGroupQueries;
import 'package:front_porch_ai/utils/utils.dart';

/// The phone's Edit group page: one read of everything the desktop page
/// shows (additive fields; an older client ignores them) and the writes for
/// the fields the older settings route does not take. Cast changes go
/// through [GroupRosterEditor], the same row writers the desktop page and
/// the chat's roster use.
class GroupEditorRelay {
  GroupEditorRelay(
    this._groups,
    this._storage,
    this._db,
    this._characters, [
    this.chat,
  ]);

  /// The running chat, so a cast change reaches a group that is open in it.
  ChatService? chat;

  final GroupChatRepository _groups;
  final StorageService _storage;
  final AppDatabase? _db;
  final CharacterRepository? _characters;

  GroupRosterEditor? get _roster => _db == null
      ? null
      : GroupRosterEditor(db: _db, groupsDir: _storage.groupsDir);

  /// The group's editable detail, or null when there is no such group.
  Future<Map<String, dynamic>?> detail(String groupId) async {
    final g = _groups.getById(groupId);
    if (g == null) return null;
    final members = await _groups.getMembersForGroup(groupId);
    final removed = await _roster?.removedMembers(groupId) ?? const [];
    final scene = groupSceneOf(g);
    return {
      'id': g.id,
      'name': g.name,
      'turnOrder': g.turnOrder.name,
      'autoAdvance': g.autoAdvance,
      'directorMode': g.directorMode,
      'personality': g.personality,
      'scenario': g.scenario,
      'systemPrompt': g.systemPrompt,
      'postHistoryInstructions': g.postHistoryInstructions,
      'mesExample': g.mesExample,
      'firstMessage': g.firstMessage,
      'alternateGreetings': g.alternateGreetings,
      'greetingSeeds': [for (final x in g.greetingSeeds) x?.toJson()],
      'tags': g.tags,
      'chaosModeEnabled': g.chaosModeEnabled,
      'inheritCharacterLorebooks': g.inheritCharacterLorebooks,
      'realism': {
        'timeOfDay': scene.timeOfDay,
        'dayCount': scene.dayCount,
        'storyStartDate': g.storyStartDate,
        'storyStartTime': g.storyStartTime,
        'verificationEnabled': g.realismVerificationEnabled,
        'verificationStrictness': g.realismVerificationStrictness,
        'verificationMaxReprocesses': g.realismVerificationMaxReprocesses,
        'directorAuthority': g.needsDirectorAuthority,
      },
      'lorebook': normalizeLorebookJson(
        g.groupLorebook.isEmpty ? null : g.groupLorebook,
      ),
      'members': [
        for (final m in members)
          () {
            final v = groupMemberValuesOf(g, m.id);
            return {
              'id': m.id,
              'name': m.name,
              'voice': m.ttsVoice ?? '',
              'prompt': v.systemPrompt,
              'note': v.note,
              'strength': v.strength,
            };
          }(),
      ],
      'feelings': startingFeelingsIn(g.defaultMemberRealismState),
      'removedCount': removed.length,
    };
  }

  /// "Your chats together" over the group's chats, or null with no database.
  Future<Map<String, dynamic>?> stats(String groupId) async {
    final db = _db;
    if (db == null || _groups.getById(groupId) == null) return null;
    return (await loadGroupStats(db, groupId)).toJson();
  }

  /// Applies the fields the Edit group page posts that the older settings
  /// route does not take. Fields left out keep their value.
  void apply(GroupChat g, Map<String, dynamic> f) {
    String? s(String k) => f[k] is String ? f[k] as String : null;
    bool? b(String k) => f[k] is bool ? f[k] as bool : null;
    g.personality = s('personality') ?? g.personality;
    g.postHistoryInstructions =
        s('postHistoryInstructions') ?? g.postHistoryInstructions;
    g.mesExample = s('mesExample') ?? g.mesExample;
    if (f['tags'] is List) {
      g.tags = [for (final t in f['tags'] as List) '$t'];
    }
    g.autoAdvance = b('autoAdvance') ?? g.autoAdvance;
    g.directorMode = b('directorMode') ?? g.directorMode;
    g.chaosModeEnabled = b('chaosModeEnabled') ?? g.chaosModeEnabled;
    g.inheritCharacterLorebooks =
        b('inheritCharacterLorebooks') ?? g.inheritCharacterLorebooks;
    if (f.containsKey('lorebook')) {
      final book = buildLorebookFromJson(f['lorebook']);
      g.groupLorebook = book == null ? '' : jsonEncode(book.toJson());
    }
    final r = f['realism'];
    if (r is Map) {
      if (r['timeOfDay'] is String || r['dayCount'] is num) {
        final seed = groupSceneOf(g);
        g.defaultMemberRealismState = withGroupSceneTime(
          g.defaultMemberRealismState,
          timeOfDay: r['timeOfDay'] is String
              ? r['timeOfDay'] as String
              : seed.timeOfDay,
          dayCount: r['dayCount'] is num
              ? (r['dayCount'] as num).toInt().clamp(1, 100000)
              : seed.dayCount,
        );
      }
      if (r.containsKey('storyStartDate')) {
        g.storyStartDate = r['storyStartDate'] as String?;
      }
      if (r.containsKey('storyStartTime')) {
        g.storyStartTime = r['storyStartTime'] as String?;
      }
      g.realismVerificationEnabled = r['verificationEnabled'] is bool
          ? r['verificationEnabled'] as bool
          : g.realismVerificationEnabled;
      if (r['verificationStrictness'] is num) {
        g.realismVerificationStrictness = (r['verificationStrictness'] as num)
            .toInt()
            .clamp(1, 5);
      }
      if (r['verificationMaxReprocesses'] is num) {
        g.realismVerificationMaxReprocesses =
            (r['verificationMaxReprocesses'] as num).toInt().clamp(1, 5);
      }
      g.needsDirectorAuthority = r['directorAuthority'] is bool
          ? r['directorAuthority'] as bool
          : g.needsDirectorAuthority;
    }
    final notes = f['characterAuthorNotes'];
    if (notes is Map) {
      g.characterAuthorNotes = MemberAuthorNote.parseAll(notes);
    }
    final feelings = f['feelings'];
    if (feelings is Map) {
      for (final from in feelings.entries) {
        if (from.value is! Map) continue;
        for (final to in (from.value as Map).entries) {
          if (to.value is! num) continue;
          g.defaultMemberRealismState = withStartingFeeling(
            g.defaultMemberRealismState,
            from: '${from.key}',
            to: '${to.key}',
            score: (to.value as num).toInt(),
          );
        }
      }
    }
  }

  /// The cast: {action: add|remove|bringBack, characterId?, memberId?}.
  /// Answers the new detail, or null when nothing could be done.
  Future<Map<String, dynamic>?> cast(
    String groupId,
    Map<String, dynamic> body,
  ) async {
    final roster = _roster;
    final characters = _characters;
    if (roster == null || _groups.getById(groupId) == null) return null;
    final ops = GroupCastOps(
      editor: roster,
      groups: _groups,
      characters: characters,
      chat: chat,
    );
    switch (body['action']) {
      case 'add':
        final card = characters?.characters
            .where((c) => c.dbId == body['characterId'])
            .firstOrNull;
        if (card == null || !await ops.add(groupId, card)) return null;
      case 'remove':
        if (!await ops.remove(groupId, '${body['memberId']}')) return null;
      case 'bringBack':
        final row = (await roster.removedMembers(groupId))
            .where((r) => body['memberId'] == null || r.id == body['memberId'])
            .firstOrNull;
        if (row == null) return null;
        await ops.bringBack(groupId, row);
      default:
        return null;
    }
    return detail(groupId);
  }
}
