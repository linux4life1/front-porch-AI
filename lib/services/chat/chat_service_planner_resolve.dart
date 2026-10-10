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

part of '../chat_service.dart';

enum PlannerTodayFate { done, abandoned, dayAte }

extension ChatServicePlannerResolve on ChatService {
  void _nudgePlannerMood(PlannerTodayFate fate) {
    _characterEmotion = switch (fate) {
      PlannerTodayFate.done => 'content',
      PlannerTodayFate.abandoned || PlannerTodayFate.dayAte => 'annoyed',
    };
  }

  Future<void> _persistTodayObjectiveId(String? id) async {
    final sid = _currentSessionId;
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
    final id = _todayObjectiveId;
    final sid = _currentSessionId;
    if (id == null) return null;
    final listed = _activeObjectives.where((o) => o.id == id).firstOrNull;
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
  Future<void> _rebindTodayObjectiveFromDb() async {
    final id = _todayObjectiveId;
    if (id == null) return;
    final live = await _heldTodayRow();
    // Not found: keep the pointer so the next upsert/day-ate still sees it.
    if (live == null || _todayObjectiveId != id) return;
    _todayObjectiveText = live.objective;
    if (_todaySentence == null) setTodaySentence(live.objective);
  }

  bool _isHeldTodayObjective(Objective obj) {
    return _todayObjectiveId != null && obj.id == _todayObjectiveId;
  }

  Future<void> _deactivateTodayObjective() async {
    final id = _todayObjectiveId;
    if (id == null) return;
    // Before the first await: the turn window may close behind it.
    if (_inObjectiveTurn) {
      _recordObjectiveTurnOp({'op': 'deactivated', 'id': id});
    }
    _todayObjectiveId = null;
    _todayObjectiveText = null;
    await _persistTodayObjectiveId(null);
    // Update by id even when the row is on another member's list —
    // day-ate after a speaker switch must still retire Ada's row.
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(id),
        active: const drift.Value(false),
      ),
    );
    await _loadActiveObjectives();
  }

  /// One secondary today-row. Match/replace by held id. Never primary,
  /// never tasks, never an ambition, never evicts other secondaries.
  Future<void> _upsertTodayObjective(String line) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty || _currentSessionId == null) return;
    final heldId = _todayObjectiveId;
    if (heldId != null) {
      final held = await _heldTodayRow();
      if (held != null && held.objective == trimmed) {
        _todayObjectiveText = trimmed;
        await _persistTodayObjectiveId(heldId);
        return;
      }
      if (held != null) {
        await _deactivateTodayObjective();
      } else {
        // The held row is gone (the user cleared the quest, or a rewind
        // took it). Drop the pointer and write the line again, even when
        // the sentence matches: _heldTodayRow already asked the database.
        _todayObjectiveId = null;
        _todayObjectiveText = null;
        await _persistTodayObjectiveId(null);
      }
    }
    final newId = const Uuid().v4();
    _todayObjectiveId = newId;
    _todayObjectiveText = trimmed;
    final inserted = await _insertTodaySideQuest(trimmed, id: newId);
    if (inserted == null) {
      _todayObjectiveId = null;
      _todayObjectiveText = null;
      await _persistTodayObjectiveId(null);
    }
  }

  Future<void> _onTodayObjectiveCompleted(Objective obj) async {
    if (!_isHeldTodayObjective(obj)) return;
    final held = todaySentence ?? obj.objective;
    _recordTodayPointerOp();
    _todayObjectiveId = null;
    _todayObjectiveText = null;
    setTodaySentence(null);
    unawaited(() async {
      await _journalResolvedToday(
        held,
        fate: PlannerTodayFate.done,
        ownerId: obj.characterId,
      );
      await _persistTodayObjectiveId(null);
    }());
  }

  /// Journal a finished or day-eaten line. Capture [held] before clearing.
  /// Abandoned lines sour mood and do not write a card. The card is the
  /// today row's owner's ([ownerId], else the held row's member): in a
  /// group that is the member whose reply wrote the line, not the speaker.
  Future<void> _journalResolvedToday(
    String? held, {
    required PlannerTodayFate fate,
    String? ownerId,
  }) async {
    final line = held?.trim();
    if (line == null || line.isEmpty) return;
    if (!_storageService.realismSettings.plannerEnabled) return;
    // Taken now, while the turn that resolved the line is still running.
    final cite = _objectiveTurnCite();
    _nudgePlannerMood(fate);
    if (fate == PlannerTodayFate.abandoned) return;
    final sessionId = _currentSessionId;
    final card = _activeCharacter;
    final mood = _characterEmotion;
    final owner =
        ownerId ??
        (await _heldTodayRow())?.characterId ??
        (card == null ? null : _getCharacterIdFromCard(card));
    if (sessionId == null || owner == null) return;
    await _journalStore.addCard(
      sessionId: sessionId,
      characterId: owner,
      content: line,
      category: 'moment',
      kind: 'today',
      sourcePositions: cite,
      storyDay: _timeService.dayCount,
      storyClock: _timeService.storyClockIso,
      emotionLabel: mood.isEmpty ? null : mood,
      maxCards: _storageService.memorySettings.journalMaxCards,
    );
  }
}
