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

/// Regen revert — rewind the rejected speaker to the pre-turn baseline.
///
/// 1:1 and group share this helper. Group impersonates the rejected speaker,
/// reverts, then saves back into `_groupRealism`. Continue is not this file.
extension ChatServiceRegenRevert on ChatService {
  void _revertRegenRealismBaseline({
    required ChatMessage lastMsg,
    required CharacterCard? regenGuest,
    required CharacterCard? regenSpeakerCard,
    required String regenSpeakerSid,
  }) {
    // Revert realism state from the rejected swipe and re-evaluate.
    // Guest messages carry no Realism/Needs state (regenGuest != null skips).
    //
    // GROUP parity: the revert must operate on the rejected SPEAKER's
    // _groupRealism entry, not on whichever member's state happens to be in
    // the scalar fields. Impersonate + load their map state (the same
    // load/save dance _evaluateRealismForUpcomingSpeaker uses), run the SAME
    // revert as 1:1, then persist the reverted scalars back to the map. The
    // per-speaker eval inside _generateResponse then replays decay + eval
    // from this clean baseline — previously nothing was reverted, so every
    // group regen stacked the new turn's deltas on top of the rejected
    // turn's, plus a second decay tick.
    final isGroupHostRegen =
        _activeGroup != null &&
        regenGuest == null &&
        regenSpeakerSid.isNotEmpty;
    // In a group, an unresolvable speaker (renamed/removed member) skips the
    // revert entirely — reverting the wrong member would corrupt THEIR state.
    final canRevertRealism = _activeGroup == null || isGroupHostRegen;

    CharacterCard? preRegenActiveCharacter;
    if (_realismEnabled && regenGuest == null && canRevertRealism) {
      if (isGroupHostRegen) {
        preRegenActiveCharacter = _activeCharacter;
        _activeCharacter = regenSpeakerCard;
        _loadGroupRealismIntoScalars(regenSpeakerSid);
      }
      // CRITICAL FIX: Find the baseline realism state from the previous accepted message.
      // We want to use the final state of the LAST ACCEPTED character message as our baseline,
      // not just blindly revert deltas and re-evaluate from scratch.
      // 1:1: one character, one lookback. GROUP: the per-speaker fields must
      // come from the rejected speaker's own last stamped message, while the
      // session-level clock baseline comes from the most recent stamped bot
      // message of ANY speaker (time is shared).
      Map<String, dynamic>? previousMessageState;
      Map<String, dynamic>? previousSessionState;
      if (_messages.length >= 2) {
        // Look back through messages to find the last bot message before the one we're regenerating
        for (int i = _messages.length - 1; i >= 0; i--) {
          if (!_messages[i].isUser && _messages[i].sender != 'System') {
            final meta = _messages[i].activeMetadata;
            if (meta != null && meta.containsKey('realism_state')) {
              final state = meta['realism_state'] as Map<String, dynamic>;
              previousSessionState ??= state;
              if (!isGroupHostRegen || _messages[i].sender == lastMsg.sender) {
                previousMessageState = state;
                debugPrint(
                  '[Realism:Regen] Found previous accepted message baseline state at message index $i',
                );
                break;
              }
            }
          }
        }
      }

      bool wasNudged = false;
      if (lastMsg.activeMetadata != null &&
          lastMsg.activeMetadata!['realism_state'] is Map) {
        wasNudged =
            lastMsg.activeMetadata!['realism_state']['time_nudged'] == true;
      }

      // Did we restore needs from the rejected message's OWN needs_pre_turn_vector
      // just below? That is the accurate "needs right before this turn" baseline
      // (always stamped: 1:1 in sendMessage pre-tick, group in the realism dance).
      // If so, the previous-accepted-message baseline restore further down must NOT
      // overwrite it — that snapshot's needs vector is the PREVIOUS turn's PRE-impact
      // needs, and clobbering with it silently reverted the last accepted turn's needs
      // deltas (e.g. a bath's +Hygiene snapping back to 0). The realism_state needs
      // snapshot stays a fallback only for messages with no needs_pre_turn_vector.
      bool restoredNeedsFromPreTurn = false;

      if (lastMsg.activeMetadata != null) {
        final bondDelta = lastMsg.activeMetadata!['bond_delta'] as int? ?? 0;
        final arousalDelta =
            lastMsg.activeMetadata!['arousal_delta'] as int? ?? 0;
        final trustDelta = lastMsg.activeMetadata!['trust_delta'] as int? ?? 0;

        if (bondDelta != 0) {
          // recordMilestone: false — undoing a rejected reply must not plant
          // reverse "Bond cooled…" story beats in Our Story (Living Time v1.5).
          _relationshipService.applyScoreDelta(
            -bondDelta,
            recordMilestone: false,
          );
        }
        if (trustDelta != 0) {
          _relationshipService.setTrustLevelForRevert(
            (_relationshipService.trustLevel - trustDelta).clamp(-100, 100),
          );
        }

        // Revert climax state if this response triggered refractory cooldown.
        // The climax checker stores the pre-climax arousal so we can restore it.
        final climaxTriggered =
            lastMsg.activeMetadata!['climax_triggered'] as bool? ?? false;
        if (climaxTriggered && _nsfwService.nsfwCooldownEnabled) {
          final preClimaxArousal =
              lastMsg.activeMetadata!['pre_climax_arousal'] as int? ?? 0;
          _nsfwService.setArousalLevel(preClimaxArousal);
          _nsfwService.setCooldownTurnsRemaining(0);
          _nsfwService.setCooldownTurnsTotal(0);
          debugPrint(
            '[Realism:Regen] Reverted climax state: arousal restored to $preClimaxArousal, cooldown cleared',
          );
        } else if (arousalDelta != 0 && _nsfwService.nsfwCooldownEnabled) {
          // Normal arousal delta revert (no climax involved)
          _nsfwService.setArousalLevel(
            (_nsfwService.arousalLevel - arousalDelta).clamp(-100, 100),
          );
        }

        // Needs pre-turn vector revert — mirrors the bond/trust/arousal delta
        // system so regen can undo the decay + fulfillment that ran for this
        // user turn, even when the previous message's realism_state snapshot
        // lacks a 'needs' entry (e.g. needs was enabled mid-chat).
        final preTurnNeeds =
            lastMsg.activeMetadata!['needs_pre_turn_vector'] as Map?;
        if (preTurnNeeds != null && _needsSimEnabled) {
          _needsSimulation.restoreFromSnapshot({
            'vector': Map<String, int>.from(preTurnNeeds),
          });
          restoredNeedsFromPreTurn = true;
          debugPrint(
            '[Realism:Regen] Restored needs vector from pre-turn snapshot on rejected message',
          );
        }
      }

      // CRITICAL FIX: Restore the baseline state from the previous accepted message.
      // This ensures the new regenerated message is evaluated against the correct baseline,
      // not from scratch which would produce wildly different realism values.
      if (previousMessageState != null) {
        // groupSpeakerId is what lets the revert rewind the two registers
        // that ride the group map rather than the scalar set — the hidden
        // inter-character feelings and the decay cadence. Without it a group
        // regen left both drifted, which is why repeated group regens
        // returned different bond/trust numbers while 1:1 regens returned
        // the same ones. Null in 1:1: there is no map, and the cadence there
        // is a scalar the same call restores.
        // Cadence (and other scalars) come from the previous accepted stamp.
        // Regen re-applies applyShortTermDecay below — that needs the
        // pre-this-turn counter, not the rejected stamp (which is already
        // post-decay). Overlaying lastMsg cadence then re-decaying skips or
        // double-counts the every-10 bond fire (hostile self-review).
        _relationshipService.restoreFromMessageState(
          previousMessageState,
          groupSpeakerId: isGroupHostRegen ? regenSpeakerSid : null,
        );
        // Feelings only (P1.10): post-gen keyword sweep mutates the map and
        // is never restamped, so lastMsg still holds pre-sweep feelings while
        // previousMessageState is an older same-speaker map.
        final rejectedMeta = lastMsg.activeMetadata?['realism_state'];
        final patch = rejectedTurnRewindPatch(
          rejectedMeta is Map ? rejectedMeta : null,
        );
        if (patch.isNotEmpty) {
          _relationshipService.restoreFromMessageState(
            patch,
            groupSpeakerId: isGroupHostRegen ? regenSpeakerSid : null,
          );
        }
        _characterEmotion =
            previousMessageState['characterEmotion'] as String? ??
            _characterEmotion;
        _emotionIntensity =
            previousMessageState['emotionIntensity'] as String? ??
            _emotionIntensity;

        _nsfwService.restoreNsfwFromMessageState(previousMessageState);

        // Needs simulation snapshot (clean port)
        // Guard + no enabled override: prevents stale resurrection on regen after toggle-off.
        // Only fall back to the previous accepted message's realism_state needs
        // vector when step 1 above found no needs_pre_turn_vector on the rejected
        // message. Otherwise this would clobber the accurate pre-turn baseline with
        // the previous turn's PRE-impact needs (the "Hygiene reverts on regen" bug).
        if (!restoredNeedsFromPreTurn &&
            previousMessageState.containsKey('needs') &&
            previousMessageState['needs'] is Map &&
            _needsSimEnabled) {
          final needsData = previousMessageState['needs'] as Map;
          if (needsData['vector'] is Map) {
            final vector = Map<String, int>.from(needsData['vector'] as Map);
            _needsSimulation.restoreFromSnapshot({'vector': vector});
          }
        }

        debugPrint(
          '[Realism:Regen] ✓ Restored baseline from previous accepted message: bond=${_relationshipService.affectionScore}, emotion=$_characterEmotion, trust=${_relationshipService.trustLevel}, arousal=${_nsfwService.arousalLevel}',
        );
      } else {
        debugPrint(
          '[Realism:Regen] ⚠ No previous message baseline found, continuing with current reverted state',
        );
      }

      // Session-level baseline (the shared story clock) comes from the most
      // recent stamped bot message of ANY speaker — identical to
      // previousMessageState in 1:1. The decay cadence is NOT session-level:
      // it is per-character, so it rides previousMessageState above instead.
      if (previousSessionState != null) {
        _timeService.restoreTimeForSwipeOrRegen(
          previousSessionState,
          wasNudged: wasNudged,
        );
      }
      // Clock suppression is an argument on Next Character only. Regen
      // rewinds above and then re-runs the scene-time eval with the
      // default (advance), so time does not walk backward.

      // ── Where they were BEFORE the reply being discarded ──────────────
      //
      // Last, so it wins: everything above rebuilds the baseline from the
      // PREVIOUS accepted message, and for spatial stance that is a
      // second-hand copy at best and missing entirely at worst. Posture is
      // written after generation, so the rejected message's own snapshot
      // was overwritten with where its reply left them — the receipt stamped
      // beside it (see kSpatialStancePreTurn) is the only surviving record
      // of where the turn began, and it belongs to THIS turn rather than
      // the one before it.
      //
      // It is also the only baseline the FIRST reply of a chat has. The
      // look-back above needs a previous accepted bot message carrying a
      // realism snapshot; on turn one there is only the greeting, and the
      // greeting is stamped on exactly one entry path (1:1 + startNewChat +
      // a card with no frontPorchExtensions). Every other opening — the
      // ordinary open-a-character path, any Front Porch or Stoop card, any
      // group — found nothing to restore and left the discarded reply's
      // position standing, so each reroll wrote the next attempt from a
      // place invented by the reply the user had just rejected. Two rerolls
      // from one point disagreed, which CLAUDE.md names as a rewind bug by
      // definition.
      //
      // 1:1 and group alike: the receipt rides the message, and in a group
      // the persist immediately below files the restored value into the
      // rejected speaker's own _groupRealism entry.
      final preTurnStance = lastMsg.activeMetadata?[kSpatialStancePreTurn];
      if (preTurnStance is String) {
        _relationshipService.setSpatialStance(preTurnStance);
        debugPrint(
          '[Realism:Regen] Rewound spatial stance to the pre-reply '
          'position: "${_relationshipService.spatialStance}"',
        );
      }
      final glanceMeta = lastMsg.activeMetadata;
      if (glanceMeta != null && glanceMeta.containsKey(kWithUserPreTurn)) {
        final pre = glanceMeta[kWithUserPreTurn];
        _relationshipService.setWithUser(pre is bool ? pre : null);
      }

      if (isGroupHostRegen) {
        // Persist the reverted baseline into the speaker's _groupRealism
        // entry and drop the impersonation. Decay + re-eval for the regen
        // turn happen inside _generateResponse via
        // _evaluateRealismForUpcomingSpeaker (forced to this speaker above),
        // exactly like the turn being replaced did.
        _saveScalarsIntoGroupRealism(regenSpeakerSid);
        _activeCharacter = preRegenActiveCharacter;
      }
    }
  }

  Future<void> _mergeOrRestoreRegenSwipe({
    required ChatMessage lastMsg,
    required CharacterCard? regenGuest,
    required Map<String, dynamic>? preservedRejectedMeta,
    required int rejectedSwipeIndex,
    required int preGenLen,
  }) async {
    final appendedReply =
        _messages.length > preGenLen &&
        !_messages.last.isUser &&
        _messages.last.sender != 'System';
    if (!appendedReply) {
      // The shell catch leaves the failed turn's EMPTY stream target in
      // place before the System banner — drop that ghost so the restored
      // reply doesn't sit next to a blank bubble of the same speaker.
      final ghostIdx = _messages.indexWhere(
        (m) => !m.isUser && m.sender != 'System' && m.text.isEmpty,
        preGenLen,
      );
      if (ghostIdx >= 0) _messages.removeAt(ghostIdx);
      _messages.insert(preGenLen, lastMsg);
      if (regenGuest == null) {
        _restoreRealismStateForSpeaker(lastMsg);
        // The pre-generation rewind above rolled pockets to the PRE-turn
        // record; with no new reply the message returns showing its
        // accepted text, so the pockets must return to the accepted
        // (post-turn) record too — same put-back contract as the two
        // realism-cancel points earlier in this method.
        _restorePocketsFromStamp(lastMsg, after: true);
      }
      notifyListeners();
      // Full rewrite: the abort inside _generateResponse already persisted
      // the shortened transcript, so an upsert alone cannot heal the row.
      await _saveChat(replaceAll: true);
      return;
    }
    if (_messages.isNotEmpty &&
        !_messages.last.isUser &&
        _messages.last.sender != 'System') {
      final newText = _messages.last.text;
      final newMetadata = _messages.last.activeMetadata != null
          ? Map<String, dynamic>.from(_messages.last.activeMetadata!)
          : null;
      final tempBefore = _messages.last.metadata?['pockets_before'];
      _messages.removeLast();
      if (tempBefore is Map) {
        lastMsg.metadata ??= {};
        lastMsg.metadata!['pockets_before'] = tempBefore;
      }
      lastMsg.swipes.add(newText);
      while (lastMsg.swipeDurations.length < lastMsg.swipes.length) {
        lastMsg.swipeDurations.add(0);
      }
      final newSwipeIndex = lastMsg.swipes.length - 1;
      if (preservedRejectedMeta != null && rejectedSwipeIndex >= 0) {
        while (lastMsg.swipeMetadata.length <= rejectedSwipeIndex) {
          lastMsg.swipeMetadata.add(null);
        }
        lastMsg.swipeMetadata[rejectedSwipeIndex] = preservedRejectedMeta;
      }
      while (lastMsg.swipeMetadata.length <= newSwipeIndex) {
        lastMsg.swipeMetadata.add(null);
      }
      lastMsg.swipeIndex = newSwipeIndex;
      // New swipe metadata only — prior swipes (incl. manual reprocess) stay
      // intact. newMetadata already carries this swipe's needs_deltas: the
      // chip attach inside _generateResponse is the one source of truth.
      if (newMetadata != null) {
        lastMsg.swipeMetadata[newSwipeIndex] = newMetadata;
      }
      _messages.add(lastMsg);
      // Host messages restore the active character's Realism/Needs from the
      // accepted swipe (in groups: the speaker's own _groupRealism entry);
      // guest messages carry none, so leave host state intact.
      if (regenGuest == null) _restoreRealismStateForSpeaker(lastMsg);
      await _saveChat();
      notifyListeners();

      // In group mode, advance the turn pointer past the regenerated speaker
      // so the next natural generation continues the correct rotation instead
      // of repeating the same character.
      if (_activeGroup != null) {
        // Same resolution rule: advancing past the WRONG member would make
        // the next natural turn repeat a character or skip one.
        final originalSpeaker = _resolveGroupSpeakerForMessage(lastMsg);
        if (originalSpeaker != null) {
          _groupManager?.advanceAfterRegeneration(originalSpeaker);
        }
      }
    }
  }
}
