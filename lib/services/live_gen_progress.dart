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

import 'package:front_porch_ai/services/prefill_anchors.dart';

/// Live per-request progress for the truthful status bar — the SHARED struct
/// every backend source writes into and both UIs (desktop status bar, web
/// gen_status events) read from:
///
///  * managed KoboldCpp — console lines parsed via [ingest]
///  * oMLX — `/admin/api/stats` poll writes via [setPromptProgress] /
///    [setGenProgress] (omlx_status_poller.dart)
///  * LM Studio — `lms log stream --source runtime` lines via
///    [ingestLmStudioRuntimeLine] (lmstudio_log_streamer.dart)
///
/// All sources report prompt progress only once per BATCH, so consumers use
/// [estimatedPromptFraction] to interpolate between real anchors.
///
/// KoboldCpp and LM Studio print a batch's line BEFORE they evaluate it
/// (`gpttype_adapter.cpp` prints `input_consumed` at the top of the loop,
/// then decodes), so their latest count is the end of the batch IN FLIGHT and
/// only the previous count is done: [promptConfirmed] vs [inFlightEnd].
/// oMLX reports `processed`, which is already done.
class LiveGenProgress {
  static final RegExp _processRe = RegExp(
    r'Processing Prompt(?:\s*\[[^\]]*\])?\s*\((\d+)\s*/\s*(\d+) tokens\)',
  );
  static final RegExp _generateRe = RegExp(
    r'Generating\s*\((\d+)\s*/\s*(\d+) tokens\)',
  );

  /// LM Studio runtime log: `... prompt processing progress, n_tokens = 512,
  /// batch.n_tokens = 512, progress = 0.168754` (cumulative tokens + exact
  /// fraction; captured empirically 2026-07-14).
  static final RegExp _lmsProgressRe = RegExp(
    r'prompt processing progress, n_tokens = (\d+),.*?progress = ([0-9.]+)',
  );

  /// The latest count the source printed (for Kobold/LM Studio: the end of
  /// the batch being evaluated now).
  int promptCurrent = 0;
  int promptTotal = 0;

  /// Tokens the source has really finished reading this pass.
  int promptConfirmed = 0;

  /// Where the batch being evaluated ends, when the source says so; the
  /// estimate never runs past it.
  int? inFlightEnd;

  final PrefillAnchors _anchors = PrefillAnchors();
  int genCurrent = 0;
  int genTotal = 0;
  DateTime? updatedAt;

  /// How many requests the source reports queued (oMLX `waiting[]`). The
  /// source cannot tell WHOSE they are (ours vs someone waiting on us), so
  /// consumers must state the fact neutrally ("1 request queued") — never
  /// attribute the wait (review finding: attribution here was invertible).
  int waitingCount = 0;

  /// What has the engine while the app's own requests wait for it, in words
  /// ("the speed test"), or null. About the engine, not one request, so
  /// [reset] leaves it: only the source that set it clears it.
  String? heldBy;

  /// The source-side id of the request this display is latched onto (oMLX
  /// `request_id`). The poller pins the FIRST request it sees and follows it
  /// until the server stops reporting it — without the pin, two concurrent
  /// requests (our reply + a queued helper pass) alternate entries across
  /// polls and the bar ping-pongs between two unrelated fractions
  /// (maintainer report, 2026-07-14).
  String? sourceRequestId;

  /// Display ratchet: the highest fraction already SHOWN for the current
  /// prompt pass. Interpolation runs ahead of the per-batch truth by design;
  /// when a real sample lands BELOW the extrapolated display, the bar must
  /// hold still until reality catches up — never slide backwards. Reset only
  /// when a genuinely new pass starts.
  double _shownFraction = 0;

  /// Bumped every time a new prompt pass begins (ratchet reset). The desktop
  /// bar keys its tween on this so an honest pass restart REBUILDS the bar at
  /// the new fraction instead of animating backwards through the old one
  /// (review finding: a 350ms reverse sweep per pass reset would re-create
  /// the very motion this fix removes).
  int passEpoch = 0;

  /// A genuinely new prompt pass: previous decode counts must never linger,
  /// the display ratchet restarts, and tween consumers re-key. Called from
  /// the new-pass detections below and by the oMLX poller when its request
  /// pin REBINDS (a cache-hit successor can open with counts so close to its
  /// predecessor's that count-based detection alone cannot see the seam).
  void beginNewPass() {
    genCurrent = 0;
    genTotal = 0;
    _restartPass();
  }

  void _restartPass() {
    promptConfirmed = 0;
    inFlightEnd = null;
    _anchors.clear();
    _shownFraction = 0;
    passEpoch++;
  }

  /// Record what is finished: [done] confirmed, the batch ending at
  /// [batchEnd] (if known) still running.
  void _confirm(int done, int? batchEnd, DateTime at) {
    promptConfirmed = done;
    inFlightEnd = batchEnd;
    _anchors.add(done, at);
  }

  void _promptFinished() {
    if (promptTotal > 0) promptCurrent = promptTotal;
    promptConfirmed = promptTotal;
    inFlightEnd = null;
  }

  /// Zero everything — called when a source stops so a backend switch (or
  /// return within the freshness window) can't show a prior request's
  /// counts.
  void reset() {
    promptCurrent = 0;
    promptTotal = 0;
    genCurrent = 0;
    genTotal = 0;
    updatedAt = null;
    waitingCount = 0;
    hintTokensPerSecond = null;
    sourceRequestId = null;
    _restartPass();
    _carry = '';
  }

  /// Prefill speed hint from the SOURCE (oMLX's avg_prefill_tps), used by
  /// consumers when no Kobold perf poll is available.
  double? hintTokensPerSecond;

  /// Tail of the previous chunk, carried so a progress line split across two
  /// stream chunks ("…(512 / 21" + "23 tokens)") still matches.
  String _carry = '';

  /// Direct write for polled sources (oMLX). Any prompt write invalidates
  /// stale decode counts from a previous request when the pass is new.
  ///
  /// New-pass detection tolerates small TOTAL drift: LM Studio's total is
  /// reconstructed from a rounded fraction (`tokens / progress`) and wobbles
  /// by a token or two between lines — without the tolerance every wobble
  /// counted as a "new request", resetting the display ratchet mid-pass.
  ///
  /// [inFlight]: [current] is the end of the batch being evaluated, not a
  /// finished count (LM Studio's llama.cpp runtime prints before decoding).
  void setPromptProgress(
    int current,
    int total, {
    DateTime? now,
    bool inFlight = false,
  }) {
    if (total <= 0) return;
    final at = now ?? DateTime.now();
    final tolerance = (total * 0.02).ceil().clamp(2, 64);
    final newPass =
        current < promptCurrent || (total - promptTotal).abs() > tolerance;
    if (newPass) beginNewPass();
    final previous = promptCurrent;
    promptCurrent = current.clamp(0, total);
    promptTotal = total;
    if (!inFlight) {
      _confirm(promptCurrent, null, at);
    } else if (newPass || promptCurrent > previous) {
      _confirm(newPass ? 0 : previous, promptCurrent, at);
    }
    updatedAt = at;
  }

  void setGenProgress(int current, int total, {DateTime? now}) {
    _promptFinished();
    genCurrent = current;
    genTotal = total;
    updatedAt = now ?? DateTime.now();
  }

  /// Feed one raw KoboldCpp console chunk. Returns true when anything
  /// changed (Generating lines arrive per token — callers throttle their
  /// notifications).
  bool ingest(String rawChunk, {DateTime? now}) {
    final chunk = _carry + rawChunk;
    var changed = false;
    var lastMatchEnd = 0;
    final at = now ?? DateTime.now();
    final p = _processRe.allMatches(chunk).lastOrNull;
    if (p != null) {
      // ANY prompt-progress line means a prompt pass is underway — the
      // previous request's decode is over, so its counts must never linger
      // (a same-size, cache-fast-forwarded prompt can open at "(N / N)").
      final afterDecode = genTotal > 0;
      genCurrent = 0;
      genTotal = 0;
      final current = int.parse(p.group(1)!);
      final total = int.parse(p.group(2)!);
      // Kobold console counts are exact — any regression, total change or
      // line after a decode IS a new pass, so the display ratchet restarts
      // honestly at its start.
      final newPass =
          afterDecode || current < promptCurrent || total != promptTotal;
      if (newPass) _restartPass();
      final previous = promptCurrent;
      promptCurrent = current;
      promptTotal = total;
      // The line names the batch about to run; the one before it is done.
      if (newPass || current > previous) {
        _confirm(newPass ? 0 : previous, current > 0 ? current : null, at);
      }
      lastMatchEnd = p.end;
      changed = true;
    }
    final g = _generateRe.allMatches(chunk).lastOrNull;
    if (g != null) {
      // Decoding implies the prompt pass finished even if we missed its
      // final progress line.
      _promptFinished();
      genCurrent = int.parse(g.group(1)!);
      genTotal = int.parse(g.group(2)!);
      if (g.end > lastMatchEnd) lastMatchEnd = g.end;
      changed = true;
    }
    // Carry only the UNMATCHED tail (capped) so a line split across chunks
    // still matches next time, but an already-consumed line can never
    // re-fire and zero live decode counts.
    final tailStart = lastMatchEnd > chunk.length - 64
        ? lastMatchEnd
        : chunk.length - 64;
    _carry = tailStart >= chunk.length
        ? ''
        : chunk.substring(tailStart < 0 ? 0 : tailStart);
    if (changed) updatedAt = at;
    return changed;
  }

  /// Feed one LM Studio runtime-log line. Returns true when it carried
  /// prompt progress.
  bool ingestLmStudioRuntimeLine(String line, {DateTime? now}) {
    final m = _lmsProgressRe.firstMatch(line);
    if (m == null) return false;
    final tokens = int.parse(m.group(1)!);
    final fraction = double.tryParse(m.group(2)!) ?? 0;
    if (fraction <= 0) return false;
    final total = (tokens / fraction).round();
    setPromptProgress(tokens, total, now: now, inFlight: true);
    return true;
  }

  /// 0..1 while a prompt pass is underway, 1.0 when it finished, null when
  /// no data (or stale per [freshAt] — a request may have been aborted).
  double? promptFraction({DateTime? now}) {
    if (promptTotal <= 0 || !freshAt(now ?? DateTime.now())) return null;
    return (promptCurrent / promptTotal).clamp(0.0, 1.0);
  }

  bool get isFresh => freshAt(DateTime.now());

  /// Whether the counts still describe a live request at [now]. Sources
  /// report once per BATCH, so the window is WIDE: 120s between updates,
  /// and while a batch is in flight up to [_inFlightFreshness] — an 8192
  /// batch deep in a long prompt on slow hardware runs 4-5 minutes with no
  /// line, and a 120s window dropped the bar mid-batch. Abandoned data
  /// self-heals: the next request's first progress write resets the counts,
  /// and consumers read this only while their own request is prefilling.
  bool freshAt(DateTime now) {
    final at = updatedAt;
    if (at == null) return false;
    final window = inFlightEnd != null
        ? _inFlightFreshness
        : const Duration(seconds: 120);
    return now.difference(at) <= window;
  }

  static const _inFlightFreshness = Duration(minutes: 30);

  /// [promptFraction] for what is really finished: the solid part of the
  /// bar. 1.0 only once the source confirmed the whole prompt.
  double? confirmedFraction({DateTime? now}) {
    if (promptFraction(now: now) == null) return null;
    return (promptConfirmed / promptTotal).clamp(0.0, 1.0);
  }

  /// Honest estimate of prompt progress BETWEEN confirmed counts: the last
  /// CONFIRMED count advances at a speed measured on THIS request, and stops
  /// short of the end of the batch in flight, so the guess can never claim
  /// tokens the source has not started. Returns 1.0 only when a source
  /// really said so.
  ///
  /// The speed, best first: the source's own speed for this request (oMLX),
  /// this pass's confirmed counts ([PrefillAnchors.rate]), this request's
  /// average since it was sent ([requestElapsed]), then [tokensPerSecond]
  /// (a previous request's speed, the weakest guess).
  ///
  /// MONOTONIC per pass (the display ratchet): when a real sample lands
  /// BELOW what was shown, the bar holds until reality catches up instead of
  /// sliding backwards (maintainer report, oMLX). A new pass resets it.
  double? estimatedPromptFraction({
    double? tokensPerSecond,
    Duration? requestElapsed,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final raw = confirmedFraction(now: at);
    if (raw == null) return null;
    double result;
    if (raw >= 1.0) {
      result = 1.0;
    } else {
      final rate = _rate(tokensPerSecond, requestElapsed, at);
      final from = _anchors.lastAt ?? updatedAt!;
      if (rate == null) {
        result = raw;
      } else {
        final dt = at.difference(from).inMilliseconds / 1000.0;
        final ceiling = inFlightEnd ?? promptTotal;
        final limit = promptConfirmed + 0.9 * (ceiling - promptConfirmed);
        final est = (promptConfirmed + rate * dt).clamp(0, limit).toDouble();
        result = (est / promptTotal).clamp(0.0, 0.99);
      }
    }
    if (result < _shownFraction) return _shownFraction;
    _shownFraction = result;
    return result;
  }

  /// Seconds until the prompt is read at the speed [estimatedPromptFraction]
  /// uses, from what it last showed; null when no speed is known.
  double? estimatedPromptSecondsLeft({
    double? tokensPerSecond,
    Duration? requestElapsed,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final raw = confirmedFraction(now: at);
    if (raw == null || raw >= 1.0) return null;
    final rate = _rate(tokensPerSecond, requestElapsed, at);
    if (rate == null) return null;
    final shown = _shownFraction > raw ? _shownFraction : raw;
    return promptTotal * (1 - shown) / rate;
  }

  double? _rate(double? fallback, Duration? requestElapsed, DateTime now) {
    final hint = hintTokensPerSecond;
    if (hint != null && hint > 0) return hint;
    final measured = _anchors.rate;
    if (measured != null && measured > 0) return measured;
    final lastAt = _anchors.lastAt;
    if (requestElapsed != null && lastAt != null && promptConfirmed > 0) {
      final seconds =
          lastAt.difference(now.subtract(requestElapsed)).inMilliseconds /
          1000.0;
      if (seconds > 0) return promptConfirmed / seconds;
    }
    return (fallback != null && fallback > 0) ? fallback : null;
  }
}
