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

/// Message reprocess / revert / regenerate flows — manualReprocessNeeds,
/// revertNeedsReprocess, regenerateLastMessage. These replay a turn with the
/// per-speaker realism dance (load → re-eval → save) and the time-travel
/// realism rollback. Extracted verbatim from `chat_service.dart` (zero behaviour
/// change) to shrink the god file; as `part of` it reaches the private services,
/// messages, and dance helpers exactly as before.
extension ChatServiceReprocess on ChatService {
  Future<bool> manualReprocessNeeds(int index, String critique) async {
    if (index < 0 || index >= _messages.length) return false;
    if (_isGenerating) return false;

    final msg = _messages[index];
    if (msg.isUser || msg.sender == 'System') return false;

    final meta = msg.activeMetadata;
    if (meta == null || !meta.containsKey('realism_state')) return false;

    final preState = meta['realism_state'];
    if (preState is! Map || preState['needs'] == null) return false;

    // A: entry guard (usable needs data) already passed; button in UI also checks now.

    final oldNeedsDeltas = <String, int>{};
    Map<String, dynamic>? originalNeedsDeltasForStash;
    if (meta.containsKey('needs_deltas')) {
      final oldMap = meta['needs_deltas'] as Map;
      originalNeedsDeltasForStash = Map<String, dynamic>.from(oldMap);
      for (final k in oldMap.keys) {
        if (oldMap[k] is Map && oldMap[k]['delta'] is num) {
          oldNeedsDeltas[k.toString()] = (oldMap[k]['delta'] as num).toInt();
        }
      }
    }

    // D: stash original deltas under pre_reprocess key (before any commit)
    final hasPrior = originalNeedsDeltasForStash != null;

    final bool isLast = index == _messages.length - 1;
    final bool isGroupNonObs = _activeGroup != null && !_observerMode;
    String? sid;
    CharacterCard? targetSpeakerCard;
    if (isGroupNonObs) {
      if (_groupCharacters.isEmpty) return false;
      targetSpeakerCard = _groupCharacters.firstWhere(
        (c) => c.name == msg.sender,
        orElse: () => _groupCharacters.first,
      );
      sid = _getCharacterIdFromCard(targetSpeakerCard);
    }

    // Snapshot the *active* live state *before* any historical/target prepare (for strict historical meta-only)
    final Map<String, int> preOpLive;
    String? preOpActiveSid;
    // Captured in BOTH modes, because every restore below is unconditional.
    // A group-only capture left this null for 1:1 chats, so the isLast
    // success path nulled the active character on every successful 1:1
    // reprocess: the chat page fell back to "No character selected." and the
    // trailing _saveChat no-oped (its null-character guard), dropping the
    // reprocess result. In a pure group this still correctly captures null.
    final CharacterCard? preActiveChar = _activeCharacter;
    if (isGroupNonObs) {
      preOpActiveSid = _getCurrentSpeakerIdForRealism();
      preOpLive = Map<String, int>.from(_getGroupNeeds(preOpActiveSid));
    } else {
      preOpLive = Map<String, int>.from(_needsSimulation.vector);
    }

    // Snapshot for rollback (target's at click time; used for last + compute baseline)
    final Map<String, int> livePreClick;
    if (isGroupNonObs && sid != null && sid.isNotEmpty) {
      livePreClick = Map<String, int>.from(_getGroupNeeds(sid));
    } else {
      livePreClick = Map<String, int>.from(_needsSimulation.vector);
    }

    // Group impersonation dance + load for prompt fidelity (personality/stance via getActiveCharacter in evaluate) + prepare scalar to msg pre.
    // For !isLast we still dance (to get correct prompt for that speaker's critique) but will strictly rollback live after.
    if (isGroupNonObs && sid != null && sid.isNotEmpty) {
      if (targetSpeakerCard != null) {
        _activeCharacter = targetSpeakerCard;
      }
      _loadGroupRealismIntoScalars(sid);
    }
    _needsSimulation.restoreFromSnapshot(preState['needs']);
    final Map<String, int> restoredPreVector = Map<String, int>.from(
      _needsSimulation.vector,
    );

    if (isLast) {
      _isVerifyingRealism = true;
      _verificationPass = 1;
      _verificationMaxPasses = 1;
      notifyListeners();
    }

    _pendingRealismMetadata = null;
    _realismEvalCancelled = false;
    final koboldForReprocess = _llmProvider?.koboldService;
    if (koboldForReprocess != null) {
      await koboldForReprocess.waitForIdle();
    }

    final bool reprocessOk = await _needsImpactEvaluator
        .reprocessWithUserCritique(msg.displayText, oldNeedsDeltas, critique);

    if (!reprocessOk) {
      // A: non-destructive: rollback to pre-op active live (historical leaves current active untouched)
      if (isGroupNonObs &&
          preOpActiveSid != null &&
          preOpActiveSid.isNotEmpty) {
        _loadGroupRealismIntoScalars(preOpActiveSid);
      } else if (isGroupNonObs && sid != null && sid.isNotEmpty) {
        _setGroupNeeds(sid, livePreClick); // fallback
      } else {
        _needsSimulation.restoreFromSnapshot({'vector': preOpLive});
      }
      // Unconditional: in a pure group the pre-op state IS null and the
      // impersonation must be dropped even on failure.
      _activeCharacter = preActiveChar;
      if (isLast) {
        _isVerifyingRealism = false;
        _pendingRealismMetadata = null;
        await _saveChat();
        notifyListeners();
      } else {
        _pendingRealismMetadata = null;
      }
      return false;
    }

    // Success path: commit metadata always (for the target msg)
    final updatedMeta = Map<String, dynamic>.from(meta);
    final computed = _needsSimulation.computeNeedsDeltasWithReasons(
      restoredPreVector,
    );
    updatedMeta['needs_deltas'] = computed;

    // Keep realism_state['needs'] aligned with manual corrections so swipe
    // navigation and regen do not resurrect a stale pre-reprocess vector.
    if (_needsSimEnabled && updatedMeta['realism_state'] is Map) {
      final postReprocessVector = isGroupNonObs && sid != null && sid.isNotEmpty
          ? Map<String, int>.from(_getGroupNeeds(sid))
          : Map<String, int>.from(_needsSimulation.vector);
      final rs = Map<String, dynamic>.from(updatedMeta['realism_state'] as Map);
      final needsSnap = <String, dynamic>{'vector': postReprocessVector};
      if (computed.isNotEmpty) {
        needsSnap['deltas'] = computed;
      }
      rs['needs'] = needsSnap;
      updatedMeta['realism_state'] = rs;
    }

    if (hasPrior) {
      updatedMeta['needs_deltas_pre_reprocess'] = originalNeedsDeltasForStash;
    }
    // D: record critique in verif meta (for history/tooltip)
    final verifMeta =
        (updatedMeta[RealismVerification.kMetaKey] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    verifMeta['reprocess_critique'] = critique;
    updatedMeta[RealismVerification.kMetaKey] = verifMeta;

    if (_pendingRealismMetadata != null) {
      for (final e in _pendingRealismMetadata!.entries) {
        updatedMeta[e.key] = e.value;
      }
    }

    msg.swipeMetadata[msg.swipeIndex] = updatedMeta;

    if (isLast) {
      // Persist live only for current last speaker
      if (isGroupNonObs && sid != null && sid.isNotEmpty) {
        _saveScalarsIntoGroupRealism(sid);
      }
      // Drop the impersonation. The group per-character state is already saved
      // to _groupRealism above; leaving _activeCharacter pointed at the
      // impersonated speaker leaked their card into everything that reads
      // _activeCharacter (verifier flags, needs strength, decay rates) until
      // the next dance overwrote it. Unconditional (not `!= null`-guarded): in
      // a pure group preActiveChar IS null and must be restored to null; for
      // 1:1 the capture above grabbed the current character, so this is the
      // no-op it always claimed to be.
      _activeCharacter = preActiveChar;
      _isVerifyingRealism = false;
      _pendingRealismMetadata = null;
    } else {
      // Historical: meta updated; strictly no live/group mutation left behind.
      // Transient onSaveChat may fire from temp apply (critique path); scalars rolled back; _saveChat here is only for target msg metadata.
      if (isGroupNonObs &&
          preOpActiveSid != null &&
          preOpActiveSid.isNotEmpty) {
        _loadGroupRealismIntoScalars(preOpActiveSid);
      } else if (!isGroupNonObs) {
        _needsSimulation.restoreFromSnapshot({'vector': preOpLive});
      }
      _activeCharacter = preActiveChar;
      _pendingRealismMetadata = null;
    }
    await _saveChat();
    notifyListeners();
    return true;
  }

  /// Revert a prior manual reprocess on the given message.
  /// Restores the stashed 'needs_deltas_pre_reprocess' into 'needs_deltas' (with reasons),
  /// rewinds live scalars *only if last* (historical: metadata-only update, live scalars/group untouched).
  /// Safe for 1:1 and group (speaker via msg.sender + dance on last).
  /// Returns true on success.
  Future<bool> revertNeedsReprocess(int index) async {
    if (index < 0 || index >= _messages.length) return false;
    if (_isGenerating) return false;
    final msg = _messages[index];
    final meta = msg.activeMetadata;
    if (meta == null || !meta.containsKey('needs_deltas_pre_reprocess')) {
      return false;
    }
    final preState = meta['realism_state'];
    if (preState is! Map || preState['needs'] == null) return false;

    final stashedDeltasMap = meta['needs_deltas_pre_reprocess'] as Map;
    final oldDeltas = <String, int>{};
    stashedDeltasMap.forEach((k, v) {
      if (v is Map && v['delta'] is num) {
        oldDeltas[k.toString()] = (v['delta'] as num).toInt();
      }
    });

    final bool isLast = index == _messages.length - 1;
    final bool isGroupNonObs = _activeGroup != null && !_observerMode;
    String? sid;
    CharacterCard? targetSpeakerCard;
    if (isGroupNonObs) {
      if (_groupCharacters.isEmpty) return false;
      targetSpeakerCard = _groupCharacters.firstWhere(
        (c) => c.name == msg.sender,
        orElse: () => _groupCharacters.first,
      );
      sid = _getCharacterIdFromCard(targetSpeakerCard);
    }

    // Snapshot pre-op active for the restores below (both modes — see the
    // matching capture note in manualReprocessNeeds).
    final CharacterCard? preActiveChar = _activeCharacter;
    Map<String, int> preOpLive = {};
    String? preOpSid;
    if (isGroupNonObs) {
      preOpSid = _getCurrentSpeakerIdForRealism();
      preOpLive = Map<String, int>.from(_getGroupNeeds(preOpSid));
    } else {
      preOpLive = Map<String, int>.from(_needsSimulation.vector);
    }

    // Dance + prepare only if we will keep the effect (isLast); for historical we temp dance but rollback
    if (isGroupNonObs && sid != null && sid.isNotEmpty) {
      if (targetSpeakerCard != null) _activeCharacter = targetSpeakerCard;
      _loadGroupRealismIntoScalars(sid);
    }
    _needsSimulation.restoreFromSnapshot(preState['needs'] as Map);

    if (oldDeltas.isNotEmpty) {
      String? reasonToRestore;
      final values = (stashedDeltasMap as Map?)?.values ?? const [];
      for (final v in values) {
        if (v is Map &&
            v['reason'] is String &&
            (v['reason'] as String).isNotEmpty) {
          reasonToRestore = v['reason'] as String;
          break;
        }
      }
      _needsSimulation.applySceneImpact(
        NeedsImpact(deltas: oldDeltas, reason: reasonToRestore),
      );
    }

    final updated = Map<String, dynamic>.from(meta);
    updated['needs_deltas'] = stashedDeltasMap;
    updated.remove('needs_deltas_pre_reprocess');
    if (_needsSimEnabled && updated['realism_state'] is Map) {
      final postRevertVector = isGroupNonObs && sid != null && sid.isNotEmpty
          ? Map<String, int>.from(_getGroupNeeds(sid))
          : Map<String, int>.from(_needsSimulation.vector);
      final rs = Map<String, dynamic>.from(updated['realism_state'] as Map);
      final needsSnap = <String, dynamic>{'vector': postRevertVector};
      if (stashedDeltasMap.isNotEmpty) {
        needsSnap['deltas'] = stashedDeltasMap;
      }
      rs['needs'] = needsSnap;
      updated['realism_state'] = rs;
    }
    msg.swipeMetadata[msg.swipeIndex] = updated;

    if (isLast) {
      if (isGroupNonObs && sid != null && sid.isNotEmpty) {
        _saveScalarsIntoGroupRealism(sid);
      }
      // Drop the impersonation set by the dance above — same leak (and same
      // fix) as manualReprocessNeeds' isLast path; this flow was missed when
      // that one was fixed. No-op for 1:1 (no dance ran).
      _activeCharacter = preActiveChar;
    } else {
      // Historical meta-only: rollback live + char, do not persist to group for this op
      if (isGroupNonObs && preOpSid != null && preOpSid.isNotEmpty) {
        _loadGroupRealismIntoScalars(preOpSid);
      } else if (!isGroupNonObs) {
        _needsSimulation.restoreFromSnapshot({'vector': preOpLive});
      }
      _activeCharacter = preActiveChar;
    }

    await _saveChat();
    notifyListeners();
    return true;
  }

  /// Regenerate the main character's (host's) most recent message when it has
  /// been buried under Scene Guest (Lite NPC) chime-in replies — the case the
  /// last-message-only [regenerateLastMessage] button can no longer reach (the
  /// guest spoke last). The guest replies were reactions to the host text we are
  /// about to discard, so they are removed from the chat (UI + context) first;
  /// the host message is then regenerated as a new swipe via
  /// [regenerateLastMessage] (so realism is reverted to the previous accepted
  /// baseline exactly as for a normal regen — no parallel logic); finally the
  /// guest chime gate is re-run against the NEW host reply, so a guest speaks
  /// again only if it is still warranted (mention / relevance), never blindly.
  ///
  /// When the host message is already last (no trailing guests) this simply
  /// delegates to [regenerateLastMessage].
  Future<void> regenerateMainCharacter() async {
    if (_messages.isEmpty || _isGenerating || _guestBusy) return;

    // Walk back past the trailing guest replies to the host message beneath them.
    int hostIndex = -1;
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.isUser || m.sender == 'System') return; // user/System tail — nothing to regen
      if (!_isGuestAuthoredMessage(m)) {
        hostIndex = i;
        break;
      }
    }
    if (hostIndex < 0) return; // only guest messages present — no host to regen

    // Host already last → plain regen (no guests to pop).
    if (hostIndex == _messages.length - 1) {
      await regenerateLastMessage();
      return;
    }

    // Reconstruct the user text that prompted the host turn for the re-chime gate.
    String userText = '';
    for (int i = hostIndex - 1; i >= 0; i--) {
      if (_messages[i].isUser) {
        userText = _messages[i].text;
        break;
      }
    }

    // Remove the now-stale trailing guest replies from UI + context, then regen
    // the (now last) host message and re-run the chime gate on the new reply.
    _messages.removeRange(hostIndex + 1, _messages.length);
    await _saveChat();
    notifyListeners();
    await regenerateLastMessage();
    await _maybeRunSceneGuestChimeIns(userText: userText);
  }

  Future<void> regenerateLastMessage() async {
    if (_messages.isEmpty || _isGenerating || _guestBusy) return;

    // Check if the last message is from the character
    if (!_messages.last.isUser && _messages.last.sender != 'System') {
      // Instead of removing the message, we generate a new swipe
      // Temporarily remove the last message so the prompt doesn't include it
      final lastMsg = _messages.removeLast();
      // Timeline integrity: the regen replaces this position's active
      // content — journal cards citing it (or anything after) are phantom
      // (smoke-test bug 2026-07-21). regenerateMainCharacter's guest-pop
      // path is covered too: it delegates here with an even lower position.
      _invalidateJournalFrom(_messages.length);
      // Is this a Scene Guest message? If so the whole regen must stay a
      // parity-safe GUEST turn: skip every Realism/Needs revert + re-eval below
      // and regenerate spoken as the guest (guestSpeaker), exactly like the
      // normal guest turn path. A host message keeps the existing behaviour.
      final regenGuest = _sceneGuestForMessage(lastMsg);
      // If the message was authored by a guest who has since LEFT the scene (or
      // had their card deleted), we can neither regenerate as them nor run the
      // host realism block on their text (that would perturb the host's
      // bond/trust/emotion/needs from guest-authored content). Refuse cleanly.
      if (regenGuest == null && _isGuestAuthoredMessage(lastMsg)) {
        _messages.add(lastMsg); // put it back untouched
        notifyListeners();
        _setGuestStatus(
          'Can’t regenerate "${lastMsg.sender}" — they have left the scene.',
          isError: true,
        );
        return;
      }
      // Snapshot the rejected swipe's metadata (e.g. manual needs reprocess) before
      // we add a new swipe — regen must not clobber prior swipe timelines.
      final rejectedSwipeIndex = lastMsg.swipeIndex;
      Map<String, dynamic>? preservedRejectedMeta;
      if (rejectedSwipeIndex >= 0) {
        if (rejectedSwipeIndex < lastMsg.swipeMetadata.length &&
            lastMsg.swipeMetadata[rejectedSwipeIndex] != null) {
          preservedRejectedMeta = Map<String, dynamic>.from(
            lastMsg.swipeMetadata[rejectedSwipeIndex]!,
          );
        } else if (lastMsg.activeMetadata != null) {
          preservedRejectedMeta = Map<String, dynamic>.from(
            lastMsg.activeMetadata!,
          );
        }
      }
      notifyListeners();

      // Resolve the rejected turn's speaker once (exact name match) — used to
      // force the turn manager AND to target the realism revert below. If the
      // member was renamed/removed, BOTH sites skip rather than fall back to
      // the first member: forcing or reverting the wrong character corrupts
      // that character's state and attribution.
      CharacterCard? regenSpeakerCard;
      String regenSpeakerSid = '';
      if (_activeGroup != null && regenGuest == null) {
        final idx = _groupCharacters.indexWhere(
          (c) => c.name == lastMsg.sender,
        );
        if (idx >= 0) {
          regenSpeakerCard = _groupCharacters[idx];
          regenSpeakerSid = _getCharacterIdFromCard(regenSpeakerCard);
        }
      }

      // In group mode, force the turn manager to the *original* speaker of the
      // removed message before generation. This prevents regen from picking a
      // different character (the core of the "speaker changed after regen" bug).
      if (regenSpeakerCard != null) {
        _groupManager?.setNextSpeaker(regenSpeakerCard);
      }

      // Roll back objective mutations recorded for the rejected turn (eval
      // proposals + completion-check side effects) BEFORE the eval replay, so
      // the new turn re-derives objectives from a clean baseline instead of
      // stacking on the invalidated turn's (and dedup can't suppress a fresh
      // proposal because the rejected turn's copy still exists). Runs with or
      // without realism (completion checks also run realism-off); id-addressed
      // ops keep 1:1 and group identical. Guest turns never touch objectives.
      if (regenGuest == null) {
        await _revertObjectiveTurnOps(lastMsg);
      }

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
                if (!isGroupHostRegen ||
                    _messages[i].sender == lastMsg.sender) {
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
          final moodDelta = lastMsg.activeMetadata!['mood_delta'] as int? ?? 0;
          final arousalDelta =
              lastMsg.activeMetadata!['arousal_delta'] as int? ?? 0;
          final trustDelta =
              lastMsg.activeMetadata!['trust_delta'] as int? ?? 0;

          if (bondDelta != 0) {
            // recordMilestone: false — undoing a rejected reply must not plant
            // reverse "Bond cooled…" story beats in Our Story (Living Time v1.5).
            _relationshipService.applyScoreDelta(
              -bondDelta,
              recordMilestone: false,
            );
          }
          // Session-level mood cadence: 1:1 zeroes it here as an intermediate
          // (the baseline restore below then sets the real value and the 1:1
          // tail re-ticks). Group regen neither restores nor re-ticks the
          // counter — the rejected turn's tick stands — so zeroing here would
          // permanently reset the cadence. Leave it untouched for groups.
          if (moodDelta != 0 && !isGroupHostRegen) {
            _moodDecayCounter = 0;
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
          _relationshipService.restoreFromMessageState(previousMessageState);
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

        // Session-level baseline (the shared clock + mood-decay cadence) comes
        // from the most recent stamped bot message of ANY speaker — identical
        // to previousMessageState in 1:1. Group regen skips the mood counter:
        // groups tick mood decay in sendMessage (not replayed on regen), so
        // the rejected turn's tick correctly stands for the replacement turn.
        if (previousSessionState != null) {
          if (!isGroupHostRegen) {
            _moodDecayCounter =
                previousSessionState['moodDecayCounter'] as int? ??
                _moodDecayCounter;
          }
          _timeService.restoreTimeForSwipeOrRegen(
            previousSessionState,
            wasNudged: wasNudged,
          );
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

      // 1:1 only: replay decay + the realism eval inline here (groups replay
      // via the per-speaker dance inside _generateResponse).
      if (_realismEnabled && _activeGroup == null && regenGuest == null) {
        // Set UI streaming state
        _isEvaluatingRealism = true;
        _realismEvalStreamText = '';
        notifyListeners();

        void handleChunk(String chunk) {
          _realismEvalStreamText += chunk;
          // Debounce: coalesce rapid token arrivals into one rebuild per 150 ms
          _evalChunkTimer?.cancel();
          _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
            try {
              notifyListeners();
            } catch (_) {
              // Widget was deactivated — timer fired after navigation
            }
          });
        }

        // Apply decay and cooldown — mirrors the normal path (lines 3933-3937).
        // This ensures _needsVector differs from the saved pre-turn vector
        // so post-generation deltas are non-zero.
        _applyMoodDecay();
        _needsSimulation.tickDecay();
        _nsfwService.decrementCooldownIfActive();

        // Record the (restored) needs baseline as the pre-turn vector BEFORE
        // generation so the post-generation checks can compute proper deltas.
        if (_needsSimEnabled && _needsSimulation.vector.isNotEmpty) {
          _pendingRealismMetadata ??= {};
          _pendingRealismMetadata!['needs_pre_turn_vector'] =
              Map<String, int>.from(_needsSimulation.vector);
        }

        if (_storageService.realismSettings.realismOneShotEval) {
          await _evaluateOneShotCall(onChunk: handleChunk);
        } else {
          _realismEvals.beginCollectForBatchedVerification();
          await _fireStaggeredRealismEvals(handleChunk);
          await _realismEvals.finalizeBatchedRealismVerifications();

          // Mirror of the primary send path: apply the one director batch (or the cheap
          // accepted-originals path) so relationship/emotional/narrative deltas and side
          // effects (bond/trust/arousal chips, fixation, autonomous objectives, emotion)
          // are produced for swiped/regenerated assistant messages too.
          final collected = _realismEvals.getCollectedForBatch();
          if (collected.isNotEmpty) {
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
                    injections: (p['injections'] as Map?)
                        ?.cast<String, String>(),
                    strictnessOverride: null,
                    maxPassesOverride: null,
                  ),
                )
                .toList();
            final batchRes = await _realismVerifier.verifyBatch(items);
            await _realismEvals.applyBatchResults(batchRes);
          }
        }

        // Check for cancellation after evals complete
        if (_realismEvalCancelled) {
          debugPrint(
            '[Realism] Evaluation cancelled during regenerate, aborting',
          );
          _realismEvalCancelled = false;
          _evalChunkTimer?.cancel();
          _evalChunkTimer = null;
          _isEvaluatingRealism = false;
          notifyListeners();
          return;
        }

        // Cancel any pending debounce notify before closing the overlay
        _evalChunkTimer?.cancel();
        _evalChunkTimer = null;
        _isEvaluatingRealism = false;
        notifyListeners();
      }

      // In group mode the per-speaker realism eval (and its metadata / needs deltas)
      // happens inside _generateResponse via _evaluateRealismForUpcomingSpeaker
      // for the correctly-forced speaker. Skip the 1:1 scalar synthesis here.
      Map<String, int>? regenPreTurn;
      Map<String, dynamic>? needsDeltas;
      if (_activeGroup == null && regenGuest == null) {
        // Save pre-turn vector BEFORE _generateResponse (which clears
        // _pendingRealismMetadata).
        regenPreTurn =
            _pendingRealismMetadata?['needs_pre_turn_vector']
                as Map<String, int>?;

        // Synthesize metadata after all regen evals complete — mirrors the
        // normal path (line 4020) so emotion_label and realism_state are in
        // _pendingRealismMetadata before _generateResponse consumes it.
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata!['emotion_label'] = _characterEmotion;
        _pendingRealismMetadata!['realism_state'] = _captureRealismState(
          preTurn: regenPreTurn,
        );

        // If cancellation was requested during realism evaluation, abort generation
        if (_realismEvalCancelled) {
          _realismEvalCancelled = false;
          notifyListeners();
          return;
        }
      }

      // Invalidate ONNX cache for the new response (delegated)
      _expressionService.invalidateOnnxCacheForNewResponse();

      // Generate into a new message — it will be appended by _generateResponse.
      // For a guest message we pass guestSpeaker so the new swipe is spoken as
      // the guest and the entire Realism/Needs post-gen block is skipped (the
      // `guestSpeaker == null` guard). For a host message regenGuest is null and
      // this is the unchanged host path: _generateResponse runs the post-gen
      // needs checks (climax, sexual, daily, fulfillment) that modify the needs
      // vector, so we compute needs_deltas AFTER generation below.
      await _generateResponse(GenerationMode.normal, guestSpeaker: regenGuest);

      // Compute needs_deltas AFTER generation so the post-generation checks
      // are reflected. This mirrors the normal generation path (line ~4053).
      // Apply directly to the message since _pendingRealismMetadata was consumed.
      // (For groups, the per-speaker path inside generate already attached the
      // correct per-character needs_deltas; we only compute scalar here for 1:1.)
      if (_activeGroup == null &&
          regenGuest == null &&
          _needsSimEnabled &&
          _needsSimulation.vector.isNotEmpty) {
        needsDeltas = _needsSimulation.computeNeedsDeltasWithReasons(
          regenPreTurn ?? const <String, int>{},
        );
      }

      // After generation, merge the new response as a swipe on the original message
      if (_messages.isNotEmpty &&
          !_messages.last.isUser &&
          _messages.last.sender != 'System') {
        final newText = _messages.last.text;
        final newMetadata = _messages.last.activeMetadata != null
            ? Map<String, dynamic>.from(_messages.last.activeMetadata!)
            : null;
        _messages.removeLast();
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
        // New swipe metadata only — prior swipes (incl. manual reprocess) stay intact.
        if (needsDeltas != null && needsDeltas.isNotEmpty) {
          lastMsg.swipeMetadata[newSwipeIndex] = {
            ...(newMetadata ?? {}),
            'needs_deltas': needsDeltas,
          };
        } else if (newMetadata != null) {
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
          final originalSpeaker = _groupCharacters.firstWhere(
            (c) => c.name == lastMsg.sender,
            orElse: () => _groupCharacters.first,
          );
          _groupManager?.advanceAfterRegeneration(originalSpeaker);
        }
      }
    } else if (_messages.last.isUser) {
      // The last message is the user's prompt (e.g. the AI reply was deleted),
      // so there is no swipe to add — generate a fresh response from it. Mirrors
      // triggerNextCharacter()/the normal send path (_generateResponse consumes
      // no new user turn, so needs decay is NOT re-ticked — that already ran
      // when the user turn was first sent). Applies identically to 1:1 and group.
      await _generateResponse(GenerationMode.normal);
    }
  }
}
