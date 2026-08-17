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

/// Phase 6 (final) of `_generateResponse` (see chat_service_generation.dart):
/// normal-completion state reset + `__DONE__` broadcasts, epoch-guarded
/// finalization (think-block salvage, the Output Sanitizer, lorebook
/// scan/decrement, `_saveChat`), the Scene-Guest parity guard wrapping the
/// whole Realism/Needs post-gen block (inter-character feelings, the
/// impersonation dance, `_saveScalarsIntoGroupRealism`, the chip attach),
/// the Journal/Growth/promise/embed/periodic passes, TTS auto-play, director
/// auto-play, and the call-mode model restore. Extracted verbatim
/// (mechanical `x` → `t.x` carrier rename only — see `_GenTurn`) from the
/// single ~1.9k-line `_generateResponse` method during the god-file split
/// (docs/design/god-file-elimination.md). Zero behaviour change.
///
/// **This is the parity-critical file** — see CLAUDE.md "Tracing
/// Realism/Needs/Group Post-Generation, Chips, Sidebar & Climax Checks",
/// which now names this file for the post-gen finalization step.
extension ChatServiceGenerationPostGen on ChatService {
  Future<void> _finalizeGenerationTurn(_GenTurn t) async {
    _isGenerating = false;
    // Settling starts the instant the last token lands — the finalization
    // below (sanitizer, lorebook, _saveChat, post-gen checks, chip attach)
    // is still the turn; the old late raise let a new turn interleave
    // (message_actions Windows CI). Restored in the outer finally.
    _isPostGenerating = true;
    _cancelRequested = false;
    _generationProgress = 0.0;
    _generationPhase = GenerationPhase.idle;
    _prefillStartTime = null;
    _prefillPromptTokens = 0;
    _generationStartTime = null;
    t.perfPoller?.cancel();
    t.perfPoller = null;

    // Fetch final perf stats from KoboldCPP for post-generation display
    if (t.isLocalBackend) {
      _koboldService.fetchPerf().then((perf) {
        if (perf != null) _lastPerfData = perf;
      });
    }

    // Signal generation complete to SSE listeners
    _tokenBroadcast.add('__DONE__');

    // Flush remaining sentence buffer and signal done to sentence listeners
    if (_sentenceBuffer.trim().isNotEmpty) {
      _sentenceBroadcast.add(_sentenceBuffer.trim());
      _sentenceBuffer = '';
    }
    _sentenceBroadcast.add('__DONE__');

    notifyListeners();

    // Only finalize if this generation is still current
    if (t.epoch == _generationEpoch) {
      // New tokens only from the stream. Continue paints
      // `glueContinueText(continuePrefix, tokens)` mid-stream; we must
      // re-merge the same way before write-back or sanitize, or the saved
      // bubble collapses to the continuation fragment (audit 2026-08-11 P0.1).
      String newPart = t.accumulatedResponse;

      // SillyTavern-like safety net for Continue (and call mode): even after
      // requesting enabled:false + max_tokens:0 + exclude:true on the
      // provider, some thinking models still emit stray <think> text. Strip
      // from the NEW portion only — never re-strip the pre-continue body.
      if (t.mode == GenerationMode.continue_ || _callMode) {
        newPart = _stripThinkBlocks(newPart);
      }

      // Close an open think on the PREFIX before glue — closing after
      // concat put Continue's new words inside the thought (empty bubble).
      final prefix = t.mode == GenerationMode.continue_
          ? closeOpenThink(t.continuePrefix)
          : '';
      String finalResponse = t.mode == GenerationMode.continue_
          ? glueContinueText(prefix, newPart)
          : newPart.trim();

      // Salvage a reply stranded inside an unclosed <think> in the NEW
      // portion only (backend stop sequences can still cut mid-think).
      finalResponse = closeOpenThink(finalResponse);

      // ── Output Sanitizer ──────────────────────────────────────────────
      // NOTE: This runs BEFORE _lorebookScanner.scanLatest() below, so
      // lorebook keyword triggers operate on the sanitized text. If a rule
      // replaces text that a lorebook keyword was matching, the trigger
      // would stop matching. This is intentional — sanitized output is the
      // "final" text that enters history and is scanned for lore.
      if (t.g2.resolveOutputSanitizerEnabled(_storageService)) {
        final rules = t.g2.resolveOutputSanitizerRules(_storageService);
        final sanitized = sanitizeOutput(finalResponse, rules);
        if (sanitized.trim().isEmpty && finalResponse.trim().isNotEmpty) {
          // A runaway rule ate the entire reply — keep the original text
          // rather than persisting an empty message the user can't recover.
          debugPrint(
            '[Sanitizer] rules reduced the whole reply to empty — '
            'keeping the unsanitized text.',
          );
        } else {
          finalResponse = sanitized;
        }
      }

      // Optional [today: …] tag — strip from the visible reply. Live write
      // stays parked (no holdTodayLine, no plannerEnabled gate).
      final todayParsed = TodayLineTag.parse(finalResponse);
      finalResponse = todayParsed.visible;

      // Always persist the finalized body. Continue + strip without sanitizer
      // used to leave streamTarget alone after mutating only finalResponse —
      // and when sanitizer DID run it wrote new-tokens-only. One write-back.
      if (finalResponse.isNotEmpty || t.mode == GenerationMode.continue_) {
        t.streamTarget.text = finalResponse;
      }

      // Turn taken = durable, before lorebook/evals.
      await _saveChat();

      // Snapshot which entries were already triggered before scanning the AI response.
      // We will only decrement those — newly AI-triggered entries must keep their
      // full depth budget so they are visible on the next user turn.
      // Covers the full scanned universe (incl. group book + group worlds).
      final preAiTriggered = <LorebookEntry>{
        for (final ref in _collectLoreRefs(inheritOverride: true))
          if (ref.entry.isTriggered && !ref.entry.constant) ref.entry,
      };

      if (finalResponse.isNotEmpty &&
          _messages.isNotEmpty &&
          identical(_messages.last, t.streamTarget)) {
        // scanLatest reads the LAST message — only valid while the streamed
        // message still holds that position (a mid-turn insert/delete can
        // shift it; scanning someone else's text would trigger wrong lore).
        _lorebookScanner.scanLatest();
      }

      // Decrement only entries that were active before the AI response.
      // This preserves full depth for lore discovered in the AI's own words.
      // Thin delegation (preAi set computed in god for snapshot; scanner owns decrement).
      _lorebookScanner.decrementLoreDepthForEntries(preAiTriggered);

      // ── Scene Guest (Lite NPC) parity guard ──────────────────────────
      // A guest turn must NOT touch the active character's Realism Engine,
      // Needs simulation, inter-character feelings, time, chips, or the
      // periodic (facts/evolution/summary/RAG) evaluators. The guest carries
      // no such state. Everything from here through the periodic evals is
      // gated so guest presence/turns leave the primary's state untouched.
      // (Lorebook scan + _saveChat above still ran for the guest.)
      if (t.guestSpeaker == null) {
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
            _relationshipService
                .updateInterCharacterFeelingsFromRecentExchange(speakerId);
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
          // Continue for — she sets the keys down, moves to the swing,
          // finishes the meal — finally reach the bookkeeping. The evals
          // keep full context either way: each gets recentExchange(), and
          // the write-back above already put the whole continued reply into
          // the last message, so the fragment is never read blind.
          // Arithmetic stays exact: needs_pre_turn_vector + re-computed
          // chips still equals the live vector (the chip helper measures
          // live-minus-stamp, so the merge is free), and pockets keeps the
          // ORIGINAL pre-turn stamp so regen/tail-delete rewind to the true
          // base (see _runPocketsPass's asContinuation).
          // Guest-authored tail: a Continue of a Scene Guest's message must
          // score NOTHING — the speaker resolution falls back to the host in
          // 1:1, so the guest's words would mutate the host's pockets, needs
          // and stance. (Guest TURNS never reach here — guestSpeaker != null
          // skips this whole block — but continueGeneration re-enters with
          // guestSpeaker null.) Pre-change the blanket skip masked this.
          final scoredReply = t.mode == GenerationMode.continue_
              ? (_isGuestAuthoredMessage(t.streamTarget)
                    ? ''
                    : newPart.trim())
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
            await Future.wait([
              _runPostGenNeedsChecks(scoredReply),
              Future<void>.delayed(
                _kEvalDispatchStagger,
              ).then((_) => _prefetchReplyFacts(scoredReply)),
            ]);
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
            // Spatial stance — where this reply LEFT her. Third of the same
            // family, and it belongs here for the identical reason: a
            // position the character establishes in her own words cannot be
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
                // her" — consume its answer through the ONE posture parser
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
            // Consumed — the carrier must never outlive the passes that read
            // it, or a stale answer could feed the next turn's bookkeeping.
            _replyFactsRaw = null;
          }

          // Keep this message's realism_state snapshot TRUTHFUL now that the
          // post-gen checks have run — needs vector AND the NSFW scalars a
          // climax just changed. See the helper for the two bugs this
          // prevents (hygiene snap-back; climax erased by the regen merge).
          _restampRealismSnapshotPostGen(t.streamTarget);

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
              (t.mode == GenerationMode.continue_ &&
                  scoredReply.isNotEmpty)) {
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
          // whether her position survived — two unrelated features wired
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
        } finally {
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
        // pre-generation advance, so the dream can be generated NOW and
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
      } // end Scene Guest parity guard (guestSpeaker == null)

      // (Task completion check now runs pre-generation in sendMessage)

      // TTS auto-play: speak the new character message automatically
      if (_ttsService != null &&
          _storageService.ttsSettings.ttsEnabled &&
          _storageService.ttsSettings.ttsAutoPlay &&
          !t.streamTarget.isUser &&
          _messages.contains(t.streamTarget)) {
        final lastMsg = t.streamTarget;
        final msgId = 'msg_${_messages.indexOf(t.streamTarget)}';
        // Resolve per-character voice, falling back to global default
        String? voiceKey;
        if (_activeGroup != null) {
          final charMatch = _groupCharacters
              .where((c) => c.name == lastMsg.sender)
              .firstOrNull;
          voiceKey = charMatch?.ttsVoice;
        } else {
          voiceKey = _activeCharacter?.ttsVoice;
        }
        _ttsService!.speak(
          lastMsg.displayText,
          voiceKey: voiceKey,
          messageId: msgId,
        );
      }

      // Auto-play: if director mode is active, queue the next character
      if (_autoPlayActive && _observerMode && _activeGroup != null) {
        // If TTS is active, wait for it to finish before starting the delay
        if (_ttsService != null && _ttsService!.isSpeaking) {
          _waitForTtsThenContinue();
        } else {
          final delayMs = (directorDelaySec * 1000).round();
          Future.delayed(Duration(milliseconds: delayMs), () {
            if (_autoPlayActive && !_isGenerating) {
              _autoPlayNext();
            }
          });
        }
      }
    }

    // Restore original model if swapped for call mode
    if (t.originalModelName != null && _llmProvider != null) {
      _llmProvider!.openRouterService.configure(
        modelName: t.originalModelName,
      );
    }
  }
}
