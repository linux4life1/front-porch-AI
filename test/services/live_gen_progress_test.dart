// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the live per-request progress parser fed by the managed
// KoboldCpp process's console output. Line shapes captured empirically from
// the bundled binary (they arrive WITHOUT newlines between updates, and the
// bracket tag varies by build).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/live_gen_progress.dart';

void main() {
  test('parses batch-glued Processing Prompt updates, last match wins', () {
    final p = LiveGenProgress();
    final changed = p.ingest(
      'Processing Prompt [BATCH] (0 / 284 tokens)'
      'Processing Prompt [BATCH] (284 / 284 tokens)',
    );
    expect(changed, isTrue);
    expect(p.promptCurrent, 284);
    expect(p.promptTotal, 284);
    expect(p.promptFraction(), 1.0);
  });

  test('accepts [BLAS], other tags, and tagless variants', () {
    final p = LiveGenProgress();
    p.ingest('Processing Prompt [BLAS] (512 / 2123 tokens)');
    expect(p.promptCurrent, 512);
    expect(p.promptTotal, 2123);
    p.ingest('Processing Prompt (1024 / 2123 tokens)');
    expect(p.promptCurrent, 1024);
    expect(p.promptFraction(), closeTo(1024 / 2123, 0.001));
  });

  test('Generating lines mark the prompt pass complete and track decode', () {
    final p = LiveGenProgress();
    p.ingest('Processing Prompt [BATCH] (512 / 900 tokens)');
    p.ingest('Generating (3 / 40 tokens)Generating (4 / 40 tokens)');
    expect(p.promptCurrent, 900); // decode implies prompt finished
    expect(p.genCurrent, 4);
    expect(p.genTotal, 40);
  });

  test('a new request resets stale decode counts', () {
    final p = LiveGenProgress();
    p.ingest('Processing Prompt [BATCH] (900 / 900 tokens)');
    p.ingest('Generating (40 / 40 tokens)');
    // Next request starts from 0 with a different total.
    p.ingest('Processing Prompt [BATCH] (0 / 5000 tokens)');
    expect(p.genCurrent, 0);
    expect(p.genTotal, 0);
    expect(p.promptCurrent, 0);
    expect(p.promptTotal, 5000);
  });

  test('same-size cache-fast-forwarded prompt still resets decode counts '
      '(review finding: it can open at "(N / N)")', () {
    final p = LiveGenProgress();
    p.ingest('Processing Prompt [BATCH] (2000 / 2000 tokens)');
    p.ingest('Generating (40 / 40 tokens)');
    // Request B: identical size, prefill fully cache-hit — first line is
    // already complete. The old decreasing-cur heuristic kept A's counts.
    p.ingest('Processing Prompt [BATCH] (2000 / 2000 tokens)');
    expect(p.genCurrent, 0);
    expect(p.genTotal, 0);
  });

  test('a progress line split across two chunks still matches (carry), and a '
      'consumed line never re-fires to zero live decode counts', () {
    final p = LiveGenProgress();
    p.ingest('Processing Prompt [BATCH] (512 / 21');
    expect(p.promptTotal, 0); // partial — nothing matched yet
    p.ingest('23 tokens)');
    expect(p.promptCurrent, 512);
    expect(p.promptTotal, 2123);
    // Decode starts; later chunks without any prompt line must not let the
    // carried (already-consumed) prompt text reset the decode counts.
    p.ingest('Generating (5 / 40 tokens)');
    p.ingest('some unrelated log line');
    expect(p.genCurrent, 5);
    expect(p.genTotal, 40);
  });

  test('estimatedPromptFraction interpolates between per-batch lines and '
      'never claims completion the console has not printed', () {
    final p = LiveGenProgress();
    final t0 = DateTime.now();
    p.ingest('Processing Prompt [BATCH] (0 / 10000 tokens)', now: t0);
    // No speed anchor → raw fraction, no guessing.
    expect(p.estimatedPromptFraction(tokensPerSecond: null, now: t0), 0.0);
    // 5s later at 400 t/s the estimate is ~2000 tokens = 20%.
    final est = p.estimatedPromptFraction(
      tokensPerSecond: 400,
      now: t0.add(const Duration(seconds: 5)),
    );
    expect(est, closeTo(0.2, 0.01));
    // A wild overestimate is capped below 100% — completion only comes from
    // a real console line.
    final capped = p.estimatedPromptFraction(
      tokensPerSecond: 400,
      now: t0.add(const Duration(minutes: 1)),
    );
    expect(capped, lessThanOrEqualTo(0.99));
    // A real completion line reports exactly 1.0.
    p.ingest('Processing Prompt [BATCH] (10000 / 10000 tokens)', now: t0);
    expect(p.estimatedPromptFraction(tokensPerSecond: 400, now: t0), 1.0);
  });

  test('display ratchet: a real sample landing below the extrapolated display '
      'holds the bar instead of yanking it backwards (the oMLX ping-pong)', () {
    final p = LiveGenProgress();
    final t0 = DateTime.now();
    p.setPromptProgress(2000, 10000, now: t0);
    // Interpolation runs ahead: shown ≈ 45% while the truth is 20%.
    final ahead = p.estimatedPromptFraction(
      tokensPerSecond: 500,
      now: t0.add(const Duration(seconds: 5)),
    )!;
    expect(ahead, closeTo(0.45, 0.01));
    // Next poll's REAL count (3000/10000 = 30%) is below what was shown —
    // the display must hold at 45%, not snap back.
    final t1 = t0.add(const Duration(seconds: 6));
    p.setPromptProgress(3000, 10000, now: t1);
    expect(p.estimatedPromptFraction(tokensPerSecond: null, now: t1), ahead);
    // Reality catches up and passes the ratchet → display climbs again.
    final t2 = t0.add(const Duration(seconds: 12));
    p.setPromptProgress(6000, 10000, now: t2);
    expect(
      p.estimatedPromptFraction(tokensPerSecond: null, now: t2),
      closeTo(0.6, 0.001),
    );
  });

  test('a new prompt pass resets the ratchet so the bar restarts honestly',
      () {
    final p = LiveGenProgress();
    final t0 = DateTime.now();
    p.setPromptProgress(9000, 10000, now: t0);
    expect(
      p.estimatedPromptFraction(tokensPerSecond: null, now: t0),
      closeTo(0.9, 0.001),
    );
    // A different request begins (regressed count, new total): the ratchet
    // must NOT pin the new bar at the old request's 90%.
    p.setPromptProgress(100, 4000, now: t0.add(const Duration(seconds: 1)));
    expect(
      p.estimatedPromptFraction(
        tokensPerSecond: null,
        now: t0.add(const Duration(seconds: 1)),
      ),
      closeTo(0.025, 0.001),
    );
  });

  test('passEpoch bumps on new pass and on reset — the tween re-key signal',
      () {
    final p = LiveGenProgress();
    final e0 = p.passEpoch;
    p.setPromptProgress(100, 4000);
    final e1 = p.passEpoch; // first write = new pass (total 0 → 4000)
    expect(e1, greaterThan(e0));
    p.setPromptProgress(2000, 4000);
    expect(p.passEpoch, e1); // same pass — no bump
    p.setPromptProgress(50, 9000);
    expect(p.passEpoch, greaterThan(e1)); // regression + new total
    final e2 = p.passEpoch;
    p.reset();
    expect(p.passEpoch, greaterThan(e2));
  });

  test('LM Studio total wobble (rounded-fraction reconstruction) is the same '
      'pass — no decode reset, no ratchet reset', () {
    final p = LiveGenProgress();
    final t0 = DateTime.now();
    p.ingestLmStudioRuntimeLine(
      'slot update_slots: id 2 | task 46 | prompt processing progress, '
      'n_tokens = 512, batch.n_tokens = 512, progress = 0.168754',
      now: t0,
    ); // total ≈ 3034
    final shown = p.estimatedPromptFraction(
      tokensPerSecond: 300,
      now: t0.add(const Duration(seconds: 3)),
    )!;
    // Second line reconstructs a slightly different total (≈ 3037) — within
    // tolerance, same pass: the display never moves backwards.
    p.ingestLmStudioRuntimeLine(
      'slot update_slots: id 2 | task 46 | prompt processing progress, '
      'n_tokens = 1024, batch.n_tokens = 512, progress = 0.337175',
      now: t0.add(const Duration(seconds: 4)),
    );
    final next = p.estimatedPromptFraction(
      tokensPerSecond: null,
      now: t0.add(const Duration(seconds: 4)),
    )!;
    expect(next, greaterThanOrEqualTo(shown));
  });

  test('non-progress chunks change nothing', () {
    final p = LiveGenProgress();
    expect(p.ingest('llama_context: n_batch = 8320'), isFalse);
    expect(p.promptFraction(), isNull);
  });

  test('LM Studio runtime line: cumulative tokens + exact fraction → counts '
      '(captured shape)', () {
    final p = LiveGenProgress();
    final hit = p.ingestLmStudioRuntimeLine(
      'slot update_slots: id  2 | task 46 | prompt processing progress, '
      'n_tokens = 512, batch.n_tokens = 512, progress = 0.168754',
    );
    expect(hit, isTrue);
    expect(p.promptCurrent, 512);
    expect(p.promptTotal, (512 / 0.168754).round()); // ≈ 3034
    expect(p.ingestLmStudioRuntimeLine('srv update: cache state'), isFalse);
  });

  test('staleness: old data stops reporting a fraction, but the window is '
      'wide enough for big-batch gaps between progress lines', () {
    final p = LiveGenProgress();
    p.ingest(
      'Processing Prompt (10 / 100 tokens)',
      now: DateTime.now().subtract(const Duration(seconds: 60)),
    );
    // 60s since the last line (a realistic 8192-batch gap) is still fresh.
    expect(p.promptFraction(), isNotNull);
    expect(p.isFresh, isTrue);

    final stale = LiveGenProgress();
    stale.ingest(
      'Processing Prompt (10 / 100 tokens)',
      now: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    expect(stale.promptFraction(), isNull);
    expect(stale.isFresh, isFalse);
  });
}
