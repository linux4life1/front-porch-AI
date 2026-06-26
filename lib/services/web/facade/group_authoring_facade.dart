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
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Group-chat authoring (create / edit settings / change membership) for the
/// web. Mirrors the desktop create flow: each chosen [CharacterCard] is
/// denormalized into a private `group_members` row and its avatar is copied into
/// `groups/<groupId>/avatars/` via the existing
/// [CharacterRepository.duplicateCharacter] (which re-embeds the V2 card), then
/// the [GroupChat] row is saved through [GroupChatRepository.save]. No group
/// simulation logic is reimplemented.
class GroupAuthoringFacade {
  GroupAuthoringFacade(this._groups, this._characters, this._db, this._storage);

  final GroupChatRepository _groups;
  final CharacterRepository _characters;
  final AppDatabase _db;
  final StorageService _storage;

  /// Settings + roster for the edit screen, or null if the group is unknown.
  Future<Map<String, dynamic>?> detail(String groupId) async {
    final g = _groups.getById(groupId);
    if (g == null) return null;
    final members = await _groups.getMembersForGroup(groupId);
    return {
      'id': g.id,
      'name': g.name,
      'turnOrder': g.turnOrder.name,
      'autoAdvance': g.autoAdvance,
      'directorMode': g.directorMode,
      'scenario': g.scenario,
      'firstMessage': g.firstMessage,
      'systemPrompt': g.systemPrompt,
      'chaosModeEnabled': g.chaosModeEnabled,
      'chaosNsfwEnabled': g.chaosNsfwEnabled,
      'inheritCharacterLorebooks': g.inheritCharacterLorebooks,
      'members': members
          .map((m) => {
                'id': m.id,
                'name': m.name,
                'hasAvatar':
                    m.avatarFilename != null && m.avatarFilename!.isNotEmpty,
              })
          .toList(),
    };
  }

  /// Create a group from ≥2 library character ids. Returns {id, name} or null.
  Future<Map<String, dynamic>?> create(Map<String, dynamic> f) async {
    final name = f['name']?.toString().trim() ?? '';
    final ids = _idList(f['characterIds']);
    if (name.isEmpty || ids.length < 2) return null;
    final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    if (!await _writeMembers(groupId, ids)) return null;
    await _groups.save(_buildGroup(groupId, f, null));
    return {'id': groupId, 'name': name};
  }

  /// Edit a group's settings and (optionally) its membership. When
  /// `characterIds` is present the roster is replaced (≥2 required). Realism
  /// blobs + per-member prompt overrides are preserved. Returns false if unknown.
  Future<bool> edit(String groupId, Map<String, dynamic> f) async {
    final existing = _groups.getById(groupId);
    if (existing == null) return false;
    if (f.containsKey('characterIds')) {
      final ids = _idList(f['characterIds']);
      if (ids.length < 2) return false;
      await _db.deleteGroupMembersForGroup(groupId);
      // Clear old private avatars so replaced members don't orphan files.
      final avDir = Directory(p.join(_storage.groupsDir.path, groupId, 'avatars'));
      if (await avDir.exists()) await avDir.delete(recursive: true);
      if (!await _writeMembers(groupId, ids)) return false;
    }
    await _groups.save(_buildGroup(groupId, f, existing));
    return true;
  }

  /// Build a [GroupChat] from web fields, falling back to [base] (an existing
  /// group on edit, or defaults on create) for any key not provided.
  GroupChat _buildGroup(
    String id,
    Map<String, dynamic> f,
    GroupChat? base,
  ) {
    bool b(String k, bool fallback) => f[k] is bool ? f[k] as bool : fallback;
    String s(String k, String fallback) =>
        f.containsKey(k) ? (f[k]?.toString() ?? fallback) : fallback;
    return GroupChat(
      id: id,
      name: s('name', base?.name ?? ''),
      turnOrder: f.containsKey('turnOrder')
          ? (f['turnOrder'] == 'random' ? TurnOrder.random : TurnOrder.roundRobin)
          : (base?.turnOrder ?? TurnOrder.roundRobin),
      autoAdvance: b('autoAdvance', base?.autoAdvance ?? false),
      directorMode: b('directorMode', base?.directorMode ?? false),
      firstMessage: s('firstMessage', base?.firstMessage ?? ''),
      scenario: s('scenario', base?.scenario ?? ''),
      systemPrompt: s('systemPrompt', base?.systemPrompt ?? ''),
      chaosModeEnabled: b('chaosModeEnabled', base?.chaosModeEnabled ?? false),
      chaosNsfwEnabled: b('chaosNsfwEnabled', base?.chaosNsfwEnabled ?? false),
      inheritCharacterLorebooks:
          b('inheritCharacterLorebooks', base?.inheritCharacterLorebooks ?? true),
      // Preserve advanced/desktop-authored state on edit.
      characterSystemPrompts: base?.characterSystemPrompts,
      worldIds: base?.worldIds ?? const [],
      groupLorebook: base?.groupLorebook ?? '',
      defaultMemberRealismState: base?.defaultMemberRealismState ?? '{}',
      baselineRealismState: base?.baselineRealismState ?? '{}',
    );
  }

  /// Denormalize each character into a private member row + copy its avatar into
  /// the group's avatar dir. Returns false if any id is unknown.
  Future<bool> _writeMembers(String groupId, List<String> characterIds) async {
    final avDir = Directory(p.join(_storage.groupsDir.path, groupId, 'avatars'));
    if (!await avDir.exists()) await avDir.create(recursive: true);
    for (final cid in characterIds) {
      final card = await _characters.getCharacterCardById(cid);
      if (card == null) return false;
      final mid = const Uuid().v4();
      // Reuse the desktop clone path: copies the avatar to <avDir>/<mid>.png and
      // re-embeds the V2 card (or synthesizes a placeholder when imageless).
      await _characters.duplicateCharacter(
        card,
        targetDirOverride: avDir.path,
        forcedBasename: mid,
        skipLibraryInsert: true,
      );
      await _db.insertGroupMember(GroupMembersCompanion(
        id: Value(mid),
        groupId: Value(groupId),
        name: Value(card.name),
        description: Value(card.description),
        personality: Value(card.personality),
        scenario: Value(card.scenario),
        firstMessage: Value(card.firstMessage),
        mesExample: Value(card.mesExample),
        systemPrompt: Value(card.systemPrompt),
        postHistoryInstructions: Value(card.postHistoryInstructions),
        alternateGreetings: Value(jsonEncode(card.alternateGreetings)),
        tags: Value(jsonEncode(card.tags)),
        avatarFilename: Value('$mid.png'),
        ttsVoice: Value(card.ttsVoice),
        lorebook: Value(card.lorebook != null
            ? jsonEncode(card.lorebook!.toJson())
            : null),
        worldNames: Value(jsonEncode(card.worldNames)),
        frontPorchExtensions: Value(card.frontPorchExtensions != null
            ? jsonEncode(card.frontPorchExtensions!.toJson())
            : null),
        memberState: const Value('{}'),
      ));
    }
    return true;
  }

  List<String> _idList(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];
}
