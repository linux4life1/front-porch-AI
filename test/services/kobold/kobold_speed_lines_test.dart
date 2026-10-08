// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The speed line KoboldCpp prints after each request, as the speed test
// reads it: KoboldCpp starts the line with its line break and ends it only
// when it next prints, and a pipe hands the output over in pieces. Each
// request's line is counted once, whole. The lines are copied from a real
// KoboldCpp 1.122.1 log.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

String _line(int read, String readS, int wrote, String writeS) =>
    '\n[10:49:15] CtxLimit:${read + wrote}/16384, Init:0.02s, '
    'Processed:$read in ${readS}s (3212.08T/s), '
    'Generated:$wrote/$wrote in ${writeS}s (37.66T/s), Total:6.00s';

void main() {
  group('the speed lines', () {
    test('a line ended only by the next print counts once, as soon as it '
        'is there', () {
      final lines = KoboldSpeedLines();
      lines.add(_line(2181, '0.68', 200, '5.31'));
      expect(lines.seen, 1);
      expect(lines.last!.read, 2181);
      lines.add('\nProcessing Prompt [BATCH] (512 / 2000 tokens)');
      expect(lines.seen, 1);
    });

    test('a line cut across two reads counts once, with its whole numbers', () {
      final lines = KoboldSpeedLines();
      final whole = _line(2181, '0.68', 200, '5.31');
      final cut = whole.indexOf('0.68') + 3; // "...in 0.6" | "8s (..."
      lines.add(whole.substring(0, cut));
      expect(lines.seen, 0);
      lines.add(whole.substring(cut));
      expect(lines.seen, 1);
      expect(lines.last!.readSeconds, 0.68);
      lines.add('\n');
      expect(lines.seen, 1);
    });

    test('two requests with the same numbers count twice', () {
      final lines = KoboldSpeedLines();
      lines.add(_line(52, '0.01', 16, '0.40'));
      lines.add(_line(52, '0.01', 16, '0.40'));
      lines.add('\n');
      expect(lines.seen, 2);
    });

    test("waiting past a mark takes the next request's line, not one "
        'counted before', () async {
      final lines = KoboldSpeedLines();
      lines.add(_line(300, '0.10', 16, '0.40'));
      final mark = lines.seen;
      final next = lines.after(mark);
      // The earlier line ends when the next request starts printing.
      lines.add('\nProcessing Prompt [BATCH] (512 / 2181 tokens)');
      lines.add(_line(2181, '0.68', 200, '5.31'));
      expect((await next)!.read, 2181);
      expect((await lines.after(mark))!.read, 2181);
    });

    test('a wait with nothing printed gives up with nothing', () async {
      final lines = KoboldSpeedLines();
      expect(
        await lines.after(0, timeout: const Duration(milliseconds: 20)),
        isNull,
      );
    });
  });

  group('a whole turn from one reply', () {
    test('reading 1,000 tokens and writing 200 at its speeds', () {
      final s = parseKoboldSpeed(_line(2000, '1.00', 200, '5.00'))!;
      expect(koboldTurnSecondsOf(s), closeTo(1000 / 2000 + 200 / 40, 1e-9));
    });

    test('a reply too short to time says nothing', () {
      expect(
        koboldTurnSecondsOf(parseKoboldSpeed(_line(52, '0.00', 1, '0.06'))!),
        isNull,
      );
    });
  });

  group('the load clock', () {
    test('a load is timed from its start to the model answering', () async {
      final clock = KoboldLoadClock()..started();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      clock.ready('/m/a.gguf');
      expect(
        clock.lastFor('/m/a.gguf')!.inMilliseconds,
        greaterThanOrEqualTo(30),
      );
    });

    test('a ready with no load begun says nothing', () {
      final clock = KoboldLoadClock()..ready('/m/a.gguf');
      expect(clock.lastFor('/m/a.gguf'), isNull);
    });
  });
}
