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

  int promptCurrent = 0;
  int promptTotal = 0;
  int genCurrent = 0;
  int genTotal = 0;
  DateTime? updatedAt;

  /// How many requests the source reports queued (oMLX `waiting[]`). The
  /// source cannot tell WHOSE they are (ours vs someone waiting on us), so
  /// consumers must state the fact neutrally ("1 request queued") — never
  /// attribute the wait (review finding: attribution here was invertible).
  int waitingCount = 0;

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
    _shownFraction = 0;
    passEpoch++;
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
    _shownFraction = 0;
    passEpoch++;
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
  void setPromptProgress(int current, int total, {DateTime? now}) {
    if (total <= 0) return;
    final tolerance = (total * 0.02).ceil().clamp(2, 64);
    final newPass =
        current < promptCurrent || (total - promptTotal).abs() > tolerance;
    if (newPass) beginNewPass();
    promptCurrent = current.clamp(0, total);
    promptTotal = total;
    updatedAt = now ?? DateTime.now();
  }

  void setGenProgress(int current, int total, {DateTime? now}) {
    if (promptTotal > 0) promptCurrent = promptTotal;
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
    final p = _processRe.allMatches(chunk).lastOrNull;
    if (p != null) {
      // ANY prompt-progress line means a prompt pass is underway — the
      // previous request's decode is over, so its counts must never linger
      // (a same-size, cache-fast-forwarded prompt can open at "(N / N)").
      genCurrent = 0;
      genTotal = 0;
      final current = int.parse(p.group(1)!);
      final total = int.parse(p.group(2)!);
      // Kobold console counts are exact — any regression or total change IS
      // a new pass, so the display ratchet restarts honestly at its start.
      if (current < promptCurrent || total != promptTotal) {
        _shownFraction = 0;
        passEpoch++;
      }
      promptCurrent = current;
      promptTotal = total;
      lastMatchEnd = p.end;
      changed = true;
    }
    final g = _generateRe.allMatches(chunk).lastOrNull;
    if (g != null) {
      // Decoding implies the prompt pass finished even if we missed its
      // final progress line.
      if (promptTotal > 0) promptCurrent = promptTotal;
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
    if (changed) updatedAt = now ?? DateTime.now();
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
    setPromptProgress(tokens, total, now: now);
    return true;
  }

  /// 0..1 while a prompt pass is underway, 1.0 when it finished, null when
  /// no data (or stale beyond [freshness] — a request may have been aborted).
  ///
  /// The window is WIDE on purpose: sources report once per BATCH, so with
  /// --batchsize 8192 on slow hardware consecutive updates can be 30-60s
  /// apart — a short window would flicker the truthful display away
  /// mid-prefill. Abandoned data self-heals: the next request's first
  /// progress write resets the counts.
  double? promptFraction({Duration freshness = const Duration(seconds: 120)}) {
    final at = updatedAt;
    if (at == null || promptTotal <= 0) return null;
    if (DateTime.now().difference(at) > freshness) return null;
    return (promptCurrent / promptTotal).clamp(0.0, 1.0);
  }

  bool get isFresh =>
      updatedAt != null &&
      DateTime.now().difference(updatedAt!) < const Duration(seconds: 120);

  /// Smooth, honest estimate of prompt progress BETWEEN batch updates: the
  /// last REAL count advances at the measured prefill speed, capped below
  /// the next unconfirmed token so the bar never claims completion the
  /// source hasn't reported. Returns 1.0 only when a source really said so.
  ///
  /// MONOTONIC per pass (the display ratchet): extrapolation can run ahead
  /// of the per-batch truth, and before the ratchet the next real sample
  /// yanked the bar backwards — a visible forward/backward "ping-pong" every
  /// poll (maintainer report, oMLX). Now the shown fraction only ever climbs
  /// or holds within one prompt pass; overshoot reads as the bar pausing
  /// until the real count catches up. A new pass resets the ratchet.
  double? estimatedPromptFraction({
    double? tokensPerSecond,
    DateTime? now,
  }) {
    final raw = promptFraction();
    if (raw == null) return null;
    double result;
    if (raw >= 1.0) {
      result = 1.0;
    } else {
      final tps = tokensPerSecond ?? hintTokensPerSecond;
      if (tps == null || tps <= 0 || updatedAt == null) {
        result = raw;
      } else {
        final dt =
            (now ?? DateTime.now()).difference(updatedAt!).inMilliseconds /
            1000.0;
        final est = promptCurrent + tps * dt;
        final capped = est.clamp(0, promptTotal - 1).toDouble();
        result = (capped / promptTotal).clamp(0.0, 0.99);
      }
    }
    if (result < _shownFraction) return _shownFraction;
    _shownFraction = result;
    return result;
  }
}
