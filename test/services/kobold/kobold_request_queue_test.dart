// The line to KoboldCpp: one request at a time, first come first served,
// and a place in it is always given back.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';

Future<void> _turns() => Future<void>.delayed(Duration.zero);

void main() {
  test('requests run one at a time, in the order they came', () async {
    final queue = KoboldRequestQueue();
    final log = <String>[];
    final gate = Completer<void>();

    final a = queue.run(() async {
      log.add('a in');
      await gate.future;
      log.add('a out');
    });
    final b = queue.run(() async {
      log.add('b in');
      log.add('b out');
    });
    final c = queue.run(() async {
      log.add('c in');
      log.add('c out');
    });

    await _turns();
    expect(log, ['a in'], reason: 'b and c wait for a');
    gate.complete();
    await Future.wait([a, b, c]);
    expect(log, ['a in', 'a out', 'b in', 'b out', 'c in', 'c out']);
  });

  test('a request that throws hands the line on, and says why', () async {
    final queue = KoboldRequestQueue();
    final failing = queue.run<void>(() async => throw StateError('boom'));
    final next = queue.run(() async => 'ran');

    await expectLater(failing, throwsStateError);
    expect(await next, 'ran');
  });

  test(
    'a ticket let go before its turn does not let the others pass',
    () async {
      final queue = KoboldRequestQueue();
      final gate = Completer<void>();
      final order = <String>[];

      final first = queue.run(() async {
        await gate.future;
        order.add('first');
      });
      final walkedAway = queue.enter()..release();
      final last = queue.run(() async => order.add('last'));

      await _turns();
      expect(order, isEmpty, reason: 'first still has the line');
      gate.complete();
      await Future.wait([first, walkedAway.turn, last]);
      expect(order, ['first', 'last']);
    },
  );

  test('letting go twice is harmless', () async {
    final queue = KoboldRequestQueue();
    final ticket = queue.enter();
    await ticket.turn;
    ticket
      ..release()
      ..release();
    expect(await queue.run(() async => 1), 1);
  });

  test(
    'waitForIdle waits for what is in line now, not for later arrivals',
    () async {
      final queue = KoboldRequestQueue();
      final gateA = Completer<void>();
      final gateB = Completer<void>();
      unawaited(queue.run(() => gateA.future));

      var idle = false;
      unawaited(queue.waitForIdle().then((_) => idle = true));
      unawaited(queue.run(() => gateB.future));

      await _turns();
      expect(idle, isFalse);
      gateA.complete();
      await _turns();
      await _turns();
      expect(idle, isTrue, reason: 'only a was in line when it was asked');

      var allDone = false;
      unawaited(queue.waitForIdle().then((_) => allDone = true));
      await _turns();
      expect(allDone, isFalse, reason: 'b still has the line');
      gateB.complete();
      await queue.waitForIdle();
    },
  );

  test('waitForIdle returns at once when nothing is in line', () async {
    await KoboldRequestQueue().waitForIdle().timeout(
      const Duration(seconds: 1),
      onTimeout: () => fail('waitForIdle waited with nothing in line'),
    );
  });
}
