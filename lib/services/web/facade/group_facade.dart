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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/group_create_draft.dart';
import 'package:front_porch_ai/services/web/facade/group_draft_opening.dart';
import 'package:front_porch_ai/services/web/facade/group_new_chats.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Read adapter over the group store for the web library — lists group chats,
/// resolves member avatars, and handles library card actions (export Group Card
/// PNG, extract members to the library). Activating a group lives in [ChatFacade]
/// (`selectGroup`) alongside character selection, to keep "what is the active
/// chat" in one place. Reuses GroupChatRepository / GroupCardExporter /
/// CharacterRepository directly; no duplicated logic.
class GroupFacade {
  GroupFacade(
    this._groups,
    this._storage, [
    this.repo,
    this.db,
    this.folders,
    this.worlds,
  ]);

  /// Resolves a group's Setting and lore-only worlds — null in auth-only
  /// boots, where the worlds endpoint answers empty.
  final WorldRepository? worlds;

  /// The web wizard's Generate buttons; null when no model provider is wired.
  GroupDraftOpening? opening;

  /// Group Settings' "New chats" switches and the forked-group notice.
  late final GroupNewChats newChats = GroupNewChats(_groups, db, worlds);

  final GroupChatRepository _groups;
  final StorageService _storage;

  /// Folder membership source so the library list can report each group's
  /// folder (groups folder like characters now) — null in auth-only boots.
  final FolderService? folders;

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
    final unknown = <Future<bool>>[];
    for (final g in _groups.groups) {
      final members = await _groups.getMembersForGroup(g.id);
      result.add({
        'id': g.id,
        'name': g.name,
        // Same ''-at-root convention as the character list's folderId.
        'folderId': folders?.getFolderForGroup(g.id)?.id ?? '',
        'memberCount': members.length,
        'members': members.map((m) {
          final version = _memberAvatarVersion(g.id, m.avatarFilename);
          return {
            'id': m.id,
            'name': m.name,
            'hasAvatar':
                m.avatarFilename != null && m.avatarFilename!.isNotEmpty,
            // The picture is only the flat no-portrait colour: the tile draws
            // the member's initial instead (additive field).
            'placeholderPortrait': _placeholderPortrait(
              g.id,
              m.avatarFilename,
              version,
              unknown,
            ),
            'avatarVersion': version,
          };
        }).toList(),
      });
    }
    if (unknown.isNotEmpty) {
      Future.wait(unknown).then((found) {
        if (found.contains(true)) onPlaceholderPortraitsFound?.call();
      });
    }
    return result;
  }

  /// Called (once per list) when background probes find a no-portrait
  /// placeholder the list did not know about; the web host wires it to the
  /// library's debounced `library_changed` broadcast so browsers refetch.
  void Function()? onPlaceholderPortraitsFound;

  /// Whether a member's picture is the flat placeholder a character made
  /// without a portrait carries. Never blocks the list: answers from the
  /// probe cache, counts an unknown picture as real and adds its probe to
  /// [unknown] to run in the background.
  bool _placeholderPortrait(
    String groupId,
    String? filename,
    int version,
    List<Future<bool>> unknown,
  ) {
    if (filename == null || filename.isEmpty || version == 0) return false;
    final file = File(
      p.join(_storage.groupsDir.path, groupId, 'avatars', filename),
    );
    final known = PlaceholderPortraitProbe.known(file, version: version);
    if (known == null) {
      unknown.add(PlaceholderPortraitProbe.check(file, version: version));
    }
    return known ?? false;
  }

  /// The member avatar file's modified-time (ms), used by the web UI as a
  /// cache-busting version token in the thumbnail URL — see the character
  /// facade's equivalent. 0 when there's no avatar or it can't be stat'd.
  int _memberAvatarVersion(String groupId, String? filename) {
    if (filename == null || filename.isEmpty) return 0;
    try {
      final f = File(
        p.join(_storage.groupsDir.path, groupId, 'avatars', filename),
      );
      return f.existsSync() ? f.statSync().modified.millisecondsSinceEpoch : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Where [groupId]'s new chats meet, for the web picker: the Setting
  /// (a world, or a place inside one), the lore-only worlds, and, for an
  /// unsplit group linking several worlds, how many (the two-roles banner).
  /// Null when the group is unknown.
  Map<String, dynamic>? worldsOf(String groupId) {
    final g = _groups.getById(groupId);
    if (g == null) return null;
    final w = worlds;
    final choice = w == null
        ? const GroupWorldChoice()
        : groupWorldChoiceIn(g, w);
    return {
      'settingId': choice.settingId,
      'loreIds': choice.loreIds,
      'legacyWorldCount': groupNeedsWorldSplitNotice(g) ? g.worldIds.length : 0,
    };
  }

  /// A posted `{settingId, loreIds}` as a choice, keeping only ids the
  /// library knows (a top-level world or a place for the Setting; worlds
  /// for lore). Null when [raw] is not such a map.
  GroupWorldChoice? _choiceFrom(Object? raw) {
    if (raw is! Map) return null;
    final w = worlds;
    bool known(Object? id) => id is String && w?.worldById(id) != null;
    final setting = raw['settingId'];
    final lore = raw['loreIds'];
    return GroupWorldChoice(
      settingId: known(setting) ? setting as String : null,
      loreIds: [
        if (lore is List)
          for (final id in lore)
            if (known(id) && id != setting) id as String,
      ],
    );
  }

  /// Create a new group from library character ids (their dbIds) + a name + a
  /// turn order. Mirrors the desktop create_group_chat_page persist path: each
  /// source character is duplicated into the group's private avatars dir and a
  /// typed GroupMember row (with provenance), then the GroupChat is saved.
  /// The rest of the body is the web wizard's draft (GroupCreateDraft):
  /// Identity switches and member Voices, Opening, Realism with Group
  /// Dynamics, Prompts & Lore.
  /// Without it Realism and Needs start on with every member neutral, as the
  /// desktop creator's defaults do; `worlds` sets where new chats meet.
  /// Returns {id, name} or null.
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
    final avDir = Directory(
      p.join(_storage.groupsDir.path, groupId, 'avatars'),
    );
    await avDir.create(recursive: true);

    final draft = GroupCreateDraft.fromBody(body);
    // Library id → the member's own id, for the draft's per-member fields.
    final idMap = <String, String>{};
    for (final source in sources) {
      final mid = const Uuid().v4();
      idMap[source.dbId!] = mid;
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
          ttsVoice: Value(
            memberVoiceFromPick(draft.memberVoices, source.dbId!, source),
          ),
          lorebook: Value(
            source.lorebook != null
                ? jsonEncode(source.lorebook!.toJson())
                : null,
          ),
          worldNames: Value(jsonEncode(source.allWorldNames)),
          frontPorchExtensions: Value(draft.memberExtensionsJson(source)),
          rawExtensions: Value(
            source.rawExtensions != null
                ? jsonEncode(source.rawExtensions!)
                : null,
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

    final realism = draft.realismBlobs(idMap);
    final where =
        (_choiceFrom(body['worlds']) ?? const GroupWorldChoice()).fields;
    await _groups.save(
      GroupChat(
        id: groupId,
        name: name,
        turnOrder: turnOrder,
        autoAdvance: draft.autoAdvance,
        directorMode: draft.directorMode,
        scenario: draft.scenario,
        firstMessage: draft.firstMessage,
        alternateGreetings: draft.greetings.greetings,
        greetingSeeds: draft.greetings.seeds,
        characterSystemPrompts: draft.promptsFor(idMap),
        groupLorebook: draft.lorebookJson,
        inheritCharacterLorebooks: draft.inheritCharacterLorebooks,
        chaosModeEnabled: draft.chaosModeEnabled,
        chaosNsfwEnabled: draft.chaosNsfwEnabled,
        defaultMemberRealismState: realism?.defaultMemberJson ?? '{}',
        baselineRealismState: realism?.baselineJson ?? '{}',
        worldIds: where.worldIds,
        loreWorldIds: where.loreWorldIds,
      ),
    );
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
    if (f['alternateGreetings'] is List || f.containsKey('greetingSeeds')) {
      // Seeds omitted + alts present: compact against empty/null, not unpaired
      // base leftovers. Same three-way as character update: omitted seeds +
      // alts → empty; omitted alts keep base (this block is not entered);
      // present seeds (including []) pair as posted.
      final paired = compactGreetingPairs(
        f['alternateGreetings'] is List
            ? greetingSlotsFromRaw(f['alternateGreetings'])
            : g.alternateGreetings,
        f.containsKey('greetingSeeds')
            ? parseGreetingSeeds(f['greetingSeeds'])
            : const [],
      );
      if (f['alternateGreetings'] is List) {
        g.alternateGreetings = paired.greetings;
      }
      g.greetingSeeds = paired.seeds;
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
    final chosen = _choiceFrom(f['worlds']);
    final w = worlds;
    if (chosen != null && w != null) {
      // Same rule as the desktop editors: an untouched choice leaves an
      // unsplit group's stored worlds alone.
      final saved = groupWorldFieldsToSave(
        storedWorldIds: g.worldIds,
        storedLoreWorldIds: g.loreWorldIds,
        chosen: chosen,
        asLoaded: groupWorldChoiceIn(g, w),
      );
      g.worldIds = saved.worldIds;
      g.loreWorldIds = saved.loreWorldIds;
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
  /// independent character, in the group's folder (the desktop "Extract
  /// Characters" action, via [GroupMemberExtractor]). Returns the number
  /// extracted, or null when the group is unknown or no repository is wired.
  Future<int?> extractMembers(String groupId) async {
    final repository = repo;
    if (repository == null) return null;
    if (_groups.getById(groupId) == null) return null;
    return GroupMemberExtractor(
      _groups,
      _storage,
      repository,
      folders,
    ).extract(groupId);
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
