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
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/group_member.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_card_exporter.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// Read adapter over the group store for the web library — lists group chats,
/// resolves member avatars, and handles library card actions (export Group Card
/// PNG, extract members to the library). Activating a group lives in [ChatFacade]
/// (`selectGroup`) alongside character selection, to keep "what is the active
/// chat" in one place. Reuses GroupChatRepository / GroupCardExporter /
/// CharacterRepository directly; no duplicated logic.
class GroupFacade {
  GroupFacade(this._groups, this._storage, [this.repo, this.db]);

  final GroupChatRepository _groups;
  final StorageService _storage;

  /// Needed for "Extract Characters" (library copies via duplicateCharacter) —
  /// null until the CharacterRepository is injected.
  final CharacterRepository? repo;

  /// Needed for the Group Card export (objectives snapshot via GroupCardExporter)
  /// — null only in auth-only boots where no DB is wired.
  final AppDatabase? db;

  /// All group chats with their members (id, name, avatar flag) so the library
  /// can render a tile with stacked member avatars.
  Future<List<Map<String, dynamic>>> list() async {
    final result = <Map<String, dynamic>>[];
    for (final g in _groups.groups) {
      final members = await _groups.getMembersForGroup(g.id);
      result.add({
        'id': g.id,
        'name': g.name,
        'memberCount': members.length,
        'members': members
            .map(
              (m) => {
                'id': m.id,
                'name': m.name,
                'hasAvatar':
                    m.avatarFilename != null && m.avatarFilename!.isNotEmpty,
              },
            )
            .toList(),
      });
    }
    return result;
  }

  /// Create a new group from library character ids (their dbIds) + a name + a
  /// turn order. Mirrors the desktop create_group_chat_page persist path: each
  /// source character is duplicated into the group's private avatars dir and a
  /// typed GroupMember row (with provenance), then the GroupChat is saved.
  /// Realism / needs / per-member prompts default off — those are configured
  /// after creation via the existing group settings. Returns {id, name} or null.
  Future<Map<String, dynamic>?> createGroup(Map<String, dynamic> body) async {
    final r = repo;
    final database = db;
    if (r == null || database == null) return null;

    final name = body['name']?.toString().trim() ?? '';
    final ids = body['memberIds'] is List
        ? (body['memberIds'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    if (name.isEmpty || ids.length < 2) return null;

    // Resolve ids → source library cards (preserve order, drop dupes/unknowns).
    final sources = <CharacterCard>[];
    for (final id in ids) {
      for (final c in r.characters) {
        if (c.dbId == id && !sources.any((s) => s.dbId == c.dbId)) {
          sources.add(c);
          break;
        }
      }
    }
    if (sources.length < 2) return null;

    final turnOrder = body['turnOrder']?.toString() == 'random'
        ? TurnOrder.random
        : TurnOrder.roundRobin;

    final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final avDir = Directory(p.join(_storage.groupsDir.path, groupId, 'avatars'));
    await avDir.create(recursive: true);

    for (final source in sources) {
      final mid = const Uuid().v4();
      await r.duplicateCharacter(
        source,
        targetDirOverride: avDir.path,
        forcedBasename: mid,
        skipLibraryInsert: true,
      );
      await database.insertGroupMember(
        GroupMembersCompanion(
          id: Value(mid),
          groupId: Value(groupId),
          name: Value(source.name),
          description: Value(source.description),
          personality: Value(source.personality),
          scenario: Value(source.scenario),
          firstMessage: Value(source.firstMessage),
          mesExample: Value(source.mesExample),
          systemPrompt: Value(source.systemPrompt),
          postHistoryInstructions: Value(source.postHistoryInstructions),
          alternateGreetings: Value(jsonEncode(source.alternateGreetings)),
          tags: Value(jsonEncode(source.tags)),
          avatarFilename: Value('$mid.png'),
          ttsVoice: Value(source.ttsVoice),
          lorebook: Value(
            source.lorebook != null ? jsonEncode(source.lorebook!.toJson()) : null,
          ),
          worldNames: Value(jsonEncode(source.worldNames)),
          frontPorchExtensions: Value(
            source.frontPorchExtensions != null
                ? jsonEncode(source.frontPorchExtensions!.toJson())
                : null,
          ),
          rawExtensions: Value(
            source.rawExtensions != null ? jsonEncode(source.rawExtensions!) : null,
          ),
          memberState: Value(
            GroupMember.encodeProvenance(
              originStableId: source.stableGroupId,
              originLibraryDbId: source.dbId,
            ),
          ),
        ),
      );
    }

    await _groups.save(GroupChat(id: groupId, name: name, turnOrder: turnOrder));
    return {'id': groupId, 'name': name};
  }

  /// Delete a group chat (and its members + sessions), reusing the desktop
  /// delete path. Returns false if the group isn't found.
  Future<bool> delete(String groupId) async {
    if (_groups.getById(groupId) == null) return false;
    await _groups.delete(groupId);
    return true;
  }

  /// Update a group's *settings* (not membership): name, system prompt,
  /// scenario, first message, turn order, and per-member system-prompt
  /// overrides. Settings-only edit via GroupChatRepository.save — distinct from
  /// the removed create wizard. Returns false if the group isn't found.
  Future<bool> updateSettings(String groupId, Map<String, dynamic> f) async {
    final g = _groups.getById(groupId);
    if (g == null) return false;
    if (f['name'] is String) g.name = f['name'] as String;
    if (f['systemPrompt'] is String) {
      g.systemPrompt = f['systemPrompt'] as String;
    }
    if (f['scenario'] is String) g.scenario = f['scenario'] as String;
    if (f['firstMessage'] is String) {
      g.firstMessage = f['firstMessage'] as String;
    }
    if (f['turnOrder'] is String) {
      g.turnOrder = f['turnOrder'] == 'random'
          ? TurnOrder.random
          : TurnOrder.roundRobin;
    }
    final prompts = f['characterSystemPrompts'];
    if (prompts is Map) {
      g.characterSystemPrompts
        ..clear()
        ..addAll(prompts.map((k, v) => MapEntry(k.toString(), v.toString())));
    }
    await _groups.save(g);
    return true;
  }

  /// Export a group as a single self-contained Group Card PNG (the `fpa_group`
  /// format) with full member fidelity. Reuses [GroupCardExporter] (the shared
  /// snapshot logic the desktop also uses) via a temp file, then returns the
  /// bytes. Returns null when the group is unknown/empty or no DB is wired.
  Future<Map<String, dynamic>?> exportGroupCardBytes(String groupId) async {
    final database = db;
    if (database == null) return null;
    final group = _groups.getById(groupId);
    if (group == null) return null;
    final tmp = File(
      p.join(
        Directory.systemTemp.path,
        'fpa_group_export_${DateTime.now().microsecondsSinceEpoch}.png',
      ),
    );
    try {
      final ok = await GroupCardExporter(
        _groups,
        _storage,
        database,
      ).exportToFile(group, tmp.path);
      if (!ok) return null;
      return {'name': group.name, 'bytes': await tmp.readAsBytes()};
    } finally {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {}
    }
  }

  /// Extract every member with a usable private avatar into the library as an
  /// independent character (the desktop "Separate to my library" action), via
  /// [CharacterRepository.duplicateCharacter]. Returns the number extracted, or
  /// null when the group is unknown or no repository is wired.
  Future<int?> extractMembers(String groupId) async {
    final repository = repo;
    if (repository == null) return null;
    if (_groups.getById(groupId) == null) return null;
    final members = await _groups.getMembersForGroup(groupId);
    var extracted = 0;
    for (final m in members) {
      try {
        final resolvedPath = m.avatarFilename != null
            ? p.join(
                _storage.groupsDir.path,
                groupId,
                'avatars',
                m.avatarFilename!,
              )
            : null;
        if (resolvedPath == null || !await File(resolvedPath).exists()) {
          continue;
        }
        final card = m.toCharacterCard(resolvedImagePath: resolvedPath);
        await repository.duplicateCharacter(card);
        extracted++;
      } catch (_) {
        // Best effort — skip a member that fails rather than aborting the batch.
      }
    }
    return extracted;
  }

  /// Resolve a group member's avatar file (stored under
  /// `groupsDir/<groupId>/avatars/<avatarFilename>`), or null if none.
  Future<File?> memberAvatarFile(String groupId, String memberId) async {
    final members = await _groups.getMembersForGroup(groupId);
    final m = members.where((x) => x.id == memberId).firstOrNull;
    final filename = m?.avatarFilename;
    if (filename == null || filename.isEmpty) return null;
    final file = File(
      p.join(_storage.groupsDir.path, groupId, 'avatars', filename),
    );
    return file.existsSync() ? file : null;
  }
}
