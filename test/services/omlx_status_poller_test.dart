// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the oMLX `/admin/api/stats` → LiveGenProgress mapping. Payload
// shapes captured empirically from oMLX v0.5.1 (2026-07-14).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/live_gen_progress.dart';
import 'package:front_porch_ai/services/omlx_status_poller.dart';

Map<String, dynamic> stats({
  List<Map<String, dynamic>> prefilling = const [],
  List<Map<String, dynamic>> generating = const [],
  List<Map<String, dynamic>> waiting = const [],
  double avgPrefillTps = 1009.7,
}) => {
  'avg_prefill_tps': avgPrefillTps,
  'active_models': {
    'models': [
      {
        'id': 'gemma-4-31b-it-6bit-abliterated-mlx',
        'active_requests': generating.length + prefilling.length,
        'prefilling': prefilling,
        'generating': generating,
        'waiting': waiting,
      },
    ],
  },
};

void main() {
  test('prefilling entry maps to prompt counts + speed hint', () {
    final p = LiveGenProgress();
    applyOmlxStats(
      stats(
        prefilling: [
          {
            'request_id': 'x',
            'processed': 1024,
            'total': 4456,
            'phase': 'prefill',
          },
        ],
      ),
      p,
    );
    expect(p.promptCurrent, 1024);
    expect(p.promptTotal, 4456);
    expect(p.hintTokensPerSecond, closeTo(1009.7, 0.1));
    expect(p.waitingCount, 0);
  });

  test('generating entry marks prompt done and tracks decode', () {
    final p = LiveGenProgress();
    applyOmlxStats(
      stats(
        generating: [
          {
            'request_id': 'x',
            'generated_tokens': 921,
            'tokens_per_second': 6.7,
            'prompt_tokens': 5079,
            'max_tokens': 4000,
          },
        ],
      ),
      p,
    );
    expect(p.promptCurrent, 5079);
    expect(p.promptTotal, 5079);
    expect(p.promptFraction(), 1.0);
    expect(p.genCurrent, 921);
    expect(p.genTotal, 4000);
  });

  test('waiting queue count is reported neutrally and clears', () {
    final p = LiveGenProgress();
    applyOmlxStats(
      stats(waiting: [{'request_id': 'q'}]),
      p,
    );
    expect(p.waitingCount, 1);
    applyOmlxStats(stats(), p);
    expect(p.waitingCount, 0);
  });

  test('malformed payloads are ignored safely', () {
    final p = LiveGenProgress();
    applyOmlxStats(null, p);
    applyOmlxStats({'active_models': 'nope'}, p);
    applyOmlxStats({'active_models': {'models': 42}}, p);
    expect(p.promptTotal, 0);
  });

  test('request pinning: entry order flipping between polls cannot ping-pong '
      'the display', () {
    final p = LiveGenProgress();
    Map<String, dynamic> req(String id, int processed, int total) =>
        {'request_id': id, 'processed': processed, 'total': total};

    // Poll 1: our reply (a) leads the list — pin latches onto it.
    applyOmlxStats(stats(prefilling: [req('a', 2048, 9000), req('b', 100, 1500)]), p);
    expect(p.sourceRequestId, 'a');
    expect(p.promptCurrent, 2048);
    expect(p.promptTotal, 9000);

    // Poll 2: the server reorders the list — the pre-pin code would have
    // jumped to b's 100/1500; the pin keeps following a.
    applyOmlxStats(stats(prefilling: [req('b', 400, 1500), req('a', 4096, 9000)]), p);
    expect(p.sourceRequestId, 'a');
    expect(p.promptCurrent, 4096);
    expect(p.promptTotal, 9000);
  });

  test('pin follows its request from prefill into decode, then releases when '
      'the request vanishes', () {
    final p = LiveGenProgress();
    applyOmlxStats(
      stats(prefilling: [{'request_id': 'a', 'processed': 8000, 'total': 9000}]),
      p,
    );
    expect(p.sourceRequestId, 'a');

    // Same request moves to generating: prompt completes, decode tracked —
    // even with another request's prefill now in the list.
    applyOmlxStats(
      stats(
        prefilling: [{'request_id': 'b', 'processed': 10, 'total': 1500}],
        generating: [
          {'request_id': 'a', 'generated_tokens': 42, 'prompt_tokens': 9000, 'max_tokens': 800},
        ],
      ),
      p,
    );
    expect(p.sourceRequestId, 'a');
    expect(p.promptFraction(), 1.0);
    expect(p.genCurrent, 42);

    // a finishes: pin releases and latches the next live request (one honest
    // restart, not per-poll alternation).
    applyOmlxStats(
      stats(prefilling: [{'request_id': 'b', 'processed': 700, 'total': 1500}]),
      p,
    );
    expect(p.sourceRequestId, 'b');
    expect(p.promptCurrent, 700);
    expect(p.promptTotal, 1500);
  });

  test('pin REBIND declares a new pass even when the successor opens with '
      'near-identical counts (cache-hit seam)', () {
    final p = LiveGenProgress();
    // Request a finishes prefill and decodes a while.
    applyOmlxStats(
      stats(
        generating: [
          {'request_id': 'a', 'generated_tokens': 421, 'prompt_tokens': 9000, 'max_tokens': 800},
        ],
      ),
      p,
    );
    expect(p.genCurrent, 421);
    final epochBefore = p.passEpoch;

    // a vanishes; cache-hit successor b opens ALREADY at 9000/9000 — count
    // heuristics see "same pass", only the rebind knows better. a's decode
    // counts must not leak into b's display.
    applyOmlxStats(
      stats(prefilling: [{'request_id': 'b', 'processed': 9000, 'total': 9000}]),
      p,
    );
    expect(p.sourceRequestId, 'b');
    expect(p.genCurrent, 0);
    expect(p.passEpoch, greaterThan(epochBefore));
  });

  test('per-entry live speed beats the server-lifetime average as the '
      'interpolation hint', () {
    final p = LiveGenProgress();
    applyOmlxStats(
      stats(
        avgPrefillTps: 1009.7,
        prefilling: [
          {'request_id': 'a', 'processed': 512, 'total': 9000, 'speed': 187.5},
        ],
      ),
      p,
    );
    expect(p.hintTokensPerSecond, closeTo(187.5, 0.1));

    // No per-entry speed → the average remains the fallback.
    final q = LiveGenProgress();
    applyOmlxStats(
      stats(
        avgPrefillTps: 1009.7,
        prefilling: [
          {'request_id': 'a', 'processed': 512, 'total': 9000},
        ],
      ),
      q,
    );
    expect(q.hintTokensPerSecond, closeTo(1009.7, 0.1));
  });
}
