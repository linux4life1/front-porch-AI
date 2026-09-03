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

/// Phase 5 of `_generateResponse` (see chat_service_generation.dart): stream
/// target identity, the display-buffer/drain-timer machinery, the per-token
/// consume loop (stop-sequence + think-tag tracking, TPS pacing), and the
/// user-cancel finalize path. Extracted verbatim (mechanical `x` → `t.x`
/// carrier rename only — see `_GenTurn`) from the single ~1.9k-line
/// `_generateResponse` method during the god-file split
/// (docs/design/god-file-elimination.md). Zero behaviour change.
///
/// Returns `true` when the user cancelled the turn (the caller must stop —
/// no finalize, no lorebook scan, no post-turn evals run on an aborted
/// reply) and `false` when the stream finished normally and finalization
/// should proceed. This is the H2 workaround: the original method's
/// `return;` inside this span meant "exit `_generateResponse` entirely",
/// which a phase method can no longer do directly.
extension ChatServiceGenerationStream on ChatService {
  Future<bool> _consumeGenerationStream(_GenTurn t) async {
    t.accumulatedResponse = "";
    bool stopFound = false;
    _tokenBuffer.clear();
    _displayedTokenCount = 0;
    _tokenTimestamps.clear();
    bool streamDone = false;
    DateTime? _thinkStartTime;
    bool _thinkStarted = false;
    bool _thinkEnded = false;

    // Determine message identity. The stream target is captured ONCE by
    // reference — every later write (flush, think timestamps, sanitizer,
    // needs re-stamp, TTS) goes through it instead of _messages.last. The
    // list can shift under a long turn (dream insert, deletes, another
    // send: none of those are hard-blocked while a turn winds down), and
    // positional writes are how an aborted reply overwrote a dream banner
    // (2026-07-28). A write to a message deleted mid-turn lands on the
    // detached object — harmless and invisible.
    String originalText = '';
    String targetSender;
    bool isUserTarget;

    // Standing Mood rides the turn's metadata so the mood chip can explain
    // itself. Stamped HERE — the single funnel every path attaches through
    // (one-shot, multi-call, group per-speaker, reprocess) — rather than
    // beside each of the four sites that write 'emotion_label', which is how
    // one of them would eventually be missed. No-op when the feature is off or
    // the day is unremarkable.
    if (_pendingRealismMetadata != null) {
      stampStandingMood(_pendingRealismMetadata!);
    }

    if (t.mode == GenerationMode.continue_) {
      t.streamTarget = _messages.last;
      // Capture before any tokens arrive — postgen re-merges this with
      // accumulatedResponse (new tokens only) after strip/sanitize.
      t.continuePrefix = closeOpenThink(t.streamTarget.text);
      originalText = t.continuePrefix;
      targetSender = t.streamTarget.sender;
      isUserTarget = t.streamTarget.isUser;
      // Merge metadata if continuing
      if (_pendingRealismMetadata != null) {
        t.streamTarget.activeMetadata ??= {};
        t.streamTarget.activeMetadata!.addAll(_pendingRealismMetadata!);
        _pendingRealismMetadata = null;
      }
    } else {
      targetSender = t.mode == GenerationMode.normal
          ? t.speakingCharacter.name
          : _userPersonaService.persona.name;
      isUserTarget = t.mode == GenerationMode.impersonate;
      // A Scene Guest turn carries NO Realism/Needs, so its message must never
      // inherit _pendingRealismMetadata — which still holds the HOST turn's
      // verification result (the leftover "✓ Director accepted" chip), bond
      // deltas, etc. Guests get clean (null) metadata.
      final initialMetadata =
          (t.guestSpeaker != null || _pendingRealismMetadata == null)
          ? null
          : Map<String, dynamic>.from(_pendingRealismMetadata!);
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
      _messages.add(t.streamTarget);
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
    final streamTarget = t.streamTarget;

    // Helper to update the visible message from buffer. Incremental: only
    // tokens newly admitted to display are appended to the running buffer
    // (the old `.take(n).join()` re-joined the ENTIRE response per token —
    // O(n²) over a long reply and the largest allocator on this path).
    final displayedBuf = StringBuffer();
    var displayedInBuf = 0;
    void _flushBufferToDisplay() {
      if (t.epoch != _generationEpoch) return; // stale generation
      if (_tokenBuffer.isEmpty && _displayedTokenCount == 0) return;
      while (displayedInBuf < _displayedTokenCount &&
          displayedInBuf < _tokenBuffer.length) {
        displayedBuf.write(_tokenBuffer[displayedInBuf++]);
      }
      final displayTokens = displayedBuf.toString();
      String displayText;
      if (t.mode == GenerationMode.continue_) {
        displayText = glueContinueText(originalText, displayTokens);
      } else {
        displayText = displayTokens.trimLeft();
      }
      // CRITICAL: Modify the captured stream target in place (never
      // _messages.last — the list can shift mid-turn) to preserve
      // thinkingStartTime and other metadata.
      streamTarget.text = displayText;
      _notifyStreamListeners();
    }

    // Read display buffer settings — disable for remote APIs (they're fast enough)
    final isRemoteBackend = _llmProvider != null && !_llmProvider!.isLocal;
    final bufferEnabled = isRemoteBackend
        ? false
        : _storageService.uiSettings.displayBufferEnabled;
    final targetTps = _storageService.uiSettings.targetDisplayTps;

    // Drain timer: displays tokens at the user-configured constant rate
    void _startDrainTimer() {
      if (_drainTimer != null) return;
      final interval = Duration(milliseconds: (1000.0 / targetTps).round());
      _drainTimer = Timer.periodic(interval, (_) {
        if (t.epoch != _generationEpoch) {
          _drainTimer?.cancel();
          _drainTimer = null;
          return;
        } // stale
        if (_displayedTokenCount < _tokenBuffer.length) {
          _displayedTokenCount++;
          _flushBufferToDisplay();
        } else if (streamDone) {
          // Stream finished and buffer fully drained
          _drainTimer?.cancel();
          _drainTimer = null;
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
      if (_cancelRequested) break;
      t.accumulatedResponse += token;
      _tokensGenerated++;
      _tokenTimestamps.add(DateTime.now());
      final tailStart =
          (t.accumulatedResponse.length -
                  token.length -
                  (maxStopLen > 8 ? maxStopLen : 8) +
                  1)
              .clamp(0, t.accumulatedResponse.length);

      // ── Phase transition: first token marks end of prefill ──
      if (_tokensGenerated == 1) {
        t.perfPoller?.cancel();
        t.perfPoller = null;
        // Fetch final perf data so we know how long prefill really took
        if (t.isLocalBackend) {
          _koboldService.fetchPerf().then((perf) {
            if (perf != null) {
              _lastPerfData = perf;
            }
          });
        }
        _prefillStartTime = null;
      }

      // Broadcast token to external listeners (SSE bridge)
      _tokenBroadcast.add(token);
      _generationProgress = _maxTokens > 0
          ? (_tokensGenerated / _maxTokens).clamp(0.0, 1.0)
          : 0.0;

      // Sentence streaming: emit complete sentences for live TTS (split
      // logic extracted verbatim to sentence_stream.dart).
      _sentenceBuffer = drainCompleteSentences(
        _sentenceBuffer + token,
        _sentenceBroadcast.add,
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
        _thinkStartTime = DateTime.now();
        _generationPhase = GenerationPhase.thinking;
        streamTarget.thinkingStartTime = _thinkStartTime.millisecondsSinceEpoch;
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
            final previousTotal = _tokenBuffer.join();
            final lastTokenContribution = trimmedTotal.substring(
              previousTotal.length.clamp(0, trimmedTotal.length),
            );
            if (lastTokenContribution.isNotEmpty) {
              _tokenBuffer.add(lastTokenContribution);
            }
            t.accumulatedResponse = trimmedTotal;
            stopFound = true;
            break;
          }
        }
      }

      if (!stopFound) {
        _tokenBuffer.add(token);
      }

      // The trim can only cut AFTER the closing tag, so a close seen this
      // chunk always survives it.
      if (thinkClosedThisChunk) {
        _thinkEnded = true;
        // Transition out of thinking to buffering/generating
        _generationPhase = bufferEnabled
            ? GenerationPhase.buffering
            : GenerationPhase.generating;
        if (_thinkStartTime != null) {
          streamTarget.thinkingDurationMs = DateTime.now()
              .difference(_thinkStartTime)
              .inMilliseconds;
          // Keep thinkingStartTime for fallback display logic in UI
        }
      }
      // If no thinking involved, first token transitions directly
      if (!_thinkStarted && _tokensGenerated == 1) {
        _generationPhase = bufferEnabled
            ? GenerationPhase.buffering
            : GenerationPhase.generating;
      }

      if (bufferEnabled) {
        // Calculate current rolling TPS (last 3 seconds). Timestamps are
        // appended in order, so advance a cursor past expired entries once
        // instead of re-filtering the whole list twice per token.
        final now = DateTime.now();
        final cutoff = now.subtract(const Duration(seconds: 3));
        while (tpsWindowStart < _tokenTimestamps.length &&
            !_tokenTimestamps[tpsWindowStart].isAfter(cutoff)) {
          tpsWindowStart++;
        }
        final recentCount = _tokenTimestamps.length - tpsWindowStart;
        final windowStart = tpsWindowStart < _tokenTimestamps.length
            ? _tokenTimestamps[tpsWindowStart]
            : _generationStartTime!;
        final windowElapsed =
            now.difference(windowStart).inMilliseconds / 1000.0;
        final currentTps = (recentCount >= 2 && windowElapsed > 0)
            ? recentCount / windowElapsed
            : (_tokensGenerated > 0
                  ? _tokensGenerated /
                        (now.difference(_generationStartTime!).inMilliseconds /
                            1000.0)
                  : 0.0);

        if (_drainTimer == null && _tokensGenerated >= 10) {
          // Not yet draining — calculate when to start
          // Buffer target = how many tokens fill the configured duration
          final bufferDuration =
              _storageService.uiSettings.bufferDurationSeconds;
          int bufferTarget;
          if (currentTps > 0) {
            bufferTarget = (currentTps * bufferDuration).round().clamp(
              5,
              _maxTokens,
            );
          } else {
            bufferTarget = 30; // Fallback if TPS unknown
          }

          if (_tokenBuffer.length >= bufferTarget) {
            _generationPhase = GenerationPhase.generating;
            _startDrainTimer();
          }
        } else if (_drainTimer != null) {
          // Already draining — check if buffer is running low
          final remaining = _tokenBuffer.length - _displayedTokenCount;
          if (remaining <= 3 && !streamDone) {
            // Buffer critically low — pause drain to rebuild
            _drainTimer?.cancel();
            _drainTimer = null;
            _generationPhase = GenerationPhase.buffering;
          }
        }
      } else {
        // No buffer: display tokens immediately
        _generationPhase = GenerationPhase.generating;
        _displayedTokenCount = _tokenBuffer.length;
        _flushBufferToDisplay();
      }

      // Update TPS/progress in the bar even during buffering — coalesced;
      // the non-buffered flush above already went through the throttle, so
      // this is a no-op there unless the interval elapsed.
      _notifyStreamListeners();

      if (stopFound) break;
    }

    // Mark stream as done. From here on state changes are terminal, so
    // drop any pending throttled notify — the finalize paths below (cancel
    // AND normal) both end in an unthrottled notifyListeners().
    streamDone = true;
    _cancelStreamNotifyThrottle();

    if (_cancelRequested) {
      // Cancelled mid-stream: do NOT drain the undisplayed backlog. A
      // think-heavy turn can hold minutes of buffered tokens, and draining
      // them after Stop is how an aborted reply kept "dumping" (and, via
      // the positional last-message writes, how one landed inside a dream
      // banner — 2026-07-28). Keep exactly what's on screen.
    } else if (!bufferEnabled) {
      // No buffer: everything already displayed
      _displayedTokenCount = _tokenBuffer.length;
      _flushBufferToDisplay();
    } else if (_drainTimer == null) {
      // Buffer never started draining (genTps < targetTps) — start now with all tokens ready
      _startDrainTimer();
      // Wait for drain to complete (Stop pressed mid-drain halts it)
      while (_displayedTokenCount < _tokenBuffer.length && !_cancelRequested) {
        await Future.delayed(const Duration(milliseconds: 16));
      }
      _drainTimer?.cancel();
      _drainTimer = null;
    } else {
      // Drain already running — wait for it to finish (or Stop to halt it)
      while (_displayedTokenCount < _tokenBuffer.length && !_cancelRequested) {
        await Future.delayed(const Duration(milliseconds: 16));
      }
      _drainTimer?.cancel();
      _drainTimer = null;
    }

    // User cancel (stream-loop break above, or Stop during the drain):
    // halt the turn HERE — no finalize, no lorebook scan, no post-turn
    // evals on an aborted reply. Mirrors the catch path's treatAsCancel:
    // keep the displayed partial so regen/continue work, save, signal done.
    if (_cancelRequested) {
      _drainTimer?.cancel();
      _drainTimer = null;
      _tokenBuffer.clear();
      _isGenerating = false;
      _cancelRequested = false;
      _generationProgress = 0.0;
      _generationPhase = GenerationPhase.idle;
      _prefillStartTime = null;
      _prefillPromptTokens = 0;
      _generationStartTime = null;
      t.perfPoller?.cancel();
      t.perfPoller = null;
      _tokenBroadcast.add('__DONE__');
      if (_sentenceBuffer.trim().isNotEmpty) {
        _sentenceBroadcast.add(_sentenceBuffer.trim());
        _sentenceBuffer = '';
      }
      _sentenceBroadcast.add('__DONE__');
      if (t.originalModelName != null && _llmProvider != null) {
        _llmProvider!.openRouterService.configure(
          modelName: t.originalModelName,
        );
      }
      if (_messages.isNotEmpty) {
        final last = _messages.last;
        final closed = closeOpenThink(last.text);
        if (closed != last.text) last.text = closed;
      }
      await _saveChat();
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Small streaming/turn-busy accessors, moved verbatim from the god
  // file's field block (zero behaviour change) ──

  /// The honest "this turn is still in motion" predicate — what the mutation
  /// guards should ask, rather than `_isGenerating` alone.
  ///
  /// NOT for the escape hatches: `stopGeneration` and
  /// `_cancelAndWaitForGeneration` must keep testing `_isGenerating` on its
  /// own. The first aborts an in-flight HTTP stream (there is none during
  /// post-gen), and the second SPINS until the flag clears — broadening it
  /// would hang the caller if post-gen ever failed to settle.
  bool get _isTurnBusy => _isGenerating || _isPostGenerating || _isImporting;

  void _notifyStreamListeners() {
    if (_streamNotifyTimer != null) return; // trailing notify already queued
    final elapsed = DateTime.now().difference(_lastStreamNotify);
    if (elapsed >= _kStreamNotifyInterval) {
      _lastStreamNotify = DateTime.now();
      notifyListeners();
    } else {
      _streamNotifyTimer = Timer(_kStreamNotifyInterval - elapsed, () {
        _streamNotifyTimer = null;
        _lastStreamNotify = DateTime.now();
        notifyListeners();
      });
    }
  }

  void _cancelStreamNotifyThrottle() {
    _streamNotifyTimer?.cancel();
    _streamNotifyTimer = null;
  }

  /// External consumers (the web server's StreamHub) listen to this for
  /// real-time token streaming.
  Stream<String> get tokenStream => _tokenBroadcast.stream;

  /// Emits complete sentences as they're detected during LLM token streaming.
  /// Used by call mode to start TTS on the first sentence immediately.
  Stream<String> get sentenceStream => _sentenceBroadcast.stream;
  // (callMode moved onto the class shell — fake-pinned for the call overlay
  // widget tests, and its setter now owns the call-model swap release.)

  /// True while the turn's awaited post-generation work is still settling.
  /// Exposed so tests can assert the window opens and — more importantly —
  /// always closes. See [_isPostGenerating].
  bool get isSettlingTurn => _isPostGenerating;

  /// Typed send is queued behind post-gen evals. Composer is empty; no bubble
  /// yet. UI shows a holding banner so the wait does not look like a lost send.
  bool get isSendWaitingOnSettle => _sendWaitingOnSettle;

  // ── Round-4b forwarder body (see chat_service_accessors.dart's banner
  // comment for why this stays a one-line forwarder on the class body) ──
  double get _tokensPerSecondImpl {
    if (_tokenTimestamps.length < 2) return 0.0;
    // Use rolling window: tokens in the last 3 seconds
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(seconds: 3));
    final recent = _tokenTimestamps.where((t) => t.isAfter(cutoff)).length;
    if (recent < 2) {
      // Fallback to overall average
      if (_generationStartTime == null || _tokensGenerated == 0) return 0.0;
      final elapsed =
          now.difference(_generationStartTime!).inMilliseconds / 1000.0;
      return elapsed > 0 ? _tokensGenerated / elapsed : 0.0;
    }
    final windowStart = _tokenTimestamps.where((t) => t.isAfter(cutoff)).first;
    final windowElapsed = now.difference(windowStart).inMilliseconds / 1000.0;
    return windowElapsed > 0 ? recent / windowElapsed : 0.0;
  }
}
