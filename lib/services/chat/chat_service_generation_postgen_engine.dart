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

/// Realism/Needs post-gen family plus Journal/Growth/periodic.
/// Finalize chrome (sanitize, lorebook, first save, TTS) stays on
/// [ChatServiceGenerationPostGen]. Continue scores new text only;
/// asContinuation keeps pockets_before; Continue does not tick here —
/// the clock helper already owns that.
extension ChatServiceGenerationPostGenEngine on ChatService {
  Future<void> _runPostGenEngineAndPeriodic(
    _GenTurn t,
    String newPart,
    String finalResponse,
  ) async {
    // Phase 2: Update hidden inter-character feelings for the speaker who
    // just responded, based on what was said in the recent exchange.
    // This makes the invisible tracking react to actual dialogue.
    if (_activeGroup != null &&
        !_observerMode &&
        finalResponse.isNotEmpty &&
        // Same one-exchange rule as the two gates around it. This is a
        // keyword heuristic over the recent text, and after a Continue
        // the first half of the reply is still in that text — so the
        // same phrases scored the same feelings a second time.
        t.mode != GenerationMode.continue_) {
      // Use the ACTUAL speaker of this turn, not a by-name lookup with a
      // first-member fallback — duplicate display names would otherwise
      // route this member's inter-character feelings to the wrong card.
      final speakerId = _getCharacterIdFromCard(t.speakingCharacter);
      if (speakerId.isNotEmpty) {
        _relationshipService.updateInterCharacterFeelingsFromRecentExchange(
          speakerId,
        );
        // (old checkpoint call removed in v30) // persist the hidden relationship changes
      }
    }

    // For group non-observer turns, temporarily re-impersonate the speaker of the *just generated*
    // response so the post-gen needs checks (now _runPostGenNeedsChecks thin to
    // _needsImpactEvaluator) use the correct _activeCharacter (for name, personality/stance
    // in the consolidated needs impact prompt). The pre-speaker-eval left the *scalars*
    // (incl. needs vector) loaded for this speaker but restored the _activeCharacter pointer
    // to the prior speaker; the thin delegate relies on the pointer for cbs. We restore the
    // pointer after the checks (scalars remain correct for the persist below).
    CharacterCard? prePostActiveChar;
    // The awaited post-gen critical section: mutates _activeCharacter,
    // the needs scalars and _groupRealism across two awaits
    // (_isPostGenerating has been up since the last token landed).
    // The try/finally is not decoration: if _runPostGenNeedsChecks
    // throws, the inline restore below is skipped and the next turn's
    // save would write to the wrong member.
    try {
      await _openWorkerLane();
      if (_activeGroup != null && !_observerMode) {
        prePostActiveChar = _activeCharacter;
        _activeCharacter = t.speakingCharacter;
        final sid = _getCharacterIdFromCard(t.speakingCharacter);
        if (sid.isNotEmpty) {
          _loadGroupRealismIntoScalars(sid);
        }
      }

      // On Continue the SAME family runs on the NEW text only — an
      // incremental extension of the exchange, not a second scoring of
      // it. The blanket skip this replaces (2026-08-12) existed because
      // re-reading the FULL reply applied the first half's deltas a
      // second time; scoring only the continuation makes a double-apply
      // impossible by construction while events the user paid a
      // Continue for — they set the keys down, move to the swing,
      // finishes the meal — finally reach the bookkeeping. The evals
      // keep full context either way: each gets recentExchange(), and
      // the write-back above already put the whole continued reply into
      // the last message, so the fragment is never read blind.
      // Arithmetic stays exact: needs_pre_turn_vector + re-computed
      // chips still equals the live vector (the chip helper measures
      // live-minus-stamp, so the merge is free), and pockets keeps the
      // ORIGINAL pre-turn stamp so regen/tail-delete rewind to the true
      // base (see _runPocketsPass's asContinuation).
      // Present-guest Continue sets guestSpeaker before _GenTurn, so
      // this whole block is skipped. Departed-guest Continue refuses
      // before generating. The empty scoredReply is leftover belt if
      // a guest-authored tail ever reaches here with guestSpeaker null.
      final scoredReply = t.mode == GenerationMode.continue_
          ? (_isGuestAuthoredMessage(t.streamTarget) ? '' : newPart.trim())
          : finalResponse;
      if (scoredReply.isNotEmpty) {
        // The needs-impact eval and the fused reply-facts fetch run
        // CONCURRENTLY (same pattern as the pre-generation 4-eval block,
        // same stagger so KoboldCpp's FIFO queue sees them in intended
        // order). They are independent by construction: needs writes the
        // needs vector; the prefetch only READS stance/emotion/pockets to
        // build its prompt and parks raw text — the passes that apply it
        // run after both complete. On a remote backend this makes the
        // post-gen phase cost the slower of the two calls, not the sum.
        //
        // The fused fetch: when two or more of the three bookkeeping
        // passes below (climax, pockets, posture) are live, ONE call
        // answers all of them and each pass consumes its slice through
        // its own unchanged parser. With fewer than two live it is a
        // no-op and each pass fires its own call exactly as before. See
        // ReplyFactsEval for the composition rules.
        try {
          await Future.wait([
            _runPostGenNeedsChecks(scoredReply),
            Future<void>.delayed(
              _kEvalDispatchStagger,
            ).then((_) => _prefetchReplyFacts(scoredReply)),
          ]);
        } catch (e) {
          if (!_postGenAbortRequested) rethrow;
        }
        if (_postGenAbortRequested) {
          _replyFactsRaw = null;
        } else {
          // Afterglow. Reads the reply that was just written, which is why
          // it lives here and not on the pre-generation judges. On Continue
          // it reads only the new text — a climax the first half already
          // registered is not re-claimed by its aftermath, and one the
          // continuation adds finally counts.
          await _runClimaxPass(scoredReply);
          // Pockets & Wardrobe — its own pass; answers to its own switch
          // and nothing else. asContinuation preserves the message's
          // original pockets_before stamp (the turn's true pre-state) and
          // appends receipts instead of replacing them.
          await _runPocketsPass(
            scoredReply,
            asContinuation: t.mode == GenerationMode.continue_,
          );
          // Spatial stance — where this reply LEFT them. Third of the same
          // family, and it belongs here for the identical reason: a
          // position the character establishes in their own words cannot be
          // known by a judge that ran before those words existed. It used
          // to ride the pre-generation scene-time eval, which is why
          // characters teleported: the prompt asserted a position derived
          // from the previous exchange while the reply had already moved
          // them somewhere else. Maintainer ruling 2026-08-08. Skipped on
          // Continue with its siblings — a continuation is the same
          // exchange, and re-reading it would just re-answer the same
          // question at the price of another call.
          //
          // The result is picked up by the group persist below
          // (spatialStance rides saveRelationshipScalarsToGroup), by the
          // snapshot restamp, and by the single persist that closes this
          // block, so 1:1 and group store it identically.
          //
          // AWAITED, and therefore inside the settling window that greys the
          // composer. That cost was weighed and kept: the value this call
          // produces is read by the NEXT prompt's "Position:" line, so a
          // fire-and-forget version would race the user's next send and hand
          // the reply the position from the exchange before — the exact
          // teleport the pass was moved here to stop. It would also race the
          // `_saveChat` below, putting the write back outside any save and
          // recreating the bug this block was rewritten to fix. Same
          // reasoning, same phase, same awaiting as its two siblings above.
          {
            final fused = _replyFactsRaw;
            if (fused != null) {
              // The fused call already asked "where did this reply leave
              // them" — consume its answer through the ONE posture parser
              // instead of paying a second call. An absent or unparseable
              // answer skips, exactly as a failed standalone pass does:
              // the stance keeps its last value.
              final posture = TimeService.parsePosture(fused);
              if (posture != null) {
                _relationshipService.setSpatialStance(posture);
              }
              debugPrint(
                '[Realism:Posture] ${_relationshipService.spatialStance} '
                '(fused reply-facts)',
              );
            } else {
              await _evaluatePhysicalStateCall(postureOnly: true);
            }
          }
          // Glance only. After posture so the judge can read where they
          // already are. Not fused with posture — that mix is the teleport.
          await _runWithUserPass(scoredReply);
          // Consumed — the carrier must never outlive the passes that read
          // it, or a stale answer could feed the next turn's bookkeeping.
          _replyFactsRaw = null;
        }
      }

      // Clock decide BEFORE restamp so the snapshot carries the time
      // the NEXT speaker will be told (bucket brigade). Named-clock
      // reconcile still runs inside the restamp. Skip when regen
      // aborted this scoring — the rejected reply must not tick.
      if (!_postGenAbortRequested) {
        await _maybeAdvanceStoryClockAfterReply(t);

        // Keep this message's realism_state snapshot TRUTHFUL now that the
        // post-gen checks have run — needs vector AND the NSFW scalars a
        // climax just changed. See the helper for the two bugs this
        // prevents (hygiene snap-back; climax erased by the regen merge).
        await _restampRealismSnapshotPostGen(t.streamTarget);

        if (prePostActiveChar != null) {
          _activeCharacter = prePostActiveChar;
        }

        // For group non-observer, persist the post-scene + long-gen-decay needs changes (and any
        // other scalars mutated by the checks) back into _groupRealism for this speaker. This is
        // what makes sidebar member cards + getNeedsForGroupCharacter() + future loads see the
        // effects of the just-generated response. (Pre-eval saved the pre-turn state for bond/etc;
        // this captures the *response* effects on needs.)
        if (_activeGroup != null &&
            !_observerMode &&
            finalResponse.isNotEmpty &&
            _messages.isNotEmpty) {
          // The ACTUAL speaker of this turn — not a by-name lookup with a
          // first-member fallback (duplicate display names would persist the
          // critical scalar save to the wrong member's _groupRealism entry).
          final sid = _getCharacterIdFromCard(t.speakingCharacter);
          if (sid.isNotEmpty) {
            _saveScalarsIntoGroupRealism(sid);
          }
        }

        // Per-message needs chips for whoever just spoke. Lives here so
        // EVERY speaker gets them (group auto-advance, /speak, chime-ins)
        // — and regens too: a regen replays the turn in normal mode, and
        // the swipe-merge copies these chips onto the accepted swipe.
        // The ONE chip source. Continue re-attaches whenever its
        // incremental pass ran: the helper measures live-vector minus the
        // message's own needs_pre_turn_vector, so the recomputed chip IS
        // the merged whole-turn delta — stale first-half chips would
        // misreport the turn the moment the continuation moved a need.
        if (t.mode == GenerationMode.normal ||
            (t.mode == GenerationMode.continue_ && scoredReply.isNotEmpty)) {
          _attachNeedsDeltaChipToLastMessage();
        }

        // ── The post-generation phase's ONE persist ────────────────────
        // Everything above this line writes to memory only: the needs
        // vector, the climax/arousal scalars, pockets, the spatial stance,
        // the restamped `realism_state` snapshot, the per-member
        // `_groupRealism` entry and the chips. The `_saveChat()` near the
        // top of this method ran BEFORE all of it — it exists to get the
        // reply text on disk before four eval round-trips, not to carry
        // their results.
        //
        // Until 2026-08-08 the only save that could follow this block was
        // the one hidden inside _attachNeedsDeltaChipToLastMessage, which
        // returns on its first line when Needs is off. So on the ordinary
        // 1:1 path with Needs off NOTHING was written after the passes ran:
        // the session row, the message snapshot and the group blob all kept
        // the PREVIOUS turn's spatial stance, and the character teleported
        // back one exchange on every reload. It also meant a user's answer
        // to "do I want the Sims needs simulation?" silently decided
        // whether their position survived — two unrelated features wired
        // together (docs/design/feature-independence.md).
        //
        // Moving the save out of the chip helper and putting it here costs
        // the same one write per turn it always did, and now it covers
        // everything the phase produced instead of one feature's slice.
        // A continuation persists too whenever its incremental pass ran —
        // the needs/climax/pockets/stance it just wrote would otherwise
        // ride memory only until some later turn happened to save.
        if (t.mode != GenerationMode.continue_ || scoredReply.isNotEmpty) {
          await _saveChat();
          notifyListeners();
        }
      }
    } finally {
      await _closeWorkerLane();
      // Unconditional pointer restore on a throw. The settling flag is
      // cleared in the OUTER finally so guest turns, stale epochs and
      // earlier errors are covered too.
      if (prePostActiveChar != null) {
        _activeCharacter = prePostActiveChar;
      }
    }

    // [EvalTraffic]: the turn's secondary-call tally — everything since
    // the last flush (pre-gen judges, post-gen passes). Printed before
    // the fire-and-forget passes launch so their spend lands in the next
    // turn's `background` line instead of muddying this one.
    final turnTraffic = EvalTraffic.current.flushTurn();
    if (turnTraffic != null) debugPrint(turnTraffic);

    // Journal maintenance pass if due (fire-and-forget): memory cards +
    // recap in one call. Card ownership is derived from the window's
    // message characterIds (immune to the prePostActiveChar restore
    // dance above); only the recap voice is best-effort at trigger time
    // in group non-obs (same caveat the old summary had).
    // Skip when regen aborted this scoring — do not diary a rejected reply.
    if (!_postGenAbortRequested) {
      _maybeRunJournalPass();

      // Growth pass if due (fire-and-forget): ring ops per owner —
      // members AND 1:1 scene guests who spoke in the window (guest
      // growth rides this shared pass; there is no per-guest trigger).
      // Cursor-based like the journal, so it is naturally regen-safe.
      _maybeRunGrowthPass();

      // Promise/debt ledger (Train B) — fire-and-forget on new turns only.
      // Keyword gate + open-list gate live inside the service so most
      // turns cost nothing. Regen/continue never invent commitments.
      if (t.mode == GenerationMode.normal) {
        _maybeRunPromiseDebtPass();
      }

      // Dream prefetch: the clock crossed a night during this turn's
      // post-reply decide, so the dream can be generated NOW and
      // merely inserted at the next send — see the producer in
      // chat_service_send.dart. The kick itself is synchronous (the park
      // exists before this line returns); only the model call runs in the
      // background, recording into the next turn's [EvalTraffic]
      // background line, where background spend belongs.
      _maybeKickDreamPrefetch();

      // Embed messages for RAG memory (fire-and-forget)
      _maybeEmbedMessages();

      // Periodic evaluations coordinator (Scene Guest cast detection).
      // NEW-TURN work — only on a normal generation, never on
      // regen/continue (which replay or extend an existing turn).
      if (t.mode == GenerationMode.normal) {
        _maybeRunPeriodicEvals();
      }
    }
  }
}
