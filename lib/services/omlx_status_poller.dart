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
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/live_gen_progress.dart';

/// Live status source for the oMLX backend (truthful status bar).
///
/// oMLX's admin API exposes exactly what the black-box wait needs
/// (`GET {base}/admin/api/stats`, no auth from localhost, responds even
/// mid-generation; shapes captured empirically 2026-07-14):
///
///   active_models.models[].prefilling[]  = {processed, total, ...}
///   active_models.models[].generating[]  = {generated_tokens, max_tokens,
///                                           prompt_tokens, tokens_per_second}
///   active_models.models[].waiting[]     = queued requests
///   avg_prefill_tps                      = interpolation speed hint
///
/// NB: do NOT poll `/admin/api/models` for this — that endpoint can stall
/// while the engine is generating; `/admin/api/stats` stays responsive.
///
/// The poller runs a 1s timer but only issues HTTP requests while
/// [isActive] returns true (i.e. a chat generation is in flight), so an idle
/// app never touches the server.
class OmlxStatusPoller {
  OmlxStatusPoller({required this.isActive});

  /// Gate: only poll while a generation is actually running.
  final bool Function() isActive;

  final LiveGenProgress progress = LiveGenProgress();

  Timer? _timer;
  String? _adminBase;
  bool _requestInFlight = false;
  bool _wasActive = false;

  /// [apiUrl] is the OpenAI-style base the app is configured with
  /// (e.g. `http://localhost:8000/v1`); the admin API lives beside it.
  void start(String apiUrl) {
    _adminBase = apiUrl.replaceFirst(RegExp(r'/v1/?$'), '');
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _adminBase = null;
    progress.reset();
  }

  Future<void> _poll() async {
    final base = _adminBase;
    final active = isActive();
    // A generation just started: clear the previous one's counts, pin, and
    // ratchet so the bar can never open on a stale ~99% from the last
    // request (review finding — the stale window lasted until the first
    // real sample arrived).
    if (active && !_wasActive) progress.reset();
    _wasActive = active;
    if (base == null || !active || _requestInFlight) return;
    _requestInFlight = true;
    try {
      final resp = await http
          .get(Uri.parse('$base/admin/api/stats'))
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return;
      applyOmlxStats(jsonDecode(resp.body), progress);
    } catch (e) {
      // Transient failures are expected (server restarting, wrong backend
      // selected while the timer drains) — never surface them.
      debugPrint('[OmlxStatus] poll skipped: $e');
    } finally {
      _requestInFlight = false;
    }
  }
}

/// Pure mapping from an oMLX `/admin/api/stats` payload into the shared
/// progress struct (split out for unit tests).
void applyOmlxStats(dynamic stats, LiveGenProgress progress) {
  if (stats is! Map) return;
  final activeModels = stats['active_models'];
  if (activeModels is! Map) return;
  final models = activeModels['models'];
  if (models is! List) return;

  final avgPrefill = stats['avg_prefill_tps'];
  if (avgPrefill is num && avgPrefill > 0) {
    progress.hintTokensPerSecond = avgPrefill.toDouble();
  }

  final prefills = <Map>[];
  final gens = <Map>[];
  var waiting = 0;
  for (final m in models) {
    if (m is! Map) continue;
    prefills.addAll((m['prefilling'] as List?)?.whereType<Map>() ?? const []);
    gens.addAll((m['generating'] as List?)?.whereType<Map>() ?? const []);
    waiting += (m['waiting'] as List?)?.length ?? 0;
  }

  progress.waitingCount = waiting;

  // Request pinning: entries carry request_id, so latch onto ONE request and
  // follow it across polls (prefill → decode) until the server stops
  // reporting it. Without the pin, two in-flight requests (our reply + a
  // queued helper pass) alternate firstOrNull wins and the bar ping-pongs
  // between two unrelated fractions (maintainer report, 2026-07-14). Only
  // when the pinned request is gone does the display move on — one honest
  // restart per request, never per poll.
  Map? entryFor(List<Map> list, String? id) => id == null
      ? null
      : list.where((e) => e['request_id']?.toString() == id).firstOrNull;

  Map? prefill = entryFor(prefills, progress.sourceRequestId);
  Map? generating = entryFor(gens, progress.sourceRequestId);
  if (prefill == null && generating == null) {
    prefill = prefills.firstOrNull;
    generating = prefill == null ? gens.firstOrNull : null;
    final previous = progress.sourceRequestId;
    final next = ((prefill ?? generating)?['request_id'])?.toString();
    // Pin REBIND = a different request now owns the display. Count-based
    // new-pass detection alone can miss the seam (a cache-hit successor can
    // open with counts nearly identical to its predecessor's finish), which
    // would let the old request's decode counts and ratchet leak into the
    // new one (review finding) — so the rebind itself declares the new pass.
    if (next != null && previous != null && next != previous) {
      progress.beginNewPass();
    }
    progress.sourceRequestId = next;
  }

  if (prefill != null) {
    // The entry's own live speed beats the server-lifetime average for
    // interpolation: the average mixes cache-hit instant prefills and other
    // models, which made the extrapolated bar overshoot (then stall on the
    // ratchet) far more than needed.
    final speed = (prefill['speed'] as num?)?.toDouble();
    if (speed != null && speed > 0) progress.hintTokensPerSecond = speed;
    final processed = (prefill['processed'] as num?)?.toInt() ?? 0;
    final total = (prefill['total'] as num?)?.toInt() ?? 0;
    if (total > 0) progress.setPromptProgress(processed, total);
    return;
  }
  if (generating != null) {
    final promptTokens = (generating['prompt_tokens'] as num?)?.toInt() ?? 0;
    if (promptTokens > 0) {
      // Decode running → the prompt pass is complete.
      progress.setPromptProgress(promptTokens, promptTokens);
    }
    progress.setGenProgress(
      (generating['generated_tokens'] as num?)?.toInt() ?? 0,
      (generating['max_tokens'] as num?)?.toInt() ?? 0,
    );
  }
}
