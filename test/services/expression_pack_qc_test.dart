// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for ExpressionPackQc (advisory Vision QC over a finished expression
// pack), driven through a fake VisionEvalFn so no LLM or HTTP is involved.
// Also covers the reroll-reset contract on ExpressionPackSession: a
// regenerated slot must drop its stale verdict.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/expression_pack_qc.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';

ExpressionSlot doneSlot(String emotion, List<int> bytes) {
  final slot = ExpressionSlot(emotion);
  slot.state = ExpressionSlotState.done;
  slot.bytes = Uint8List.fromList(bytes);
  return slot;
}

/// Fake VisionEvalFn that captures every call and pops canned replies.
class FakeEval {
  FakeEval(this.replies);

  final List<String?> replies;
  final prompts = <String>[];
  final images = <List<String>>[];

  Future<String?> call({
    required String prompt,
    required List<String> imagesB64,
  }) async {
    prompts.add(prompt);
    images.add(imagesB64);
    return replies.removeAt(0);
  }
}

void main() {
  const base = 'QkFTRQ==';

  group('ExpressionPackQc.run', () {
    test('stamps pass/fail/mixed verdicts; flaw rides note without flipping '
        'pass; prompts carry the emotion; images ride [base, slot] in order',
        () async {
      final slots = [
        doneSlot('happy', [1, 2]),
        doneSlot('angry', [3, 4]),
        doneSlot('sad', [5, 6]),
      ];
      final fake = FakeEval([
        '{"same_person": true, "expression": "happy", "flaw": "none"}',
        'Sure! {"same_person": false, "expression": "angry", '
            '"flaw": "warped face"}',
        '{"same_person": true, "expression": "sad", '
            '"flaw": "extra finger"}',
      ]);
      final qc = ExpressionPackQc(
        slots: slots,
        baseImageB64: base,
        fire: fake.call,
      );

      await qc.run();

      expect(slots[0].qc!.pass, isTrue);
      expect(slots[0].qc!.note, '');
      expect(slots[1].qc!.pass, isFalse);
      expect(slots[1].qc!.samePerson, isFalse);
      expect(slots[1].qc!.note, 'warped face');
      // A real flaw does NOT flip pass by itself — both booleans were true.
      expect(slots[2].qc!.pass, isTrue);
      expect(slots[2].qc!.note, 'extra finger');

      expect(qc.checkedCount, 3);
      expect(qc.totalToCheck, 3);
      expect(qc.flaggedCount, 1);
      expect(qc.unparsedCount, 0);
      expect(qc.isRunning, isFalse);

      // The target emotion must NOT be leaked to the model — it has to NAME
      // what it sees (blind/sycophantic setups can't pass by echoing "true").
      expect(fake.prompts[0], isNot(contains('happy')));
      expect(fake.prompts[0], contains('naming the facial expression'));
      for (var i = 0; i < slots.length; i++) {
        expect(fake.images[i], [base, base64Encode(slots[i].bytes!)]);
      }
    });

    test('only done slots with bytes are checked', () async {
      final pending = ExpressionSlot('happy'); // stays pending
      final failed = ExpressionSlot('angry')
        ..state = ExpressionSlotState.failed;
      final done = doneSlot('sad', [7]);
      final fake = FakeEval([
        '{"same_person": true, "expression": "sad", "flaw": "none"}',
      ]);
      final qc = ExpressionPackQc(
        slots: [pending, failed, done],
        baseImageB64: base,
        fire: fake.call,
      );

      await qc.run();

      expect(fake.prompts, hasLength(1));
      expect(qc.totalToCheck, 1);
      expect(pending.qc, isNull);
      expect(failed.qc, isNull);
      expect(done.qc, isNotNull);
    });

    test('unparseable and null replies leave qc null and count as unparsed',
        () async {
      final slots = [doneSlot('happy', [1]), doneSlot('angry', [2])];
      final fake = FakeEval(['they look pretty similar to me!', null]);
      final qc = ExpressionPackQc(
        slots: slots,
        baseImageB64: base,
        fire: fake.call,
      );

      await qc.run();

      expect(slots[0].qc, isNull);
      expect(slots[1].qc, isNull);
      expect(qc.unparsedCount, 2);
      expect(qc.checkedCount, 2);
      expect(qc.flaggedCount, 0);
    });

    test('cancel between slots leaves the rest unchecked', () async {
      final slots = [doneSlot('happy', [1]), doneSlot('angry', [2])];
      late ExpressionPackQc qc;
      var calls = 0;
      Future<String?> fire({
        required String prompt,
        required List<String> imagesB64,
      }) async {
        calls++;
        qc.cancel(); // requested mid-flight → consulted between slots
        return '{"same_person": true, "expression": "happy", "flaw": "none"}';
      }

      qc = ExpressionPackQc(slots: slots, baseImageB64: base, fire: fire);
      await qc.run();

      expect(calls, 1);
      expect(slots[0].qc, isNotNull); // in-flight slot still finished
      expect(slots[1].qc, isNull);
      expect(qc.checkedCount, 1);
      expect(qc.isRunning, isFalse);
    });

    test('run() is reentrancy-guarded (second call is a no-op)', () async {
      final slots = [doneSlot('happy', [1])];
      final gate = Completer<void>();
      var calls = 0;
      Future<String?> fire({
        required String prompt,
        required List<String> imagesB64,
      }) async {
        calls++;
        await gate.future;
        return '{"same_person": true, "expression": "happy", "flaw": "none"}';
      }

      final qc = ExpressionPackQc(
        slots: slots,
        baseImageB64: base,
        fire: fire,
      );
      final first = qc.run();
      expect(qc.isRunning, isTrue);
      final second = qc.run(); // must not start a second pass
      gate.complete();
      await first;
      await second;

      expect(calls, 1);
    });

    test(
      'a slot re-rolled while its check is in flight never receives the '
      'stale verdict (bytes identity guard)',
      () async {
        final slots = [doneSlot('happy', [1]), doneSlot('angry', [2])];
        var call = 0;
        Future<String?> fire({
          required String prompt,
          required List<String> imagesB64,
        }) async {
          // The prompt no longer names the target emotion (by design), so
          // key the simulated mid-flight re-roll on the first call instead.
          if (++call == 1) {
            slots[0].bytes = Uint8List.fromList([9, 9]);
            slots[0].qc = null;
          }
          return '{"same_person": false, "expression": "neutral", '
              '"flaw": "none"}';
        }

        final qc = ExpressionPackQc(
          slots: slots,
          baseImageB64: base,
          fire: fire,
        );
        await qc.run();

        expect(slots[0].qc, isNull, reason: 'stale verdict must not stamp');
        expect(slots[1].qc, isNotNull, reason: 'unaffected slot still checked');
        expect(qc.checkedCount, 2);
        expect(qc.unparsedCount, 0, reason: 'skipped ≠ unparsed');
      },
    );

    test(
      'named expressions match through the shared vocabulary (furious→anger, '
      'stems) and mismatches carry an honest "reads as" note',
      () async {
        final slots = [
          doneSlot('anger', [1]),
          doneSlot('amusement', [2]),
          doneSlot('joy', [3]),
        ];
        final fake = FakeEval([
          '{"same_person": true, "expression": "furious", "flaw": "none"}',
          '{"same_person": true, "expression": "amused grin", "flaw": "none"}',
          // The blind-model failure mode: a generic answer that fit every
          // slot under the old yes/no prompt now reads as a mismatch.
          '{"same_person": true, "expression": "neutral", "flaw": "none"}',
        ]);
        final qc = ExpressionPackQc(
          slots: slots,
          baseImageB64: base,
          fire: fake.call,
        );
        await qc.run();

        expect(slots[0].qc!.pass, isTrue, reason: 'furious → anger via map');
        expect(slots[1].qc!.pass, isTrue, reason: 'amused → amusement stem');
        expect(slots[2].qc!.pass, isFalse);
        expect(slots[2].qc!.note, contains('reads as "neutral"'));
        expect(qc.flaggedCount, 1);
      },
    );

    test('dispose mid-run bails out without stamping or notifying', () async {
      final slots = [doneSlot('happy', [1])];
      late ExpressionPackQc qc;
      Future<String?> fire({
        required String prompt,
        required List<String> imagesB64,
      }) async {
        qc.dispose(); // dialog closed while the eval was in flight
        return '{"same_person": true, "expression": "happy", "flaw": "none"}';
      }

      qc = ExpressionPackQc(slots: slots, baseImageB64: base, fire: fire);
      await qc.run(); // must not throw (notifyListeners after dispose)

      expect(slots[0].qc, isNull);
      expect(qc.checkedCount, 0);
    });
  });

  group('reroll resets stale verdicts (ExpressionPackSession)', () {
    test('a regenerated slot drops its qc', () async {
      final session = ExpressionPackSession(
        emotions: const ['happy'],
        basePrompt: 'portrait',
        negativePrompt: 'np',
        denoise: 0.7,
        generate: ({required String prompt, required String negativePrompt, required int seed, required double denoise}) async =>
            Uint8List.fromList([9]),
      );
      await session.run();
      expect(session.slots[0].state, ExpressionSlotState.done);

      session.slots[0].qc = const PackQcVerdict(
        samePerson: true,
        expressionMatches: true,
      );
      await session.reroll(0);

      expect(session.slots[0].state, ExpressionSlotState.done);
      expect(session.slots[0].qc, isNull);
    });
  });

}
