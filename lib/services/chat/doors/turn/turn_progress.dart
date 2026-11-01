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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/chat_defaults.dart';

/// Set when regenerate/continue abort in-flight post-gen evals (needs,
/// climax, pockets, posture) so the rejected reply is not scored. Cleared
/// after a successful yield, at finalize start, and in regen's finally —
/// leftover latch must not survive into the next turn. File scope, as it
/// always was: one latch for the process.
bool _postGenAbortRequested = false;

/// One turn's progress and flags: the narrow streaming flag, the settling
/// window after it, Stop, the turn epoch, the status bar's numbers (phase,
/// tokens, prefill timing, the KoboldCpp perf poll), the display buffer and
/// the two live streams (tokens for the web, sentences for a voice call).
///
/// Not a notifier: it calls the service's own notify ([notify]), so the
/// status bar and the composer see each transition when they always did.
class TurnProgress {
  TurnProgress(this.notify, {required bool Function() busyElsewhere})
    : _busyElsewhere = busyElsewhere;

  /// The service's own notify, synchronous.
  final void Function() notify;

  /// An import, the narrator's beat or a send parked on "Did time pass?".
  final bool Function() _busyElsewhere;

  /// Token streaming — deliberately the NARROW sense (see the shell's
  /// `isGenerating`). It drives the send button.
  bool isGenerating = false;

  /// True while the awaited POST-generation work is still running.
  ///
  /// [isGenerating] is cleared the moment the last token lands, but the turn
  /// is not finished there: the needs-impact eval, the realism-state re-stamp,
  /// the `RealismDance.saveScalarsIntoGroup` persist and the chip attach all
  /// run afterwards, and in a group they run under an impersonation dance
  /// that reassigns the active character and loads that member's scalars.
  /// For those seconds the app used to report "not generating" while the
  /// engine was still mutating state, so every re-entrancy guard stood open:
  /// a delete could shift the timeline under a running eval, and a new turn
  /// could interleave with the previous one's persist.
  ///
  /// Deliberately NOT held across the fire-and-forget passes (journal,
  /// growth, promise-debt, embed, periodic evals). Those are unawaited by
  /// design and can run indefinitely; blocking input until they finish
  /// would trade a race for a wedged UI, which is the worse bug.
  bool isPostGenerating = false;

  /// True while Try again (regenerate on a trailing user line) runs. That
  /// regen holds [isPostGenerating], but no reply exists to keep.
  bool answeringUnansweredLine = false;

  /// Stop was pressed; the stream loop and the drain wait read it.
  bool cancelRequested = false;

  /// Bumped per turn and on a chat switch: a stale turn's late writes skip.
  int generationEpoch = 0;

  bool get postGenAbortRequested => _postGenAbortRequested;
  set postGenAbortRequested(bool v) => _postGenAbortRequested = v;

  /// The honest "this turn is still in motion" predicate — what the mutation
  /// guards should ask, rather than [isGenerating] alone.
  ///
  /// NOT for the escape hatches: `stopGeneration` and
  /// `cancelAndWaitForGeneration` must keep testing [isGenerating] on its
  /// own. The first aborts an in-flight HTTP stream (there is none during
  /// post-gen), and the second SPINS until the flag clears — broadening it
  /// would hang the caller if post-gen ever failed to settle.
  bool get isTurnBusy => isGenerating || isPostGenerating || _busyElsewhere();

  /// True while the turn's awaited post-generation work is still settling.
  /// Exposed so tests can assert the window opens and — more importantly —
  /// always closes. See [isPostGenerating].
  bool get isSettlingTurn => isPostGenerating;

  double generationProgress = 0.0;
  int tokensGenerated = 0;
  int maxTokens = 0;
  DateTime? generationStartTime;
  GenerationPhase generationPhase = GenerationPhase.idle;

  /// When we entered prefill (for the elapsed timer).
  DateTime? prefillStartTime;

  /// Estimated prompt token count for progress display.
  int prefillPromptTokens = 0;

  /// Cached KoboldCPP perf data from the last /api/extra/perf poll.
  Map<String, dynamic>? lastPerfData;

  final List<String> tokenBuffer = [];
  Timer? drainTimer;
  int displayedTokenCount = 0;

  /// Rolling window for TPS measurement.
  final List<DateTime> tokenTimestamps = [];

  // ── Streaming rebuild throttle ──
  // notifyStreamListeners coalesces per-token notifies into at most one per
  // ~33 ms with a guaranteed trailing notify (the final token batch always
  // paints). End-of-turn paths still call plain notify directly, so
  // terminal state (isGenerating=false, chips, perf) is never throttled.
  DateTime _lastStreamNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _streamNotifyTimer;

  /// The web StreamHub's real-time token feed.
  final StreamController<String> tokenBroadcast =
      StreamController<String>.broadcast();

  /// Emits complete sentences as they're detected during LLM token
  /// streaming. Used by call mode to start TTS on the first sentence.
  final StreamController<String> sentenceBroadcast =
      StreamController<String>.broadcast();

  /// Accumulates tokens until a sentence boundary.
  String sentenceBuffer = '';

  /// Seconds elapsed since entering the prefill phase. Returns 0 if not
  /// prefilling.
  double get prefillElapsedSeconds => prefillStartTime != null
      ? DateTime.now().difference(prefillStartTime!).inMilliseconds / 1000.0
      : 0.0;

  double get tokensPerSecond {
    if (tokenTimestamps.length < 2) return 0.0;
    // Use rolling window: tokens in the last 3 seconds
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(seconds: 3));
    final recent = tokenTimestamps.where((t) => t.isAfter(cutoff)).length;
    if (recent < 2) {
      // Fallback to overall average
      if (generationStartTime == null || tokensGenerated == 0) return 0.0;
      final elapsed =
          now.difference(generationStartTime!).inMilliseconds / 1000.0;
      return elapsed > 0 ? tokensGenerated / elapsed : 0.0;
    }
    final windowStart = tokenTimestamps.where((t) => t.isAfter(cutoff)).first;
    final windowElapsed = now.difference(windowStart).inMilliseconds / 1000.0;
    return windowElapsed > 0 ? recent / windowElapsed : 0.0;
  }

  void notifyStreamListeners() {
    if (_streamNotifyTimer != null) return; // trailing notify already queued
    final elapsed = DateTime.now().difference(_lastStreamNotify);
    if (elapsed >= kStreamNotifyInterval) {
      _notifyStreamTick();
    } else {
      _streamNotifyTimer = Timer(kStreamNotifyInterval - elapsed, () {
        _streamNotifyTimer = null;
        _notifyStreamTick();
      });
    }
  }

  void _notifyStreamTick() {
    _lastStreamNotify = DateTime.now();
    StreamTickNotify.run(notify);
  }

  void cancelStreamNotifyThrottle() {
    _streamNotifyTimer?.cancel();
    _streamNotifyTimer = null;
  }
}
