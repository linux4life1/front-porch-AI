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

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/today_sentence.dart';
import 'package:front_porch_ai/services/chat/planner_today_fate.dart';

/// The planner's today line as a side quest: the one secondary row it
/// holds, its fate when the day resolves it (done, abandoned, eaten), the
/// mood that fate moves and the Journal card it leaves.
class TodayPlanner {
  TodayPlanner(this._g);

  final RealismGraph _g;

  TodaySentence get _today => _g.deps.doors.sessions().today;
  ObjectivesDoor get _objectives => _g.deps.doors.objectives();
  AppDatabase get _db => _g.deps.services.db();

  /// The planner's today line is the first feature to move the mood through
  /// the one door (docs/design/mood-with-bite.md): a fresh feeling with the
  /// line as its cause, stamped on the reply so regen rewinds it.
  void _nudgeMood(PlannerTodayFate fate, String line) {
    switch (fate) {
      case PlannerTodayFate.done:
        _g.mood.set('content', 'moderate', cause: line);
      case PlannerTodayFate.abandoned:
        _g.mood.set('annoyed', 'moderate', cause: 'let go of: $line');
      case PlannerTodayFate.dayAte:
        _g.mood.set('annoyed', 'moderate', cause: 'the day ran out on: $line');
    }
  }

  Future<void> persistTodayObjectiveId(String? id) async {
    final sid = _g.session.currentSessionId;
    if (sid == null) return;
    await _db.patchSession(
      SessionsCompanion(
        id: drift.Value(sid),
        todayObjectiveId: drift.Value(id),
      ),
    );
  }

  /// The held today row while it is still active, found by id. The loaded
  /// list is checked first; in a group the row sits on the member whose
  /// turn wrote it, which is often not the list on screen, so the chat's
  /// rows are asked next.
  Future<Objective?> _heldTodayRow() async {
    final id = _today.todayObjectiveId;
    final sid = _g.session.currentSessionId;
    if (id == null) return null;
    final listed = _objectives.activeObjectives
        .where((o) => o.id == id)
        .firstOrNull;
    if (listed != null || sid == null) return listed;
    try {
      return await (_db.select(_db.objectives)..where(
            (o) =>
                o.id.equals(id) & o.chatId.equals(sid) & o.active.equals(true),
          ))
          .getSingleOrNull();
    } catch (e) {
      debugPrint('[Planner] Could not read the held today row: $e');
      return null;
    }
  }

  /// Rebind by the persisted session id. Never guess among secondaries.
  Future<void> rebindTodayObjectiveFromDb() async {
    final id = _today.todayObjectiveId;
    if (id == null) return;
    final live = await _heldTodayRow();
    // Not found: keep the pointer so the next upsert/day-ate still sees it.
    if (live == null || _today.todayObjectiveId != id) return;
    _today.todayObjectiveText = live.objective;
    if (_today.todaySentence == null) _today.setTodaySentence(live.objective);
  }

  /// Record where the today line stood before the turn moves it, so the
  /// rewind can hand the sidebar back the line it showed.
  void recordTodayPointerOp() {
    if (!_objectives.inObjectiveTurn) return;
    _objectives.turnOps.record({
      'op': 'today',
      'id': _today.todayObjectiveId,
      'text': _today.todayObjectiveText,
      'sentence': _today.todaySentence,
    });
  }

  /// A rewound `today` turn op: the line the sidebar showed before it.
  Future<void> revertTodayPointer(Map entry) async {
    _today.todayObjectiveId = entry['id'] as String?;
    _today.todayObjectiveText = entry['text'] as String?;
    _today.setTodaySentence(entry['sentence'] as String?);
    await persistTodayObjectiveId(_today.todayObjectiveId);
  }

  /// A promoted quest stops being the today line.
  Future<void> releaseHeldToday(String objectiveId) async {
    if (_today.todayObjectiveId != objectiveId) return;
    _today.todayObjectiveId = null;
    _today.todayObjectiveText = null;
    _today.setTodaySentence(null);
    await persistTodayObjectiveId(null);
  }

  bool isHeldTodayObjective(Objective obj) {
    return _today.todayObjectiveId != null && obj.id == _today.todayObjectiveId;
  }

  Future<void> deactivateTodayObjective() async {
    final id = _today.todayObjectiveId;
    if (id == null) return;
    // Before the first await: the turn window may close behind it.
    if (_objectives.inObjectiveTurn) {
      _objectives.turnOps.record({'op': 'deactivated', 'id': id});
    }
    _today.todayObjectiveId = null;
    _today.todayObjectiveText = null;
    await persistTodayObjectiveId(null);
    // Update by id even when the row is on another member's list —
    // day-ate after a speaker switch must still retire Ada's row.
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(id),
        active: const drift.Value(false),
      ),
    );
    await _objectives.loadActiveObjectives();
  }

  /// One secondary today-row. Match/replace by held id. Never primary,
  /// never tasks, never an ambition, never evicts other secondaries.
  Future<void> upsertTodayObjective(String line) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty || _g.session.currentSessionId == null) return;
    final heldId = _today.todayObjectiveId;
    if (heldId != null) {
      final held = await _heldTodayRow();
      if (held != null && held.objective == trimmed) {
        _today.todayObjectiveText = trimmed;
        await persistTodayObjectiveId(heldId);
        return;
      }
      if (held != null) {
        await deactivateTodayObjective();
      } else {
        // The held row is gone (the user cleared the quest, or a rewind
        // took it). Drop the pointer and write the line again, even when
        // the sentence matches: _heldTodayRow already asked the database.
        _today.todayObjectiveId = null;
        _today.todayObjectiveText = null;
        await persistTodayObjectiveId(null);
      }
    }
    final newId = const Uuid().v4();
    _today.todayObjectiveId = newId;
    _today.todayObjectiveText = trimmed;
    final inserted = await _objectives.writer.insertTodaySideQuest(
      trimmed,
      id: newId,
    );
    if (inserted == null) {
      _today.todayObjectiveId = null;
      _today.todayObjectiveText = null;
      await persistTodayObjectiveId(null);
    }
  }

  Future<void> onTodayObjectiveCompleted(Objective obj) async {
    if (!isHeldTodayObjective(obj)) return;
    final held = _today.todaySentence ?? obj.objective;
    recordTodayPointerOp();
    _today.todayObjectiveId = null;
    _today.todayObjectiveText = null;
    _today.setTodaySentence(null);
    unawaited(() async {
      await journalResolvedToday(
        held,
        fate: PlannerTodayFate.done,
        ownerId: obj.characterId,
      );
      await persistTodayObjectiveId(null);
    }());
  }

  /// Journal a finished or day-eaten line. Capture [held] before clearing.
  /// Abandoned lines sour mood and do not write a card. The card is the
  /// today row's owner's ([ownerId], else the held row's member): in a
  /// group that is the member whose reply wrote the line, not the speaker.
  Future<void> journalResolvedToday(
    String? held, {
    required PlannerTodayFate fate,
    String? ownerId,
  }) async {
    final line = held?.trim();
    if (line == null || line.isEmpty) return;
    final storage = _g.deps.services.storage;
    if (!storage.realismSettings.plannerEnabled) return;
    // Taken now, while the turn that resolved the line is still running.
    final cite = _objectives.turnOps.cite();
    _nudgeMood(fate, line);
    if (fate == PlannerTodayFate.abandoned) return;
    final sessionId = _g.session.currentSessionId;
    final card = _g.session.activeCharacter;
    final mood = _g.registers.emotion;
    final owner =
        ownerId ??
        (await _heldTodayRow())?.characterId ??
        (card == null ? null : _g.session.characterIdFor(card));
    if (sessionId == null || owner == null) return;
    await _g.journalStore.addCard(
      sessionId: sessionId,
      characterId: owner,
      content: line,
      category: 'moment',
      kind: 'today',
      sourcePositions: cite,
      storyDay: _g.time.dayCount,
      storyClock: _g.time.storyClockIso,
      emotionLabel: mood.isEmpty ? null : mood,
      maxCards: storage.memorySettings.journalMaxCards,
    );
  }
}
