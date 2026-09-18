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

/// Objective completion checks, regen turn-ops, and promise/debt.
/// Gates on the live [ChatService.objectivesActive] AND, never a stored AND.
extension ChatServiceObjectiveCompletion on ChatService {
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
    if (!objectivesActive || _activeObjectives.isEmpty) return;
    _checkTaskCompletionInBackground(); // step 11 thin (full in objective_proposal)
    notifyListeners(); // trigger UI to show spinner
  }

  /// Synchronous version — awaits the check. Used pre-generation.
  Future<void> _maybeCheckTaskCompletionSync() async {
    // The recurring cost this feature's switch exists to stop: one model call
    // every `freq` messages, forever, for as long as a quest is open.
    if (!objectivesActive ||
        _activeObjectives.isEmpty ||
        _llmProvider == null ||
        _isCheckingCompletion) {
      return;
    }

    _messagesSinceLastCheck++;
    // The per-objective cadence the UI exposes is the cadence, full stop.
    // The old realism-on override forced freq to one — a BLOCKING model
    // call, awaited before every reply — onto every single turn the moment
    // any quest was open with the engine on, silently ignoring the
    // checkFrequency the user can see and set (eval review Tier-1 §3.1).
    final freq =
        primaryObjective?.checkFrequency ??
        _activeObjectives.first.checkFrequency;
    if (_messagesSinceLastCheck < freq) {
      // Off-interval, the check still fires the moment the scene actually
      // touches a quest: a completion can only be shown by the exchange, and
      // the check reads exactly this window — so an exchange sharing none of
      // a quest's content words is a guaranteed NO not worth a blocking
      // round trip. A paraphrase the gate misses is caught by the next
      // interval check, never lost. Cast + user name tokens are excluded or
      // "get Jennifer to admit her fear" would match every line Jennifer
      // speaks.
      final recentLower = _messages.reversed
          .take(8)
          .map((m) => m.promptText)
          .join('\n')
          .toLowerCase();
      final quests = <String>[
        for (final o in _activeObjectives) ...[
          o.objective,
          for (final t in tasksForObjective(o))
            if (t['completed'] != true) (t['description'] as String? ?? ''),
        ],
      ];
      final ignore = <String>{
        for (final c in [?_activeCharacter, ..._groupCharacters])
          ...c.name.toLowerCase().split(RegExp(r'[^a-z0-9]+')),
        ..._userPersonaService.persona.name.toLowerCase().split(
          RegExp(r'[^a-z0-9]+'),
        ),
      }..remove('');
      if (!objectivesMentionedIn(recentLower, quests, ignore: ignore)) {
        return;
      }
      debugPrint('[Objective] Mention gate: quest touched — checking early');
    }
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

  /// Manual "Mark kept / broken" from the diary's Promises tab (desktop) and
  /// the web Promises panel. Same applier as automatic detection — the
  /// trust/bond effects apply too, restoring what a missed detection should
  /// have done.
  Future<bool> resolvePromiseManually({
    required String characterId,
    required String cardId,
    required bool kept,
  }) async {
    final sessionId = _currentSessionId;
    if (sessionId == null) return false;
    // Never mid-turn: the scalar dance below would fight the active
    // speaker's own load/save.
    if (_isTurnBusy) return false;
    // Group parity: the service's trust/bond callbacks land on whichever
    // member's scalars are LOADED. Manual resolution can come from any
    // member's diary at any time, so run the same load → apply → save
    // dance the post-gen checks use, scoped to that member.
    final isGroupMember =
        _activeGroup != null &&
        _groupCharacters.any((c) => _getCharacterIdFromCard(c) == characterId);
    if (isGroupMember) _loadGroupRealismIntoScalars(characterId);
    final ok = await _promiseDebtService.resolveManually(
      sessionId: sessionId,
      characterId: characterId,
      cardId: cardId,
      kept: kept,
      storyDay: _timeService.dayCount,
      storyClock: _timeService.storyClockIso,
    );
    if (isGroupMember) _saveScalarsIntoGroupRealism(characterId);
    if (ok) await _saveChat();
    return ok;
  }

  /// Train B — promise/debt ledger pass (fire-and-forget). Detects new
  /// commitments or kept/broken resolutions for the current speaker's diary.
  /// (Moved verbatim from chat_service.dart — commitment tracking belongs
  /// with the objectives part; god-file ratchet.)
  ///
  /// Gated on the Journal and its own switch, NOT on the Realism Engine. It
  /// used to require realism, but nothing here consumes realism state: the pass
  /// reads the recent exchange text and writes a journal card. The story day
  /// and clock it stamps are nullable and nothing reads them back, so a frozen
  /// clock costs nothing. The Journal genuinely is required — a commitment IS a
  /// journal card — and the separate switch exists because this is one extra
  /// model call per reply, which a user who turned realism off to save calls
  /// deserves to opt into rather than inherit.
  void _maybeRunPromiseDebtPass() {
    if (!_storageService.realismSettings.promiseLedgerEnabled) return;
    if (!_storageService.memorySettings.journalEnabled) return;
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    final charId = _getCurrentSpeakerIdForRealism();
    if (charId.isEmpty) return;

    String characterName = _activeCharacter?.name ?? 'the character';
    if (_activeGroup != null && !_observerMode) {
      final card = _groupCharacters
          .where((c) => _getCharacterIdFromCard(c) == charId)
          .firstOrNull;
      if (card != null) characterName = card.name;
    }

    // 6, not the judges' 4: a promise often spans a couple of exchanges
    // (missed KEPT if it scrolls out — 2026-08-04). recentExchange is the
    // one window builder (clamp, photo markers, think-strip).
    final recent = recentExchange(_messages, take: 6);
    if (recent.trim().isEmpty) return;

    unawaited(
      _promiseDebtService.evaluateTurn(
        sessionId: sessionId,
        characterId: charId,
        characterName: characterName,
        userName: _userPersonaService.persona.name,
        recentExchange: recent,
        receiptPosition: persistTipCite(
          base: _history.basePosition,
          length: _messages.length,
        ).firstOrNull,
        storyDay: _timeService.dayCount,
        storyClock: _timeService.storyClockIso,
      ),
    );
  }
}
