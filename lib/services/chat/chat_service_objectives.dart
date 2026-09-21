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

/// Objectives inject — load, prompt text, set/clear/promote, today line.
/// Tasks live in [ChatServiceObjectiveTasks]; completion checks and
/// promise/debt live in [ChatServiceObjectiveCompletion].
/// `objectivesActive` stays the live AND on the class.
extension ChatServiceObjectives on ChatService {
  // ── Objective System ───────────────────────────────────────────────────

  /// All active objectives for the current character/session (both primary
  /// and secondary — see [primaryObjective] / [secondaryObjectives] for the
  /// split views).
  List<Objective> get activeObjectives => _activeObjectives;

  /// Load the active objectives for the current session from DB.
  Future<void> _loadActiveObjectives() async {
    if (_activeCharacter == null || _currentSessionId == null) {
      _activeObjectives = [];
      _messagesSinceLastCheck = 0;
      _isCheckingCompletion = false;
      _summaryPaused =
          false; // explicit secondary zero for _summaryPaused (symmetric; _loadActiveObjectives empty hygiene)
      _isSummaryGenerating =
          false; // secondary zero in _loadActiveObjectives empty (0-session hygiene for summary flag)
      _isGrowthPassRunning =
          false; // growth-pass flag zero in _loadActiveObjectives empty (0-session hygiene; keep reset blocks in sync)
      _clearTodayPointer();
      return;
    }
    final charId = _getCharacterIdFromCard(_activeCharacter!);
    try {
      _activeObjectives = await _db.getActiveObjectives(
        charId,
        chatId: _currentSessionId!,
      );
      for (final obj in _activeObjectives) {
        debugPrint(
          '[Objective] Loaded: ${obj.objective} (Primary: ${obj.isPrimary})',
        );
      }
    } catch (e) {
      debugPrint(
        '[Objective] Failed to load (will run without objectives this session): $e',
      );
      _activeObjectives = [];
    }
    _rebindTodayObjectiveFromDb();
    notifyListeners(); // Central _disposed guard in ChatService overrides now protects this (and all other) post-async notify sites. Per-site try/catch removed (deletion part of rec 2 task); see god _disposed + notify override + setActiveCharacter:2205 comment.
  }

  /// Build the prompt injection text for the active objectives.
  /// Wording intensity varies based on injection depth for the primary objective.
  /// Secondary objectives are injected as ambient background goals.
  String _getObjectiveInjection() {
    // Thin delegation (full in AuthorNoteBuilder per step 8). Objective state mgmt
    // (lists, getters, tasksFor) stays in god (objective_service is later step).
    return _authorNoteBuilder.buildObjectiveInjection();
  }

  /// Set a new objective for the current session (or for a specific character when in group mode).
  ///
  /// [autoGenerateTasks] defaults to false. User-created objectives (typed in the UI) should
  /// not auto-generate subtasks — the user is in control of their own quests and can use the
  /// explicit "Generate Tasks" button if desired.
  ///
  /// Autonomous objectives proposed by the character (via the realism "proposed_objective"
  /// evals) pass true so that the character's self-generated goals come with concrete
  /// sequential tasks. This makes the AI-driven objectives feel organic and like something
  /// the character is actively striving to accomplish. The evals also claim the
  /// main-quest slot (isPrimary: true) when the character has no primary yet, so an
  /// autonomous goal becomes a real overarching quest instead of an ambient side goal.
  Future<void> setObjective(
    String goal, {
    bool isPrimary = true,
    CharacterCard? targetCharacter,
    bool autoGenerateTasks = false,
    bool recordTurnOps = false,

    /// v46 — the ambition this quest is a step toward, or null for one that
    /// serves none. Only the autonomous proposal paths pass it; a quest the
    /// user typed has no eval behind it to say which mountain it climbs.
    String? servedAmbition,
  }) async {
    if (goal.trim().isEmpty) return;
    if (_currentSessionId == null) return;

    CharacterCard? target = targetCharacter;
    if (target == null) {
      if (_activeGroup != null) {
        // During per-speaker group realism evals (which propose autonomous objectives),
        // _activeCharacter is temporarily impersonated to the evaluated speaker. Prefer it
        // so the character's own internal goal attaches to *them*, not nextCharacter.
        final currentIsGroupMember =
            _activeCharacter != null &&
            _groupCharacters.any(
              (c) =>
                  _getCharacterIdFromCard(c) ==
                  _getCharacterIdFromCard(_activeCharacter!),
            );
        if (currentIsGroupMember) {
          target = _activeCharacter;
        } else {
          target = nextCharacter ?? _groupCharacters.firstOrNull;
        }
      } else {
        target = _activeCharacter;
      }
    }
    if (target == null) return;

    final charId = _getCharacterIdFromCard(target);

    if (isPrimary) {
      final existing = await _db.getObjectivesForCharacter(
        charId,
        chatId: _currentSessionId,
      );
      for (final obj in existing) {
        if (obj.active && obj.isPrimary) {
          await _db.updateObjective(
            ObjectivesCompanion(
              id: drift.Value(obj.id),
              isPrimary: const drift.Value(false),
            ),
          );
          if (recordTurnOps) {
            // charId enables the invert's primary-reconciliation guard.
            _recordObjectiveTurnOp({
              'op': 'demoted',
              'id': obj.id,
              'charId': charId,
            });
          }
        }
      }
    } else {
      final currentSecondaries = secondaryObjectives;
      if (currentSecondaries.length >= kMaxSecondaryObjectives) {
        // Oldest first (createdAt asc). Drop enough to leave room for the
        // new one. Today insert does not use this door.
        final drop = currentSecondaries.length - (kMaxSecondaryObjectives - 1);
        for (var i = 0; i < drop; i++) {
          await _db.updateObjective(
            ObjectivesCompanion(
              id: drift.Value(currentSecondaries[i].id),
              active: const drift.Value(false),
            ),
          );
          if (recordTurnOps) {
            _recordObjectiveTurnOp({
              'op': 'evicted',
              'id': currentSecondaries[i].id,
            });
          }
        }
      }
    }

    final newId = const Uuid().v4();
    await _db.insertObjective(
      ObjectivesCompanion.insert(
        id: newId,
        characterId: charId,
        objective: goal.trim(),
        chatId: drift.Value(_currentSessionId),
        active: const drift.Value(true),
        isPrimary: drift.Value(isPrimary),
        servedAmbition: drift.Value(servedAmbition),
      ),
    );
    if (recordTurnOps) {
      _recordObjectiveTurnOp({'op': 'created', 'id': newId, 'charId': charId});
    }

    await _loadActiveObjectives();
    _messagesSinceLastCheck = 0;

    if (autoGenerateTasks) {
      try {
        final forChar = await getActiveObjectivesFor(target);
        final matches = forChar.where((o) => o.id == newId);
        final addedObj = matches.isNotEmpty ? matches.first : null;
        if (addedObj != null) {
          unawaited(
            generateObjectiveTasks(
              addedObj,
              // A main quest gets a full arc; a side quest stays a short beat.
              taskCount: isPrimary ? 5 : 3,
              nsfw: false,
            ), // step 11 thin (full in objective_proposal)
          );
        }
      } catch (_) {
        // Objective created successfully; task generation is best-effort and non-fatal.
        // User can always tap "Generate Tasks" manually.
      }
    }
  }

  /// Planner today line: one secondary, no tasks, no ambition, no eviction.
  Future<String?> _insertTodaySideQuest(String goal, {String? id}) async {
    if (goal.trim().isEmpty || _currentSessionId == null) return null;
    CharacterCard? target;
    if (_activeGroup != null) {
      final currentIsGroupMember =
          _activeCharacter != null &&
          _groupCharacters.any(
            (c) =>
                _getCharacterIdFromCard(c) ==
                _getCharacterIdFromCard(_activeCharacter!),
          );
      target = currentIsGroupMember
          ? _activeCharacter
          : (nextCharacter ?? _groupCharacters.firstOrNull);
    } else {
      target = _activeCharacter;
    }
    if (target == null) return null;
    final newId = id ?? const Uuid().v4();
    await _db.insertObjective(
      ObjectivesCompanion.insert(
        id: newId,
        characterId: _getCharacterIdFromCard(target),
        objective: goal.trim(),
        chatId: drift.Value(_currentSessionId),
        active: const drift.Value(true),
        isPrimary: const drift.Value(false),
        servedAmbition: const drift.Value(null),
      ),
    );
    await _persistTodayObjectiveId(newId);
    await _loadActiveObjectives();
    return newId;
  }

  /// Promote an existing side quest to the primary quest IN PLACE, demoting any
  /// current primary to a side quest. Unlike calling [setObjective] with the same
  /// text (the old promote pattern), this keeps the objective's id and its
  /// generated task progress, and cannot leave a duplicate copy of the goal
  /// behind as a still-active side quest.
  Future<void> promoteObjective(Objective obj) async {
    if (_currentSessionId == null) return;
    final existing = await _db.getObjectivesForCharacter(
      obj.characterId,
      chatId: _currentSessionId,
    );
    for (final o in existing) {
      if (o.active && o.isPrimary && o.id != obj.id) {
        await _db.updateObjective(
          ObjectivesCompanion(
            id: drift.Value(o.id),
            isPrimary: const drift.Value(false),
          ),
        );
      }
    }
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        isPrimary: const drift.Value(true),
      ),
    );
    if (_todayObjectiveId == obj.id) {
      _todayObjectiveId = null;
      _todayObjectiveText = null;
      setTodaySentence(null);
      await _persistTodayObjectiveId(null);
    }
    await _loadActiveObjectives();
  }

  /// Clear the active objective.
  Future<void> clearObjective(Objective obj) async {
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        active: const drift.Value(false),
      ),
    );
    await _loadActiveObjectives();
    _messagesSinceLastCheck = 0;
  }

  /// Update the injection depth for the active objective.
  Future<void> updateObjectiveDepth(Objective obj, int depth) async {
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        injectionDepth: drift.Value(depth),
      ),
    );
    await _loadActiveObjectives();
  }

  // ── Round-4b forwarder bodies (see chat_service_accessors.dart's banner
  // comment for why these stay one-line forwarders on the class body) ──

  /// Returns the personal objectives for a specific character when in group mode.
  /// Falls back to the global list for 1:1 or when no per-char data exists yet.
  List<Objective> _getObjectivesForGroupCharacterImpl(CharacterCard character) {
    if (_activeGroup == null) return _activeObjectives;
    final id = _getCharacterIdFromCard(character);
    return _groupObjectives[id] ?? const <Objective>[];
  }

  /// Loads the active objectives for the given character in the current session.
  /// Safe to call from group objective UIs — does not mutate global _activeObjectives.
  Future<List<Objective>> _getActiveObjectivesForImpl(
    CharacterCard character,
  ) async {
    if (_currentSessionId == null) return const [];
    final charId = _getCharacterIdFromCard(character);
    try {
      return await _db.getActiveObjectives(charId, chatId: _currentSessionId!);
    } catch (e) {
      debugPrint('[Objective] Failed to load for ${character.name}: $e');
      return const [];
    }
  }
}
