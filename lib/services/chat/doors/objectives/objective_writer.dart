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

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart'
    show AppDatabaseMemoryQueries, Objective, ObjectivesCompanion;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';

/// Writes that create, promote or end an objective, and the seeding of a
/// fresh chat from a card's authored task or a group card's goals.
class ObjectiveWriter {
  ObjectiveWriter(this._door, this._d);

  final ObjectivesDoor _door;
  final ObjectiveDeps _d;

  ChatSessionState get _session => _d.session;

  bool _isGroupMember(CharacterCard? card) =>
      card != null &&
      _session.groupCharacters.any(
        (c) => _d.characterIdFor(c) == _d.characterIdFor(card),
      );

  /// Set a new objective for the current session (or for a specific
  /// character when in group mode).
  ///
  /// [autoGenerateTasks] defaults to false. User-created objectives (typed in
  /// the UI) do not auto-generate subtasks: the user is in control of their
  /// own quests and can use the explicit "Generate Tasks" button.
  ///
  /// Autonomous objectives proposed by the character (the realism
  /// "proposed_objective" evals) pass true, so the character's own goals
  /// come with concrete sequential tasks. The evals also claim the
  /// main-quest slot (isPrimary: true) when the character has no primary
  /// yet, so an autonomous goal becomes a real overarching quest.
  ///
  /// [servedAmbition] (v46) is the ambition this quest is a step toward;
  /// only the autonomous proposal paths pass it. [origin] (v58) is who the
  /// goal is from: the user by default; the narrative judge passes
  /// character, the card import card.
  Future<void> setObjective(
    String goal, {
    bool isPrimary = true,
    CharacterCard? targetCharacter,
    bool autoGenerateTasks = false,
    bool recordTurnOps = false,
    String? servedAmbition,
    String origin = kObjectiveOriginUser,
  }) async {
    if (goal.trim().isEmpty) return;
    if (_session.currentSessionId == null) return;

    CharacterCard? target = targetCharacter;
    if (target == null) {
      if (_session.activeGroup != null) {
        // During per-speaker group realism evals (which propose autonomous
        // objectives) the active character is temporarily impersonated to
        // the evaluated speaker. Prefer it so the character's own internal
        // goal attaches to *them*, not the next speaker.
        if (_isGroupMember(_session.activeCharacter)) {
          target = _session.activeCharacter;
        } else {
          target =
              _d.hooks.nextSpeaker() ?? _session.groupCharacters.firstOrNull;
        }
      } else {
        target = _session.activeCharacter;
      }
    }
    if (target == null) return;

    final charId = _d.characterIdFor(target);
    final ops = _door.turnOps;

    if (isPrimary) {
      final existing = await _d.db.getObjectivesForCharacter(
        charId,
        chatId: _session.currentSessionId,
      );
      for (final obj in existing) {
        if (obj.active && obj.isPrimary) {
          await _d.db.updateObjective(
            ObjectivesCompanion(
              id: drift.Value(obj.id),
              isPrimary: const drift.Value(false),
            ),
          );
          if (recordTurnOps) {
            // charId enables the invert's primary-reconciliation guard.
            ops.record({'op': 'demoted', 'id': obj.id, 'charId': charId});
          }
        }
      }
    } else {
      final currentSecondaries = _door.secondaryObjectives;
      final cap = _d.maxSecondaryObjectives;
      if (currentSecondaries.length >= cap) {
        // Oldest first (createdAt asc). Drop enough to leave room for the
        // new one. Today insert does not use this door.
        final drop = currentSecondaries.length - (cap - 1);
        for (var i = 0; i < drop; i++) {
          await _d.db.updateObjective(
            ObjectivesCompanion(
              id: drift.Value(currentSecondaries[i].id),
              active: const drift.Value(false),
            ),
          );
          if (recordTurnOps) {
            ops.record({'op': 'evicted', 'id': currentSecondaries[i].id});
          }
        }
      }
    }

    final newId = const Uuid().v4();
    await _d.db.insertObjective(
      ObjectivesCompanion.insert(
        id: newId,
        characterId: charId,
        objective: goal.trim(),
        chatId: drift.Value(_session.currentSessionId),
        active: const drift.Value(true),
        isPrimary: drift.Value(isPrimary),
        servedAmbition: drift.Value(servedAmbition),
        origin: drift.Value(origin),
      ),
    );
    if (recordTurnOps) {
      // origin + primary let the side-quest cooldown read the turn ops.
      ops.record({
        'op': 'created',
        'id': newId,
        'charId': charId,
        'origin': origin,
        'primary': isPrimary,
      });
    }

    await _door.loadActiveObjectives();
    _door.messagesSinceLastCheck = 0;

    if (autoGenerateTasks) {
      try {
        final forChar = await _door.getActiveObjectivesFor(target);
        final matches = forChar.where((o) => o.id == newId);
        final addedObj = matches.isNotEmpty ? matches.first : null;
        if (addedObj != null) {
          unawaited(
            _door.tasks.generate(
              addedObj,
              // A main quest gets a full arc; a side quest stays a short beat.
              taskCount: isPrimary ? 5 : 3,
              nsfw: false,
            ),
          );
        }
      } catch (_) {
        // Objective created successfully; task generation is best-effort and
        // non-fatal. User can always tap "Generate Tasks" manually.
      }
    }
  }

  /// Planner today line: one secondary, no tasks, no ambition, no eviction.
  Future<String?> insertTodaySideQuest(String goal, {String? id}) async {
    if (goal.trim().isEmpty || _session.currentSessionId == null) return null;
    CharacterCard? target;
    if (_session.activeGroup != null) {
      // The line comes from the reply just written, so it is that
      // speaker's. Director turns run without the speaker stand-in, and by
      // then the turn order already names the next member.
      final replyId = _session.messages.reversed
          .where((m) => !m.isUser && m.sender != 'System')
          .firstOrNull
          ?.characterId;
      final groupCharacters = _session.groupCharacters;
      target =
          groupCharacters
              .where((c) => _d.characterIdFor(c) == replyId)
              .firstOrNull ??
          (_isGroupMember(_session.activeCharacter)
              ? _session.activeCharacter
              : (_d.hooks.nextSpeaker() ?? groupCharacters.firstOrNull));
    } else {
      target = _session.activeCharacter;
    }
    if (target == null) return null;
    final newId = id ?? const Uuid().v4();
    await _d.db.insertObjective(
      ObjectivesCompanion.insert(
        id: newId,
        characterId: _d.characterIdFor(target),
        objective: goal.trim(),
        chatId: drift.Value(_session.currentSessionId),
        active: const drift.Value(true),
        isPrimary: const drift.Value(false),
        servedAmbition: const drift.Value(null),
        origin: const drift.Value(kObjectiveOriginPlanner),
      ),
    );
    if (_door.inObjectiveTurn) {
      _door.turnOps.record({'op': 'created', 'id': newId});
    }
    await _d.hooks.holdToday(newId);
    await _door.loadActiveObjectives();
    return newId;
  }

  /// Promote a side quest to the primary quest IN PLACE, demoting any
  /// current primary to a side quest. Unlike [setObjective] with the same
  /// text (the old promote pattern), this keeps the objective's id and its
  /// generated task progress, and leaves no duplicate side quest behind.
  Future<void> promote(Objective obj) async {
    if (_session.currentSessionId == null) return;
    final existing = await _d.db.getObjectivesForCharacter(
      obj.characterId,
      chatId: _session.currentSessionId,
    );
    for (final o in existing) {
      if (o.active && o.isPrimary && o.id != obj.id) {
        await _d.db.updateObjective(
          ObjectivesCompanion(
            id: drift.Value(o.id),
            isPrimary: const drift.Value(false),
          ),
        );
      }
    }
    await _d.db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        isPrimary: const drift.Value(true),
      ),
    );
    await _d.hooks.releaseToday(obj.id);
    await _door.loadActiveObjectives();
  }

  /// Clear the active objective.
  Future<void> clear(Objective obj) async {
    await _d.db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        active: const drift.Value(false),
      ),
    );
    await _door.loadActiveObjectives();
    _door.messagesSinceLastCheck = 0;
  }

  /// Import a card's authored "Current Task / Quest" as that character's
  /// primary objective.
  ///
  /// The authoring box was retired from every editor (Ambitions replaced it,
  /// and a per-chat quest belongs in the sidebar's Objectives panel). The
  /// FIELD is still read, so a quest an author typed before the swap still
  /// arrives, quietly, in the one place quests now live.
  ///
  /// Shared by every fresh-chat entry point; group entry once never seeded
  /// at all, so a member card's task was dropped on the floor.
  ///
  /// Deferred to a microtask: the session row must exist before the
  /// objective write. [target] pins a group member's task to THEM rather
  /// than to whoever speaks first; 1:1 leaves it null and [setObjective]
  /// resolves the active character. Not gated on objectivesActive: this is a
  /// data-preservation write, and an objective costs nothing while off.
  void importAuthoredTask(FrontPorchExtensions? ext, {CharacterCard? target}) {
    final task = ext?.currentTask.trim() ?? '';
    if (task.isEmpty) return;
    Future.microtask(() async {
      // Not twice: a chat that already has this goal open keeps the one it
      // has (the library had one chat holding five copies of the same task).
      final who = target ?? _session.activeCharacter;
      if (who != null) {
        final open = await _door.getActiveObjectivesFor(who);
        final same = task.toLowerCase();
        if (open.any((o) => o.objective.trim().toLowerCase() == same)) return;
      }
      await setObjective(
        task,
        isPrimary: true,
        targetCharacter: target,
        origin: kObjectiveOriginCard,
      );
      debugPrint(
        '[Objective] Imported authored task'
        '${target != null ? ' for ${target.name}' : ''}: $task',
      );
    });
  }

  /// One-time seeding of objectives carried in an imported Group Card,
  /// called after group state is loaded for a freshly imported group.
  Future<void> seedImportedMemberObjectivesIfPresent() async {
    if (_session.activeGroup == null || _session.currentSessionId == null) {
      return;
    }

    try {
      final stateJson = _session.activeGroup!.defaultMemberRealismState;
      if (stateJson.isEmpty || stateJson == '{}') return;

      final map = jsonDecode(stateJson);
      if (map is! Map) return;

      final importedObj = map['imported_member_objectives'];
      if (importedObj is! Map) return;

      for (final entry in importedObj.entries) {
        final charId = entry.key.toString();
        final list = entry.value as List? ?? [];
        for (final objData in list) {
          final objMap = objData as Map<String, dynamic>? ?? {};
          // Uuid, like every other objective write. The old id was built
          // inside this loop from the outer key, so two objectives for the
          // same member written in the same millisecond collided on the
          // primary key and every remaining member's quests were dropped.
          await _d.db.insertObjective(
            ObjectivesCompanion.insert(
              id: const Uuid().v4(),
              characterId: charId,
              chatId: drift.Value(_session.currentSessionId!),
              objective:
                  objMap['objective']?.toString() ?? 'Imported objective',
              tasks: drift.Value(objMap['tasks']?.toString() ?? '[]'),
              active: const drift.Value(true),
              isPrimary: drift.Value(objMap['isPrimary'] == true),
              checkFrequency: drift.Value(
                (objMap['checkFrequency'] as num?)?.toInt() ?? 3,
              ),
              injectionDepth: drift.Value(
                (objMap['injectionDepth'] as num?)?.toInt() ?? 4,
              ),
              // A group card's goals were authored with the card.
              origin: drift.Value(
                objMap['origin'] as String? ?? kObjectiveOriginCard,
              ),
            ),
          );
        }
      }

      // Remove the marker so it doesn't seed again. The marker lives on the
      // GROUP row and saveChat only upserts the session, so save the group
      // too, or every re-entry seeds the same quests all over again.
      map.remove('imported_member_objectives');
      _session.activeGroup!.defaultMemberRealismState = jsonEncode(map);
      await _d.hooks.groupRepository()?.save(_session.activeGroup!);
      await _d.saveChat();
    } catch (e) {
      debugPrint('[Objective] Imported member objectives seed failed: $e');
    }
  }
}
