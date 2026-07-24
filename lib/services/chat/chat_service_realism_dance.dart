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

/// Per-speaker realism evaluation + the load/save impersonation dance
/// (_evaluateRealismForUpcomingSpeaker / _loadGroupRealismIntoScalars /
/// _saveScalarsIntoGroupRealism). Extracted verbatim (zero behaviour change).
extension ChatServiceRealismDance on ChatService {
  /// Runs targeted realism evaluation for the specific character who is about
  /// to speak next in a group chat. This is the core of making realism work
  /// on a per-character, turn-timed basis.
  ///
  /// Uses temporary impersonation of _activeCharacter so that all existing
  /// realism eval methods (_evaluateOneShotCall, _evaluateRelationshipCall, etc.)
  /// and their parsing/inertia logic are reused without duplication.
  Future<void> _evaluateRealismForUpcomingSpeaker(
    CharacterCard speaker,
  ) async {
    // Unified gate: runs for the 1:1 host AND each group speaker (one at a time);
    // skips group observer mode and realism-off. This is the single realism eval
    // path — the former centralized 1:1 block was removed in favour of this.
    if (!_realismActiveThisMode) return;

    final charId = _getCharacterIdFromCard(speaker);
    if (charId.isEmpty) return;

    debugPrint(
      '[Realism:Unified] Pre-turn eval for upcoming speaker: ${speaker.name} '
      '($charId) — mode=${_activeGroup == null ? "1:1" : "group"}',
    );

    // Save previous 1:1 context (normally null in pure group sessions)
    final previousActiveCharacter = _activeCharacter;

    // Impersonate this speaker for the duration of the eval so all existing
    // LLM eval methods, guards, name/personality reads, and delta application
    // logic work exactly as they do for 1:1 chats.
    _activeCharacter = speaker;

    // Short-term bond decay for the PINNED speaker (moved from sendMessage,
    // where the speaker wasn't picked yet and random turn order made the
    // decay always hit the first member). The check runs on this speaker's
    // own cadence counter directly against their map entry, so it is correct
    // to run it BEFORE the scalar load below (the map write flows into the
    // load). 1:1 keeps its original sendMessage tick.
    if (_activeGroup != null && !_observerMode) {
      _applyMoodDecay();
    }

    // Group non-observer: ensure this definite speaker receives their per-turn needs decay
    // (central tick in sendMessage is skipped for groups to support random turn order without
    // always decaying the 'first' member). Snapshot the pre-decay value for chips/realism_state
    // *before* applying this turn's decay, then decay the speaker's map entry, then load scalars.
    if (_activeGroup != null && !_observerMode && _needsSimEnabled) {
      final sidForDecay = charId;
      final currentForSpeaker = _getGroupNeeds(sidForDecay);
      final preDecay = currentForSpeaker.isNotEmpty
          ? Map<String, int>.from(currentForSpeaker)
          : {
              for (final k in NeedsSimulation.needKeys)
                k: NeedsSimulation.needDefaults[k] ?? 80,
            };
      // Stash the true pre-decay for this speaker so post-gen chip delta computation
      // (and regen) see the correct baseline including the decay portion of the turn.
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['needs_pre_turn_vector'] = preDecay;

      // Apply one tick of decay directly to this speaker's group entry using
      // THIS speaker's own per-member decay rates (from their card ext) — the
      // same source the 1:1 path uses — so each group member decays at its own
      // authored rate. `_activeCharacter` is this speaker (impersonated above).
      // decayedValueFor is THE shared rule (rate + modifier pipeline): group
      // members get the same conditional decay boosts (low energy → faster
      // hunger, etc.) that 1:1 always applied — this loop used to skip them.
      final decayed = Map<String, int>.from(preDecay);
      final customRates = _activeDecayRates();
      for (final key in NeedsSimulation.needKeys) {
        final cur = decayed[key] ?? 80;
        decayed[key] = _needsSimulation.decayedValueFor(
          key,
          cur,
          decayed,
          customRates,
        );
      }
      _setGroupNeeds(sidForDecay, decayed);

      // Now load the post-decay state into scalars for the remainder of the speaker eval + prompt injection.
      _loadGroupRealismIntoScalars(charId);

      // Catastrophe check on THIS speaker's just-loaded vector — 1:1 parity
      // (the 1:1 host runs this inside tickDecay). Persist the recovery floor
      // back to the speaker's group entry so it sticks.
      _needsSimulation.applyCatastropheIfNeeded();
      _setGroupNeeds(sidForDecay, Map<String, int>.from(_needsSimulation.vector));
    } else if (_activeGroup != null) {
      // Group speaker (observer mode or needs-off): load this speaker's persisted
      // group realism state into the scalar fields the eval will read and mutate.
      _loadGroupRealismIntoScalars(charId);
    }

    // Per-speaker refractory tick (group only — the 1:1 host ticks in
    // sendMessage, which is now gated to 1:1). Must run AFTER this speaker's
    // scalars are loaded; the old pre-pick site in sendMessage ticked the
    // previous speaker's loaded scalars and the tick was lost on load, so
    // group cooldowns never counted down. Saved back to the per-char map
    // immediately (like the needs decay write above) so a cancelled eval
    // can't lose the tick.
    if (_activeGroup != null && !_observerMode) {
      _nsfwService.decrementCooldownIfActive();
      _nsfwService.saveNsfwScalarsToGroup(charId);
    }
    // 1:1 host: the scalar fields ALREADY hold this character's loaded + post-decay
    // state (restored by loadSession, decayed in sendMessage). The _groupRealism map
    // is a group-only store whose writes are gated on `_activeGroup != null`, so
    // loading from it here would overwrite the host's real state with empty defaults
    // (bond 0, trust default, fresh needs) — this was the "loading a 1:1 chat nukes
    // realism" regression. The eval mutates the scalars in place; _saveChat persists
    // them as it always has for 1:1.

    // Phase 2: Ensure hidden inter-character relationship tracking is seeded
    // for all other group members (neutral 0). This happens on the speaker's
    // first turn with realism so the invisible feelings map is always present.
    _relationshipService.ensureInterCharacterRelationshipsSeeded(charId);

    _isEvaluatingRealism = true;
    _realismEvalStreamText = '';
    notifyListeners();

    // Capture this speaker's pre-turn needs vector (before decay + eval)
    Map<String, int>? preTurnVector;
    if (_needsSimEnabled && _needsSimulation.vector.isNotEmpty) {
      preTurnVector = Map<String, int>.from(_needsSimulation.vector);
    }

    // Temporarily load this speaker's personal objectives so the narrative
    // evaluation (and one-shot) sees the correct primary/secondary context
    // for "proposed_objective" generation. This is required for 1:1 parity.
    final previousObjectives = List<Objective>.from(_activeObjectives);
    final speakerObjectives = await getActiveObjectivesFor(speaker);
    _activeObjectives = speakerObjectives.where((o) => o.active).toList();

    void handleChunk(String chunk) {
      _realismEvalStreamText += chunk;
      _evalChunkTimer?.cancel();
      _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
        try {
          notifyListeners();
        } catch (_) {}
      });
    }

    try {
      // Respect early cancellation. Do NOT consume the flag here: the callers
      // own it — sendMessage (1:1) and _generateResponse (group) both check it
      // right after this returns and abort generation. Consuming it here was
      // why Cancel stopped aborting generation.
      if (_realismEvalCancelled) {
        debugPrint(
          '[Realism:Group] Evaluation cancelled before LLM calls for ${speaker.name}',
        );
        return;
      }

      if (_relationshipService.pendingTrustRepair) {
        // Trust-repair eval (fires when trust dropped sharply). Was 1:1-only in
        // the old centralized block; now part of the single path so the host
        // keeps it (and a group member would too, if their trust ever flags it).
        debugPrint(
          '[Realism:Unified] Trust-repair eval for ${speaker.name} ($charId)',
        );
        _relationshipService.consumePendingTrustRepair();
        final userText = _messages
            .lastWhere(
              (m) => m.isUser,
              orElse: () => ChatMessage(text: '', sender: '', isUser: true),
            )
            .text;
        await _evaluateTrustRepairCall(userText, onChunk: handleChunk);
      } else if (_storageService.realismSettings.realismOneShotEval) {
        debugPrint(
          '[Realism:Unified] One-shot eval for ${speaker.name} ($charId)',
        );
        await _evaluateOneShotCall(onChunk: handleChunk);
      } else {
        // Run the four evals AND the batched verifier pass — identical to the
        // (former) centralized 1:1 path, so EVERY speaker (host or group member)
        // gets the same double-checked realism. This is the parity unification.
        debugPrint(
          '[Realism:Unified] 4-call eval + verifier for ${speaker.name} ($charId)',
        );
        _realismEvals.beginCollectForBatchedVerification();
        await _fireStaggeredRealismEvals(handleChunk);
        await _realismEvals.finalizeBatchedRealismVerifications();

        final collected = _realismEvals.getCollectedForBatch();
        if (collected.isNotEmpty) {
          debugPrint(
            '[Realism:Unified] Verifying ${collected.length} eval(s) for '
            '${speaker.name}',
          );
          final items = collected
              .map(
                (p) => (
                  evalKind: p['kind'] as String,
                  rawOutput: p['raw'] as String,
                  sceneResponse: p['scene'] as String,
                  preState: null,
                  activeChar: _activeCharacter,
                  activeGroup: _activeGroup,
                  recentMessages: _messages,
                  promptText: p['prompt'] as String?,
                  injections: (p['injections'] as Map?)?.cast<String, String>(),
                  strictnessOverride: null,
                  maxPassesOverride: null,
                ),
              )
              .toList();
          final batchRes = await _realismVerifier.verifyBatch(items);
          await _realismEvals.applyBatchResults(batchRes);
        }
      }

      // Handle cancellation after the eval calls. The flag is deliberately
      // left set — the caller (sendMessage / _generateResponse) consumes it
      // and aborts generation (see the pre-eval check above).
      if (_realismEvalCancelled) {
        debugPrint(
          '[Realism:Unified] Evaluation cancelled during/after LLM calls for ${speaker.name}',
        );
        return;
      }

      // Harvest the now-updated scalar fields back into this speaker's
      // _groupRealism entry so prompt injection and UI see fresh values.
      // Group-only: the 1:1 host's scalars are the canonical store (persisted by
      // _saveChat below); the group-map writes no-op for the host anyway, and
      // reloading from the map is what nuked the host's state (see the load note above).
      if (_activeGroup != null) {
        _saveScalarsIntoGroupRealism(charId);
      }

      // Synthesize metadata for timeline / chips (best-effort, same as 1:1 path)
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['emotion_label'] = _characterEmotion;
      _pendingRealismMetadata!['realism_state'] = _captureRealismState(
        preTurn: preTurnVector,
      );

      if (_needsSimEnabled) {
        final needsDeltas = _needsSimulation.computeNeedsDeltasWithReasons(
          preTurnVector ?? const <String, int>{},
        );
        if (needsDeltas.isNotEmpty) {
          _pendingRealismMetadata!['needs_deltas'] = needsDeltas;
        }
      }

      _saveChat();
    } finally {
      // Always restore previous context and clear busy state
      _activeCharacter = previousActiveCharacter;
      _activeObjectives = previousObjectives;
      _evalChunkTimer?.cancel();
      _evalChunkTimer = null;
      _isEvaluatingRealism = false;
      notifyListeners();
    }
  }

  /// Loads the given group character's realism values from _groupRealism into
  /// the single-character scalar fields so the existing eval methods can
  /// operate on them during impersonation.
  void _loadGroupRealismIntoScalars(String charId) {
    // Relationship (affection/trust/fix/tiers etc) now via service load helper (uses the same _getGroup* internally via cbs).
    _relationshipService.loadRelationshipScalarsForSpeaker(charId);
    // Nsfw (arousal + cooldown + nsfwEnabled per char) via service (extends prior arousal-only for full group parity).
    // Note: group uses 'arousal' key (historical) vs snapshot 'arousalLevel' for compat.
    _nsfwService.loadNsfwScalarsForSpeaker(charId);

    _characterEmotion = _getGroupString(charId, 'emotion');
    _emotionIntensity = _getGroupString(
      charId,
      'emotionIntensity',
      defaultValue: 'moderate',
    );

    // Needs vector (if any persisted for this char)
    final needs = _getGroupNeeds(charId);
    if (needs.isNotEmpty) {
      _needsSimulation.restoreFromSnapshot({'vector': needs});
    } else if (_needsSimEnabled) {
      // Fresh start for a group member who has never had needs for this group chat.
      // Use full 100 to match 1:1 "new chat" behavior (prevents bleed perception).
      _needsSimulation.initializeFresh();
    }
  }

  /// Writes the current scalar realism fields back into the target group
  /// character's _groupRealism entry after an impersonated eval round.
  void _saveScalarsIntoGroupRealism(String charId) {
    // Relationship scalars (affection/long/trust/fix/tiers/spatial) now via service.
    _relationshipService.saveRelationshipScalarsToGroup(charId);
    // Nsfw scalars (arousal + cooldown + enabled) now via service (for group per-char persistence parity).
    // Note: group uses 'arousal' key (historical) vs snapshot 'arousalLevel' for compat.
    _nsfwService.saveNsfwScalarsToGroup(charId);

    if (_characterEmotion.isNotEmpty) {
      _setGroupRealismValue(charId, 'emotion', _characterEmotion);
    }
    if (_emotionIntensity.isNotEmpty) {
      _setGroupRealismValue(charId, 'emotionIntensity', _emotionIntensity);
    }

    // Persist current needs vector for this speaker
    if (_needsSimulation.vector.isNotEmpty) {
      _setGroupNeeds(charId, Map<String, int>.from(_needsSimulation.vector));
    }
  }

}
