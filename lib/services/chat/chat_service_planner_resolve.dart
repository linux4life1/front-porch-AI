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

  /// Rebind by the persisted session id. Never guess among secondaries.
  void _rebindTodayObjectiveFromDb() {
    final id = _todayObjectiveId;
    if (id == null) return;
    final live = _activeObjectives.where((o) => o.id == id).firstOrNull;
    if (live == null) {
      // Chat-scoped hold lives on another member's list. Keep the
      // pointer so the next upsert/day-ate still finds the row.
      return;
    }
    _todayObjectiveText = live.objective;
    if (_todaySentence == null) setTodaySentence(live.objective);
  }

  bool _isHeldTodayObjective(Objective obj) {
    return _todayObjectiveId != null && obj.id == _todayObjectiveId;
  }

  Future<void> _deactivateTodayObjective() async {
    final id = _todayObjectiveId;
    if (id == null) return;
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
      final held = _activeObjectives.where((o) => o.id == heldId).firstOrNull;
      if (held != null && held.objective == trimmed) {
        _todayObjectiveText = trimmed;
        await _persistTodayObjectiveId(heldId);
        return;
      }
      if (held == null &&
          (_todayObjectiveText == trimmed || todaySentence == trimmed)) {
        // List has not loaded the held row yet. Do not insert a second.
        await _persistTodayObjectiveId(heldId);
        return;
      }
      if (held != null && held.objective != trimmed) {
        await _deactivateTodayObjective();
      } else if (held == null) {
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
    _todayObjectiveId = null;
    _todayObjectiveText = null;
    setTodaySentence(null);
    unawaited(() async {
      await _journalResolvedToday(held, fate: PlannerTodayFate.done);
      await _persistTodayObjectiveId(null);
    }());
  }

  /// Journal a finished or day-eaten line. Capture [held] before clearing.
  /// Abandoned lines sour mood and do not write a card.
  Future<void> _journalResolvedToday(
    String? held, {
    required PlannerTodayFate fate,
  }) async {
    final line = held?.trim();
    if (line == null || line.isEmpty) return;
    if (!_storageService.realismSettings.plannerEnabled) return;
    _nudgePlannerMood(fate);
    if (fate == PlannerTodayFate.abandoned) return;
    final sessionId = _currentSessionId;
    final card = _activeCharacter;
    if (sessionId == null || card == null) return;
    await _journalStore.addCard(
      sessionId: sessionId,
      characterId: _getCharacterIdFromCard(card),
      content: line,
      category: 'moment',
      kind: 'today',
      storyDay: _timeService.dayCount,
      storyClock: _timeService.storyClockIso,
      emotionLabel: _characterEmotion.isEmpty ? null : _characterEmotion,
      maxCards: _storageService.memorySettings.journalMaxCards,
    );
  }
}
