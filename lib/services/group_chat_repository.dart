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
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Persists group chat definitions to the database.
class GroupChatRepository extends ChangeNotifier {
  final StorageService _storageService;
  AppDatabase _db;
  final List<GroupChat> _groups = [];

  List<GroupChat> get groups => List.unmodifiable(_groups);

  GroupChatRepository(this._storageService, this._db) {
    _load();
  }

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  Future<void> _load() async {
    await _storageService.initialized;
    _groups.clear();

    try {
      final dbGroups = await _db.getAllGroups();
      for (final g in dbGroups) {
        // characterIds column is legacy dead weight (clean break decoupling).
        // We never read it; membership is sourced exclusively from group_members table.
        // Always write '[]' on save to satisfy the NOT NULL column without migration.

        // characterSystemPrompts is now stored in its own first-class column (v32).
        // Full deprecation of the previous Path B blob hack inside defaultMemberRealismState.
        Map<String, String> charPrompts = {};
        try {
          final decoded = jsonDecode(g.characterSystemPrompts);
          if (decoded is Map) {
            charPrompts = decoded.map(
              (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
            );
          }
        } catch (_) {}

        // Parse worldIds (JSON array) — safe default to empty list on any decode error.
        List<String> worldIdList = [];
        try {
          final decodedWorlds = jsonDecode(g.worldIds);
          if (decodedWorlds is List) {
            worldIdList = decodedWorlds.map((e) => e.toString()).toList();
          }
        } catch (_) {}

        // Construct GroupChat using *real column values* from the v31 schema additions.
        // Old groups receive the DB column defaults (false, '', '[]', true, '{}') which
        // preserve previous behavior and require no one-time promotion logic here.
        _groups.add(
          GroupChat(
            id: g.id,
            stableId: g.stableId,
            name: g.name,
            turnOrder: TurnOrder.values.firstWhere(
              (e) => e.name == g.turnOrder,
              orElse: () => TurnOrder.roundRobin,
            ),
            autoAdvance: g.autoAdvance,
            directorMode: g.directorMode,
            firstMessage: g.firstMessage,
            alternateGreetings: parseGroupAlternateGreetings(
              g.defaultMemberRealismState,
            ),
            greetingSeeds: parseGroupGreetingSeeds(g.defaultMemberRealismState),
            scenario: g.scenario,
            systemPrompt: g.systemPrompt,
            defaultMemberRealismState: g.defaultMemberRealismState,
            characterSystemPrompts: charPrompts,
            // v31 first-class columns (read directly; no longer silently defaulting):
            chaosModeEnabled: g.chaosModeEnabled,
            chaosNsfwEnabled: g.chaosNsfwEnabled,
            groupLorebook: g.groupLorebook,
            worldIds: worldIdList,
            inheritCharacterLorebooks: g.inheritCharacterLorebooks,
            baselineRealismState: g.baselineRealismState,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to load groups from DB: $e');
    }

    notifyListeners();
  }

  /// Reload groups from DB (e.g. after cloud sync).
  Future<void> reload() async {
    await _load();
  }

  Future<void> save(GroupChat group) async {
    // Save to database
    final existing = await _db.getGroupById(group.id);

    // characterSystemPrompts is now persisted in its own dedicated column (v32).
    // Full removal of the previous Path B transitional blob logic that merged it
    // into defaultMemberRealismState. defaultMemberRealismState is written as-is.
    // characterIds is legacy dead weight (always '[]' — membership is in group_members).
    final patchedBlob = withGroupOpeningAlts(
      group.defaultMemberRealismState,
      alternateGreetings: group.alternateGreetings,
      greetingSeeds: group.greetingSeeds,
    );
    // Same-session export / cache reads must see the patched alts/seeds.
    group.defaultMemberRealismState = patchedBlob;
    group.alternateGreetings = parseGroupAlternateGreetings(patchedBlob);
    group.greetingSeeds = parseGroupGreetingSeeds(patchedBlob);
    final companion = GroupsCompanion(
      id: Value(group.id),
      stableId: Value(group.stableId),
      name: Value(group.name),
      characterIds: const Value('[]'),
      turnOrder: Value(group.turnOrder.name),
      autoAdvance: Value(group.autoAdvance),
      directorMode: Value(group.directorMode),
      firstMessage: Value(group.firstMessage),
      scenario: Value(group.scenario),
      systemPrompt: Value(group.systemPrompt),
      defaultMemberRealismState: Value(patchedBlob),
      characterSystemPrompts: Value(jsonEncode(group.characterSystemPrompts)),
      chaosModeEnabled: Value(group.chaosModeEnabled),
      chaosNsfwEnabled: Value(group.chaosNsfwEnabled),
      groupLorebook: Value(group.groupLorebook),
      worldIds: Value(jsonEncode(group.worldIds)),
      inheritCharacterLorebooks: Value(group.inheritCharacterLorebooks),
      baselineRealismState: Value(group.baselineRealismState),
      // updateGroup now uses partial .write() (so folder_id survives saves);
      // bump updatedAt explicitly since the column default no longer applies.
      updatedAt: Value(DateTime.now()),
    );

    if (existing != null) {
      await _db.updateGroup(companion);
    } else {
      await _db.insertGroup(
        GroupsCompanion.insert(
          id: group.id,
          stableId: Value(group.stableId),
          name: group.name,
          characterIds: const Value(
            '[]',
          ), // legacy dead column (decoupled members in group_members)
          turnOrder: Value(group.turnOrder.name),
          autoAdvance: Value(group.autoAdvance),
          directorMode: Value(group.directorMode),
          firstMessage: Value(group.firstMessage),
          scenario: Value(group.scenario),
          systemPrompt: Value(group.systemPrompt),
          defaultMemberRealismState: Value(patchedBlob),
          characterSystemPrompts: Value(
            jsonEncode(group.characterSystemPrompts),
          ),
          chaosModeEnabled: Value(group.chaosModeEnabled),
          chaosNsfwEnabled: Value(group.chaosNsfwEnabled),
          groupLorebook: Value(group.groupLorebook),
          worldIds: Value(jsonEncode(group.worldIds)),
          inheritCharacterLorebooks: Value(group.inheritCharacterLorebooks),
          baselineRealismState: Value(group.baselineRealismState),
        ),
      );
    }

    // Replace in the in-memory list so subsequent reads see the saved state.
    // We replace the whole object (the caller owns the instance we were given).
    final idx = _groups.indexWhere((g) => g.id == group.id);
    if (idx >= 0) {
      _groups[idx] = group;
    } else {
      _groups.add(group);
    }
    notifyListeners();
  }

  /// Guarantee this group has a portable, device-independent [GroupChat.stableId]
  /// (used to update a shared group in place on The Stoop instead of duplicating
  /// it, and to re-associate it after switching devices). Generates + persists
  /// one on the first call for a group that lacks it; a no-op afterwards.
  /// Returns the id. Mutates the passed [group] so callers see it immediately.
  Future<String> ensureStableId(GroupChat group) async {
    final existing = group.stableId?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    group.stableId = id;
    await save(group);
    return id;
  }

  Future<void> delete(String groupId) async {
    // Delete from database
    await _db.deleteGroupById(groupId);
    _groups.removeWhere((g) => g.id == groupId);

    // Delete associated chat sessions from database
    final sessions = await _db.getSessionsForGroup(groupId);
    for (final session in sessions) {
      await _db.deleteMessagesForSession(session.id);
      await _db.deleteSessionById(session.id);
    }

    // Best-effort recursive delete of private group avatar tree (groups/<id>/).
    // DB rows (including group_members) already cascaded in _db.deleteGroupById.
    // Orphans prevented per plan + security review.
    // (No groupDir helper added per strict "no new methods" rule; inline safe construction.)
    try {
      final gDir = Directory(
        path.join(_storageService.groupsDir.path, groupId),
      );
      if (await gDir.exists()) {
        await gDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint(
        '[GroupRepo] Best-effort delete of private group dir $groupId failed (non-fatal): $e',
      );
    }

    notifyListeners();
  }

  GroupChat? getById(String id) {
    return _groups.where((g) => g.id == id).firstOrNull;
  }

  /// Returns the fully decoupled group members for the given group.
  /// Source of truth is the group_members table (private to the group).
  /// Callers must use the returned GroupMember list (or reconstruct transient
  /// CharacterCard via member.toCharacterCard(resolvedPath) where widgets require it).
  Future<List<GroupMember>> getMembersForGroup(String groupId) async {
    await _storageService.initialized;
    try {
      final rows = await _db.getGroupMembers(groupId);
      return rows.map(GroupMember.fromRow).toList();
    } catch (e) {
      debugPrint('Failed to load group members for $groupId: $e');
      return [];
    }
  }

  /// Resolves the on-disk avatar [File]s for a group's members, in member
  /// order. Members without an avatar are skipped. Paths are absolute (under
  /// the group's private avatars dir). Shared by the home grid's group card and
  /// the Stoop share picker so both preview a group from the same source.
  Future<List<File>> getMemberAvatarFiles(String groupId) async {
    final rows = await getMembersForGroup(groupId);
    final files = <File>[];
    for (final m in rows) {
      if (m.avatarFilename == null) continue;
      files.add(
        File(
          path.join(
            _storageService.groupsDir.path,
            groupId,
            'avatars',
            m.avatarFilename!,
          ),
        ),
      );
    }
    return files;
  }
}
