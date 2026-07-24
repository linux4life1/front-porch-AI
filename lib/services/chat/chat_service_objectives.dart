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

/// Objective System — load/inject/set/clear objectives, task management
/// (toggle/update/add/remove/complete), and background completion checks.
/// Extracted verbatim (zero behaviour change) to shrink the god file.
extension ChatServiceObjectives on ChatService {
  // ── Objective System ───────────────────────────────────────────────────

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
      if (currentSecondaries.length >= 2) {
        for (int i = 0; i < currentSecondaries.length - 1; i++) {
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
    await _loadActiveObjectives();
  }

  /// Generate subtasks for the current objective using the LLM.
  /// Clears existing tasks first so regen always produces a clean slate.
  // Thin delegation (full generateObjectiveTasks + 2000 budget + central strip + proposal
  // handling in objective_proposal step 11; objective mgmt coordination / list / load / db
  // updates stayed thin in god per plan for step9/11; "thin delegation here; full objective
  // proposal in step 11").
  Future<void> generateObjectiveTasks(
    Objective obj, {
    int taskCount = 5,
    bool nsfw = false,
  }) => _objectiveProposal.generateObjectiveTasks(
    obj,
    taskCount: taskCount,
    nsfw: nsfw,
  );

  /// Marks the first uncompleted task matching taskDesc as completed (best-effort side-effect
  /// for auto-complete in checkTaskCompletionInBackground currentTask YES path).
  /// (Thin delegation; full mutation logic here in god per plan for step 11 to keep list/db
  /// mutation thin/stayed in god; leaf calls via cb. Matches toggleTask pattern exactly.)
  Future<void> markTaskCompleted(Objective obj, String taskDesc) async {
    final tasks = tasksForObjective(obj);
    final idx = tasks.indexWhere(
      (t) => (t['description'] as String) == taskDesc && t['completed'] != true,
    );
    if (idx < 0) return;
    // Turn-op for regen rollback: obj.tasks is still the pre-mutation JSON here,
    // so the inverse is a plain write-back of that string. Armed-gated: manual
    // "Check now" completions are user actions, not turn ops.
    if (_objectiveTurnOpsArmed) {
      _recordObjectiveTurnOp({
        'op': 'tasks_changed',
        'id': obj.id,
        'prev': obj.tasks,
      });
    }
    tasks[idx]['completed'] = true;
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Manually toggle a task's completion status.
  Future<void> toggleTask(Objective obj, int taskIndex) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;

    tasks[taskIndex]['completed'] = !(tasks[taskIndex]['completed'] as bool);
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Update the description of a specific task.
  Future<void> updateTask(
    Objective obj,
    int taskIndex,
    String newDescription,
  ) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;
    if (newDescription.trim().isEmpty) return;

    tasks[taskIndex]['description'] = newDescription.trim();
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
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

  /// Add a manually created task to the active objective.
  Future<void> addManualTask(Objective obj, String description) async {
    if (description.trim().isEmpty) return;
    final tasks = tasksForObjective(obj);
    tasks.add({'description': description.trim(), 'completed': false});
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Remove a task from the active objective.
  Future<void> removeTask(Objective obj, int taskIndex) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;
    tasks.removeAt(taskIndex);
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Update how often task completion is checked.
  Future<void> updateCheckFrequency(Objective obj, int frequency) async {
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        checkFrequency: drift.Value(frequency),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Check if the current task has been completed (called periodically).
  /// Manually trigger a completion check (called from UI "Check now" button).
  void forceCheckCompletion() {
    if (_activeObjectives.isEmpty) return;
    _checkTaskCompletionInBackground(); // step 11 thin (full in objective_proposal)
    notifyListeners(); // trigger UI to show spinner
  }

  /// Synchronous version — awaits the check. Used pre-generation.
  Future<void> _maybeCheckTaskCompletionSync() async {
    if (_activeObjectives.isEmpty ||
        _llmProvider == null ||
        _isCheckingCompletion) {
      return;
    }

    _messagesSinceLastCheck++;
    final freq = _realismEnabled
        ? 1
        : (primaryObjective?.checkFrequency ??
              _activeObjectives.first.checkFrequency);
    if (_messagesSinceLastCheck < freq) return;
    _messagesSinceLastCheck = 0;

    // Arm turn-op recording only for THIS turn-path check (see field doc):
    // its completions/retirements belong to the turn being generated and must
    // roll back on regen; manual "Check now" runs the same check unarmed.
    _objectiveTurnOpsArmed = true;
    try {
      await _checkTaskCompletionInBackground(); // step 11 thin (full in objective_proposal)
    } finally {
      _objectiveTurnOpsArmed = false;
    }
  }

  // Thin delegation (full _checkTaskCompletionInBackground + 2000 budget + central strip in
  // objective_proposal step 11; objective mgmt coordination / isChecking flag / load / db
  // updates stayed thin in god per plan for step9/11; "thin delegation here; full objective
  // proposal in step 11").
  Future<void> _checkTaskCompletionInBackground() =>
      _objectiveProposal.checkTaskCompletionInBackground();

  // ── Objective turn-ops: regen rollback (mirrors the realism delta-revert) ──
  //
  // Objective mutations attributable to a turn (eval-proposed creations with
  // their demotion/eviction side effects, check-driven task completions and
  // quest retirements) are recorded here and ride
  // _pendingRealismMetadata['objective_turn_ops'], so they attach to the bot
  // message the turn produced via the exact flush/reset machinery the realism
  // metadata already uses. regenerateLastMessage inverts them (reversed, by
  // objective id — character-agnostic, so 1:1 and group behave identically)
  // before replaying the evals, which may then legitimately re-propose for the
  // new turn. Nothing user-initiated ever records: panel setObjective,
  // toggleTask, clearObjective have no recording path, and the check-driven
  // sites are gated on _objectiveTurnOpsArmed, which only the turn-path
  // check in _maybeCheckTaskCompletionSync arms — so a manual "Check now"
  // (forceCheckCompletion) runs the same check unrecorded and regen can
  // never undo a user action.
  //
  // Known follow-up (deliberate, reviewed): swiping BACK to a rejected swipe
  // does not re-apply its inverted ops (faithful 'created' re-apply is
  // impossible from this op log — auto task-gen fills tasks async after the
  // metadata flush). Accepting an old swipe and continuing self-heals at the
  // next turn's check/eval, which re-derives completions and can re-propose;
  // until that turn the panel reflects the newest swipe's objective state.

  /// Append one turn op to the pending realism metadata (created on demand;
  /// leaves always start from getPendingRealismMetadata(), so the list
  /// survives their read-mutate-set pattern).
  void _recordObjectiveTurnOp(Map<String, dynamic> op) {
    _pendingRealismMetadata ??= {};
    final list =
        (_pendingRealismMetadata!['objective_turn_ops'] ??= <dynamic>[])
            as List;
    list.add(op);
  }

  /// Invert the rejected message's recorded objective ops (reverse order):
  /// created → deleted, tasks_changed → pre-mutation JSON restored,
  /// deactivated/evicted → reactivated, demoted → primary restored. Blind
  /// id-addressed updates: a row deleted since (e.g. chat cleanup) no-ops.
  Future<void> _revertObjectiveTurnOps(ChatMessage rejectedMsg) async {
    final raw = rejectedMsg.activeMetadata?['objective_turn_ops'];
    if (raw is! List || raw.isEmpty) return;
    for (final entry in raw.reversed) {
      if (entry is! Map) continue;
      final id = entry['id'] as String?;
      if (id == null || id.isEmpty) continue;
      try {
        switch (entry['op']) {
          case 'created':
            await _db.deleteObjective(id);
          case 'tasks_changed':
            final prev = entry['prev'];
            if (prev is String) {
              await _db.updateObjective(
                ObjectivesCompanion(
                  id: drift.Value(id),
                  tasks: drift.Value(prev),
                ),
              );
            }
          case 'deactivated' || 'evicted':
            await _db.updateObjective(
              ObjectivesCompanion(
                id: drift.Value(id),
                active: const drift.Value(true),
              ),
            );
          case 'demoted':
            // Reconciliation guard (review finding): if the user promoted a
            // DIFFERENT objective to primary between the turn and this regen,
            // blindly restoring this one would leave two active primaries.
            // The user's later choice wins — skip the restore then.
            final charId = entry['charId'] as String?;
            var otherPrimaryExists = false;
            if (charId != null && charId.isNotEmpty) {
              final current = await _db.getObjectivesForCharacter(
                charId,
                chatId: _currentSessionId,
              );
              otherPrimaryExists = current.any(
                (o) => o.active && o.isPrimary && o.id != id,
              );
            }
            if (!otherPrimaryExists) {
              await _db.updateObjective(
                ObjectivesCompanion(
                  id: drift.Value(id),
                  isPrimary: const drift.Value(true),
                ),
              );
            }
        }
      } catch (e) {
        debugPrint('[Objective] Regen revert op failed (${entry['op']}): $e');
      }
    }
    debugPrint(
      '[Objective] Regen reverted ${raw.length} turn op(s) from rejected message',
    );
    // Refresh the in-memory list the UI/injection reads. In group mode the
    // turn manager has already been forced back to the rejected speaker, so
    // the speaker loader targets the right member.
    if (_activeGroup != null) {
      await _loadObjectivesForCurrentSpeaker();
    } else {
      await _loadActiveObjectives();
    }
  }
}
