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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Phase 5 of a turn: stream target identity, the display-buffer and
/// drain-timer machinery, the per-token consume loop (stop-sequence and
/// think-tag tracking, TPS pacing). The body is the one the stream part
/// held (`x` → `t.x` carrier names, see [GenTurn]); zero behaviour change.
///
/// [consume] returns `true` when the user cancelled the turn (the caller
/// must stop — no finalize, no lorebook scan, no post-turn evals run on an
/// aborted reply) and `false` when the stream finished normally and
/// finalization should proceed (hazard H2).
class TurnStream {
  TurnStream(this._e);

  final TurnEngine _e;

  TurnDeps get _d => _e.deps;
  ChatSessionState get _session => _d.session;
  TurnProgress get _p => _e.progress;
  RealismGraph get _g => _d.doors.graph();
  PromptAssembler get _prompts => _d.doors.prompts();
  StorageService get _storageService => _d.services.storage;
  UserPersonaService get _userPersonaService => _d.services.personas;
  KoboldService get _koboldService => _d.services.kobold;
  LLMProvider? get _llmProvider => _d.services.llmProvider();
  String? _getCharacterIdForCard(CharacterCard card) =>
      _session.characterIdFor(card);

  MoodRegisters get _mood => _g.mood;
  Map<String, dynamic>? get _pendingRealismMetadata => _g.registers.pending;
  set _pendingRealismMetadata(Map<String, dynamic>? v) =>
      _g.registers.pending = v;
  void _stampReplyContext(ChatMessage target, {required bool continuing}) =>
      _prompts.budget.stampReplyContext(target, continuing: continuing);
  StandingMood get _standingMood => _g.standingMood;

  Future<bool> consume(GenTurn t) async {
    t.accumulatedResponse = "";
    bool stopFound = false;
    _p.tokenBuffer.clear();
    _p.displayedTokenCount = 0;
    _p.tokenTimestamps.clear();
    bool streamDone = false;
    bool _thinkStarted = false;
    bool _thinkEnded = false;

    // Determine message identity. The stream target is captured ONCE by
    // reference — every later write (flush, think timestamps, sanitizer,
    // needs re-stamp, TTS) goes through it instead of _session.messages.last. The
    // list can shift under a long turn (dream insert, deletes, another
    // send: none of those are hard-blocked while a turn winds down), and
    // positional writes are how an aborted reply overwrote a dream banner
    // (2026-07-28). A write to a message deleted mid-turn lands on the
    // detached object — harmless and invisible.
    String originalText = '';
    String targetSender;
    bool isUserTarget;

    // Standing Mood and the mood's cause ride the turn's metadata so the
    // mood chip can explain itself. Stamped HERE, the single funnel every
    // path attaches through (one-shot, multi-call, group per-speaker,
    // reprocess), not beside each site that writes 'emotion_label', which
    // is how one of them would eventually be missed.
    if (_pendingRealismMetadata != null) {
      _standingMood.stamp(_pendingRealismMetadata!);
      _mood.stampCause(_pendingRealismMetadata!);
    }

    if (t.mode == GenerationMode.continue_) {
      t.streamTarget = _session.messages.last;
      // Capture before any tokens arrive — postgen re-merges this with
      // accumulatedResponse (new tokens only) after strip/sanitize.
      t.continuePrefix = closeOpenThink(t.streamTarget.text);
      originalText = t.continuePrefix;
      targetSender = t.streamTarget.sender;
      isUserTarget = t.streamTarget.isUser;
      // Continue extends the reply already on screen. It does not re-eval,
      // so leftover `_pendingRealismMetadata` (a cancelled regen's chips /
      // realism_state) must not stamp this bubble. Cancel paths null it;
      // do not merge it here.
    } else {
      originalText = t.continuePrefix; // a rewrite's seed; else empty
      targetSender = t.mode == GenerationMode.normal
          ? t.speakingCharacter.name
          : _userPersonaService.persona.name;
      isUserTarget = t.mode == GenerationMode.impersonate;
      // A Scene Guest / soft roster turn carries NO Realism/Needs, so its
      // message must never inherit `_pendingRealismMetadata` — leftover
      // host/full-member `needs_pre_turn_vector` and chips. 1:1 guests
      // already skipped via `guestSpeaker`; group lite must too.
      // time_skip_to is chat-scoped skip ownership, not speaker Realism:
      // keep only that key so an OOC / AFK snap still chips the guest
      // reply. Pending is consumed by the host attach, so also read the
      // last bot slot when the key is no longer pending.
      final Map<String, dynamic>? initialMetadata;
      if (_e.entry.isLiteTurn(t)) {
        var skip = _pendingRealismMetadata?['time_skip_to'] as String? ?? '';
        if (skip.isEmpty) {
          for (var i = _session.messages.length - 1; i >= 0; i--) {
            final m = _session.messages[i];
            if (m.isUser || m.sender == 'System') continue;
            skip = m.activeMetadata?['time_skip_to'] as String? ?? '';
            break;
          }
        }
        initialMetadata = liteSkipMetadata(skip, _pendingRealismMetadata);
      } else if (_pendingRealismMetadata == null) {
        initialMetadata = null;
      } else {
        // needs_time_wear is post-gen scratch (the chip step reads it),
        // written after this reset, so a value here is the previous
        // turn's and would ride onto this reply: with the global Needs
        // switch turned off mid-chat, the new reply wore nothing and
        // showed last turn's wear.
        initialMetadata = Map<String, dynamic>.from(_pendingRealismMetadata!)
          ..remove('needs_time_wear');
      }
      debugPrint(
        '[Realism:Metadata] PRE-GEN attach (needs_deltas + any post-gen '
        'deltas are added AFTER this): '
        'bond_delta=${initialMetadata?['bond_delta']}, '
        'keys=${initialMetadata?.keys.toList()}',
      );
      t.streamTarget = ChatMessage(
        text: "",
        sender: targetSender,
        isUser: isUserTarget,
        characterId: t.mode == GenerationMode.normal
            ? _getCharacterIdForCard(t.speakingCharacter)
            : null,
        metadata: initialMetadata,
        swipeMetadata: initialMetadata != null ? [initialMetadata] : null,
      );
      _session.messages.add(t.streamTarget);
      t.replyLanded = true;
      _pendingRealismMetadata = null;
    }
    // RAG receipt (rag_injection.dart): stamped here — the same single
    // funnel Standing Mood uses above — so continue/regen/group/guest turns
    // all carry what retrieval did for THIS text. Persisted by the postgen
    // _saveChat with everything else.
    if (t.ragReceipt != null) {
      t.streamTarget.activeMetadata ??= {};
      t.streamTarget.activeMetadata!['rag_receipt'] = t.ragReceipt;
    }
    if (t.searchReceipt != null) {
      t.streamTarget.activeMetadata ??= {};
      t.streamTarget.activeMetadata!['search_receipt'] = t.searchReceipt;
      if (t.searchReceipt!['source'] == 'wiki') {
        t.streamTarget.activeMetadata!['wiki_receipt'] = t.searchReceipt;
      }
    }
    if (t.wikiReceipt != null) {
      t.streamTarget.activeMetadata ??= {};
      t.streamTarget.activeMetadata!['wiki_receipt'] = t.wikiReceipt;
    }
    if (t.toolReceipt != null) {
      t.streamTarget.activeMetadata ??= {};
      t.streamTarget.activeMetadata!['tool_receipt'] = t.toolReceipt;
    }
    _stampReplyContext(
      t.streamTarget,
      continuing: t.mode == GenerationMode.continue_,
    );
    final streamTarget = t.streamTarget;

    // Helper to update the visible message from buffer. Incremental: only
    // tokens newly admitted to display are appended to the running buffer
    // (the old `.take(n).join()` re-joined the ENTIRE response per token —
    // O(n²) over a long reply and the largest allocator on this path).
    final displayedBuf = StringBuffer();
    var displayedInBuf = 0;
    void _flushBufferToDisplay() {
      if (t.epoch != _p.generationEpoch) return; // stale generation
      if (_p.tokenBuffer.isEmpty && _p.displayedTokenCount == 0) return;
      while (displayedInBuf < _p.displayedTokenCount &&
          displayedInBuf < _p.tokenBuffer.length) {
        displayedBuf.write(_p.tokenBuffer[displayedInBuf++]);
      }
      final displayTokens = displayedBuf.toString();
      String displayText;
      if (t.mode == GenerationMode.continue_) {
        displayText = glueContinueText(originalText, displayTokens);
      } else {
        displayText = (originalText + displayTokens).trimLeft();
      }
      // CRITICAL: Modify the captured stream target in place (never
      // _session.messages.last — the list can shift mid-turn) to preserve
      // thinkingStartTime and other metadata.
      streamTarget.text = displayText;
      _p.notifyStreamListeners();
    }

    // Read display buffer settings — disable for remote APIs (they're fast enough)
    final isRemoteBackend = _llmProvider != null && !_llmProvider!.isLocal;
    final bufferEnabled = isRemoteBackend
        ? false
        : _storageService.uiSettings.displayBufferEnabled;
    final targetTps = _storageService.uiSettings.targetDisplayTps;

    // Drain timer: displays tokens at the user-configured constant rate
    void _startDrainTimer() {
      if (_p.drainTimer != null) return;
      final interval = Duration(milliseconds: (1000.0 / targetTps).round());
      _p.drainTimer = Timer.periodic(interval, (_) {
        if (t.epoch != _p.generationEpoch) {
          _p.drainTimer?.cancel();
          _p.drainTimer = null;
          return;
        } // stale
        if (_p.displayedTokenCount < _p.tokenBuffer.length) {
          _p.displayedTokenCount++;
          _flushBufferToDisplay();
        } else if (streamDone) {
          // Stream finished and buffer fully drained
          _p.drainTimer?.cancel();
          _p.drainTimer = null;
        }
        // If buffer is caught up but stream still running, timer ticks idly until more tokens arrive
      });
    }

    // Scan window for stop sequences / think tags: only the newly-appended
    // token can COMPLETE a match, so scanning the trailing
    // (token + longestNeedle - 1) chars finds exactly what a full scan
    // would — without re-reading the whole response per token (O(n²)).
    final maxStopLen = t.stopList.fold<int>(
      0,
      (m, s) => s.length > m ? s.length : m,
    );
    // Cursor for the rolling-TPS window: timestamps are appended in order,
    // so entries before the cutoff can be skipped permanently instead of
    // re-filtered with two O(n) where() passes per token.
    var tpsWindowStart = 0;

    // Consume the stream — tokens go into buffer (or display immediately)
    await for (final token in t.stream) {
      if (_p.cancelRequested) break;
      t.accumulatedResponse += token;
      _p.tokensGenerated++;
      _p.tokenTimestamps.add(DateTime.now());
      final tailStart =
          (t.accumulatedResponse.length -
                  token.length -
                  (maxStopLen > 8 ? maxStopLen : 8) +
                  1)
              .clamp(0, t.accumulatedResponse.length);

      // ── Phase transition: first token marks end of prefill ──
      if (_p.tokensGenerated == 1) {
        t.perfPoller?.cancel();
        t.perfPoller = null;
        // Fetch final perf data so we know how long prefill really took
        if (t.isLocalBackend) {
          _koboldService.fetchPerf().then((perf) {
            if (perf != null) {
              _p.lastPerfData = perf;
            }
          });
        }
        _p.prefillStartTime = null;
      }

      // Broadcast token to external listeners (SSE bridge)
      _p.tokenBroadcast.add(token);
      _p.generationProgress = _p.maxTokens > 0
          ? (_p.tokensGenerated / _p.maxTokens).clamp(0.0, 1.0)
          : 0.0;

      // Sentence streaming: emit complete sentences for live TTS (split
      // logic extracted verbatim to sentence_stream.dart).
      _p.sentenceBuffer = drainCompleteSentences(
        _p.sentenceBuffer + token,
        _p.sentenceBroadcast.add,
      );

      // Track think timing (tail-window scans, same reasoning as above).
      // Runs BEFORE the stop-sequence scan so the scan knows the model is
      // inside an open <think> block for this very chunk. Case-INSENSITIVE
      // like ChatMessage.displayText's strip (<THINK> is valid there) — a
      // case-sensitive tracker here would leave uppercase think blocks
      // unprotected from the trim below.
      final tailLower = t.accumulatedResponse
          .substring(tailStart)
          .toLowerCase();
      if (!_thinkStarted && tailLower.contains('<think>')) {
        _thinkStarted = true;
        final startedAt = t.thinkStartedAt = DateTime.now();
        _p.generationPhase = GenerationPhase.thinking;
        streamTarget.thinkingStartTime = startedAt.millisecondsSinceEpoch;
      }
      final closeIdxInTail = (_thinkStarted && !_thinkEnded)
          ? tailLower.indexOf('</think>')
          : -1;
      final thinkClosedThisChunk = closeIdxInTail != -1;

      // Client-side safety trim check (mid-stream). Tail-window scan: a
      // match ending before this token was already caught last iteration.
      // SKIPPED inside an open <think> block (and scanning only AFTER a
      // close seen this chunk): models draft dialogue ("Name: …") while
      // thinking, and trimming there strands an unclosed <think> whose
      // displayText strips to an empty bubble (Discord report 2026-08-04).
      if (!_thinkStarted || _thinkEnded || thinkClosedThisChunk) {
        final scanFrom = thinkClosedThisChunk
            ? tailStart + closeIdxInTail + '</think>'.length
            : tailStart;
        for (final stop in t.stopList) {
          final index = t.accumulatedResponse.indexOf(stop, scanFrom);
          if (index != -1) {
            final trimmedTotal = t.accumulatedResponse.substring(0, index);
            final previousTotal = _p.tokenBuffer.join();
            final lastTokenContribution = trimmedTotal.substring(
              previousTotal.length.clamp(0, trimmedTotal.length),
            );
            if (lastTokenContribution.isNotEmpty) {
              _p.tokenBuffer.add(lastTokenContribution);
            }
            t.accumulatedResponse = trimmedTotal;
            stopFound = true;
            break;
          }
        }
      }

      if (!stopFound) {
        _p.tokenBuffer.add(token);
      }

      // The trim can only cut AFTER the closing tag, so a close seen this
      // chunk always survives it.
      if (thinkClosedThisChunk) {
        _thinkEnded = true;
        // Transition out of thinking to buffering/generating
        _p.generationPhase = bufferEnabled
            ? GenerationPhase.buffering
            : GenerationPhase.generating;
        final startedAt = t.thinkStartedAt;
        if (startedAt != null) {
          streamTarget.thinkingDurationMs = DateTime.now()
              .difference(startedAt)
              .inMilliseconds;
          // Keep thinkingStartTime for fallback display logic in UI
        }
      }
      // If no thinking involved, first token transitions directly
      if (!_thinkStarted && _p.tokensGenerated == 1) {
        _p.generationPhase = bufferEnabled
            ? GenerationPhase.buffering
            : GenerationPhase.generating;
      }

      if (bufferEnabled) {
        // Calculate current rolling TPS (last 3 seconds). Timestamps are
        // appended in order, so advance a cursor past expired entries once
        // instead of re-filtering the whole list twice per token.
        final now = DateTime.now();
        final cutoff = now.subtract(const Duration(seconds: 3));
        while (tpsWindowStart < _p.tokenTimestamps.length &&
            !_p.tokenTimestamps[tpsWindowStart].isAfter(cutoff)) {
          tpsWindowStart++;
        }
        final recentCount = _p.tokenTimestamps.length - tpsWindowStart;
        final windowStart = tpsWindowStart < _p.tokenTimestamps.length
            ? _p.tokenTimestamps[tpsWindowStart]
            : _p.generationStartTime!;
        final windowElapsed =
            now.difference(windowStart).inMilliseconds / 1000.0;
        final currentTps = (recentCount >= 2 && windowElapsed > 0)
            ? recentCount / windowElapsed
            : (_p.tokensGenerated > 0
                  ? _p.tokensGenerated /
                        (now
                                .difference(_p.generationStartTime!)
                                .inMilliseconds /
                            1000.0)
                  : 0.0);

        if (_p.drainTimer == null && _p.tokensGenerated >= 10) {
          // Not yet draining — calculate when to start
          // Buffer target = how many tokens fill the configured duration
          final bufferDuration =
              _storageService.uiSettings.bufferDurationSeconds;
          int bufferTarget;
          if (currentTps > 0) {
            bufferTarget = (currentTps * bufferDuration).round().clamp(
              5,
              _p.maxTokens,
            );
          } else {
            bufferTarget = 30; // Fallback if TPS unknown
          }

          if (_p.tokenBuffer.length >= bufferTarget) {
            _p.generationPhase = GenerationPhase.generating;
            _startDrainTimer();
          }
        } else if (_p.drainTimer != null) {
          // Already draining — check if buffer is running low
          final remaining = _p.tokenBuffer.length - _p.displayedTokenCount;
          if (remaining <= 3 && !streamDone) {
            // Buffer critically low — pause drain to rebuild
            _p.drainTimer?.cancel();
            _p.drainTimer = null;
            _p.generationPhase = GenerationPhase.buffering;
          }
        }
      } else {
        // No buffer: display tokens immediately
        _p.generationPhase = GenerationPhase.generating;
        _p.displayedTokenCount = _p.tokenBuffer.length;
        _flushBufferToDisplay();
      }

      // Update TPS/progress in the bar even during buffering — coalesced;
      // the non-buffered flush above already went through the throttle, so
      // this is a no-op there unless the interval elapsed.
      _p.notifyStreamListeners();

      if (stopFound) break;
    }

    // Mark stream as done. From here on state changes are terminal, so
    // drop any pending throttled notify — the finalize paths below (cancel
    // AND normal) both end in an unthrottled notifyListeners().
    streamDone = true;
    _p.cancelStreamNotifyThrottle();

    if (_p.cancelRequested) {
      // Cancelled mid-stream: do NOT drain the undisplayed backlog. A
      // think-heavy turn can hold minutes of buffered tokens, and draining
      // them after Stop is how an aborted reply kept "dumping" (and, via
      // the positional last-message writes, how one landed inside a dream
      // banner — 2026-07-28). Keep exactly what's on screen.
    } else if (!bufferEnabled) {
      // No buffer: everything already displayed
      _p.displayedTokenCount = _p.tokenBuffer.length;
      _flushBufferToDisplay();
    } else if (_p.drainTimer == null) {
      // Buffer never started draining (genTps < targetTps) — start now with all tokens ready
      _startDrainTimer();
      // Wait for drain to complete (Stop pressed mid-drain halts it)
      while (_p.displayedTokenCount < _p.tokenBuffer.length &&
          !_p.cancelRequested) {
        await Future.delayed(const Duration(milliseconds: 16));
      }
      _p.drainTimer?.cancel();
      _p.drainTimer = null;
    } else {
      // Drain already running — wait for it to finish (or Stop to halt it)
      while (_p.displayedTokenCount < _p.tokenBuffer.length &&
          !_p.cancelRequested) {
        await Future.delayed(const Duration(milliseconds: 16));
      }
      _p.drainTimer?.cancel();
      _p.drainTimer = null;
    }

    // User cancel (stream-loop break above, or Stop during the drain):
    // halt the turn HERE — no finalize, no lorebook scan, no post-turn
    // evals on an aborted reply. Mirrors the catch path's treatAsCancel:
    // keep the displayed partial so regen/continue work, save, signal done.
    if (_p.cancelRequested) {
      await _e.stops.haltStoppedTurn(t, streamTarget);
      return true;
    }
    t.sealThinkClock();
    return false;
  }
}
