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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'entry_door.dart';

/// One-time, idempotent re-key of group stores from a legacy name/
/// stableGroupId onto [groupMemberStoreId] (UUID when the member has one).
/// The session store runs it after each group blob load.
class GroupStoreMigrate {
  GroupStoreMigrate(this._door, this._d);

  final EntryDoor _door;
  final EntryDeps _d;

  ChatSessionState get _session => _d.session;
  EntryServices get _s => _d.services;
  GroupSessionConfig get _group => _d.sessions().groupConfig;
  GroupRealismStore get _groupStore => _s.realism().groups;
  AppDatabase get _db => _s.db();
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  GrowthDesk get _growthDesk => _s.growthDesk();

  /// Move live maps + definition blobs. Persist the group row when
  /// definition keys moved. Returns true when a session-scoped map moved
  /// (caller persists the session once).
  Future<bool> rekeyGroupStores() async {
    if (_activeGroup == null) return false;
    final members = _groupCharacters;
    if (members.isEmpty) return false;

    var sessionChanged = false;
    sessionChanged |= migrateGroupStoreKeys(_groupStore.members, members);
    sessionChanged |= migrateGroupStoreKeys(_group.authorNotes, members);
    sessionChanged |= migrateGroupStoreKeys(
      _group.authorNoteStrengths,
      members,
    );
    sessionChanged |= migrateGroupStoreKeys(
      _group.characterSystemPrompts,
      members,
    );
    sessionChanged |= migrateGroupStoreKeys(
      _group.characterRAGPriorities,
      members,
    );
    sessionChanged |= migrateGroupStoreKeys(
      _s.objectives().groupObjectives,
      members,
    );
    sessionChanged |= _rekeyGroupMemberRelationships(members);

    if (_rekeyGroupDefinitionBlobs(members)) {
      final group = _activeGroup;
      final repo = _door.groupRepository;
      if (group != null && repo != null) {
        unawaited(() async {
          try {
            await repo.save(group);
          } catch (e) {
            debugPrint('[GroupStore] Failed to persist rekeyed group: $e');
          }
        }());
      }
    }
    await _rekeyGroupObjectiveRows(members);
    await _rekeyGroupMemoryRows(members);
    await _hydrateGroupObjectivesFromDb(members);
    return sessionChanged;
  }

  /// Session-scoped journal / growth / embeddings. Other chats that
  /// still key a same-name member stay put. Safe to repeat.
  Future<void> _rekeyGroupMemoryRows(Iterable<CharacterCard> members) async {
    final sid = _session.currentSessionId;
    if (sid == null) return;
    var moved = false;
    try {
      for (final member in members) {
        final dest = groupMemberStoreId(member);
        final fromIds = <String>{member.stableGroupId};
        // Avatar-less members were also keyed by display name
        // (embeddings especially). Re-key those rows too.
        final path = member.imagePath;
        if (path == null || path.isEmpty) {
          fromIds.add(member.name);
          fromIds.add(stableGroupIdFrom(null, member.name));
        }
        for (final legacy in fromIds) {
          if (dest == legacy || legacy.isEmpty) continue;
          await _db.rekeySessionMemoryCharacterId(legacy, dest, sessionId: sid);
          moved = true;
        }
      }
    } catch (e) {
      debugPrint('[GroupStore] Failed to rekey journal/growth rows: $e');
    }
    if (moved) await _growthDesk.refreshCache();
  }

  /// Fill the existing [ObjectivesDoor.groupObjectives] map from DB after rekey.
  /// Session-scoped rows and card-level (`chat_id IS NULL`) rows.
  Future<void> _hydrateGroupObjectivesFromDb(
    Iterable<CharacterCard> members,
  ) async {
    final sid = _session.currentSessionId;
    try {
      for (final member in members) {
        final id = groupMemberStoreId(member);
        final sessionRows = sid != null
            ? await _db.getObjectivesForCharacter(id, chatId: sid)
            : const <Objective>[];
        final cardRows = await _db.getObjectivesForCharacter(id);
        _s.objectives().groupObjectives[id] = [...sessionRows, ...cardRows];
      }
    } catch (e) {
      debugPrint('[GroupStore] Failed to hydrate objectives: $e');
    }
  }

  /// Session-scoped rows always move. Card-level rows move only when
  /// no library character already owns that legacy key.
  Future<void> _rekeyGroupObjectiveRows(Iterable<CharacterCard> members) async {
    final sid = _session.currentSessionId;
    try {
      for (final member in members) {
        final dest = groupMemberStoreId(member);
        final legacy = member.stableGroupId;
        if (dest == legacy) continue;
        if (sid != null) {
          await _db.rekeyObjectiveCharacterId(legacy, dest, chatId: sid);
        }
        final clash =
            _s.characters()?.characters.any(
              (c) => c.stableGroupId == legacy && c.dbId != member.dbId,
            ) ??
            false;
        if (!clash) {
          await _db.rekeyObjectiveCharacterId(legacy, dest);
        }
      }
    } catch (e) {
      debugPrint('[GroupStore] Failed to rekey objective rows: $e');
    }
  }

  bool _rekeyGroupMemberRelationships(Iterable<CharacterCard> members) {
    final idMap = groupMemberLegacyIdMap(members);
    if (idMap.isEmpty) return false;
    var changed = false;
    for (final state in _groupStore.members.values) {
      final rels = state.relationships;
      if (rels == null || rels.isEmpty) continue;
      if (!rels.keys.any(idMap.containsKey)) continue;
      state.relationships = {
        for (final e in rels.entries) idMap[e.key] ?? e.key: e.value,
      };
      changed = true;
    }
    return changed;
  }

  bool _rekeyGroupDefinitionBlobs(Iterable<CharacterCard> members) {
    final group = _activeGroup;
    if (group == null) return false;
    var changed = false;

    Map<String, dynamic> decode(String raw) {
      if (raw.isEmpty || raw == '{}') return {};
      try {
        final decoded = jsonDecode(raw);
        return decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      } catch (_) {
        return {};
      }
    }

    final defaults = decode(group.defaultMemberRealismState);
    if (defaults.isNotEmpty && migrateGroupRealismBlobKeys(defaults, members)) {
      group.defaultMemberRealismState = jsonEncode(defaults);
      changed = true;
    }

    final baseline = decode(group.baselineRealismState);
    if (baseline.isNotEmpty && migrateGroupStoreKeys(baseline, members)) {
      group.baselineRealismState = jsonEncode(baseline);
      changed = true;
    }

    changed |= migrateGroupStoreKeys(group.characterSystemPrompts, members);
    changed |= migrateGroupStoreKeys(group.characterAuthorNotes, members);
    return changed;
  }
}
