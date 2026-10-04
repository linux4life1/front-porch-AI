// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Knowing when a model swap has really happened. The figures in the first
// test were measured on a real KoboldCpp 1.117.1: a reload answered at once,
// the old model kept answering, the server went away, and the new model
// answered about two seconds later.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

/// A clock the test moves, and an engine described as "what it reports at
/// each moment after the request".
class _Timeline {
  _Timeline(this.at);

  /// Seconds since the request -> (uptime, ready). Null uptime: no answer.
  final ({double? uptime, bool ready}) Function(double seconds) at;
  var _elapsed = Duration.zero;
  final DateTime _start = DateTime(2026);
  var readyAsked = 0;

  double get seconds => _elapsed.inMilliseconds / 1000;
  DateTime now() => _start.add(_elapsed);
  Future<void> pause(Duration d) async => _elapsed += d;
  Future<double?> uptime() async => at(seconds).uptime;
  Future<bool> ready() async {
    readyAsked++;
    return at(seconds).ready;
  }

  Future<void> wait({Duration timeout = const Duration(seconds: 30)}) =>
      waitForKoboldReload(
        uptime: uptime,
        ready: ready,
        timeout: timeout,
        now: now,
        pause: pause,
      );
}

void main() {
  test('the old model answering after the request is not the new one', () {
    // Measured: 5.09s before the request, 5.23s just after it.
    expect(koboldIsNewProcess(5.23, const Duration(milliseconds: 20)), isFalse);
    // Measured: the new process reported 1.58s at 2.24s after the request.
    expect(
      koboldIsNewProcess(1.58, const Duration(milliseconds: 2240)),
      isTrue,
    );
    // An engine that was itself only just started when asked.
    expect(koboldIsNewProcess(0.4, const Duration(milliseconds: 300)), isFalse);
  });

  test('the wait ends only once a new process is up AND ready', () async {
    final engine = _Timeline((s) {
      if (s < 0.6) return (uptime: 5.2 + s, ready: true); // old, still up
      if (s < 2.0) return (uptime: null, ready: false); // restarting
      if (s < 3.5) return (uptime: s - 0.7, ready: false); // new, loading
      return (uptime: s - 0.7, ready: true);
    });

    await engine.wait();

    expect(engine.seconds, greaterThanOrEqualTo(3.5));
    expect(engine.seconds, lessThan(4.0));
  });

  test('an old model that answers "ready" never ends the wait', () async {
    // The reload was dropped: the old process just keeps running.
    final engine = _Timeline((s) => (uptime: 40 + s, ready: true));

    await expectLater(
      engine.wait(timeout: const Duration(seconds: 5)),
      throwsA(
        isA<KoboldSwapTimeout>().having((e) => e.restarted, 'restarted', false),
      ),
    );
    expect(engine.readyAsked, 0, reason: 'readiness of the old model is moot');
  });

  test('a new process that never becomes ready times out, and says the '
      'engine did restart', () async {
    final engine = _Timeline(
      (s) => s < 1
          ? (uptime: null, ready: false)
          : (uptime: s - 0.7, ready: false),
    );

    await expectLater(
      engine.wait(timeout: const Duration(seconds: 8)),
      throwsA(
        isA<KoboldSwapTimeout>().having((e) => e.restarted, 'restarted', true),
      ),
    );
  });

  test('the load limit grows with the model: a minute plus eight seconds a '
      'gigabyte, up to fifteen minutes', () {
    const gb = 1024 * 1024 * 1024;
    expect(koboldLoadTimeout(0), const Duration(seconds: 60));
    expect(koboldLoadTimeout(4 * gb), const Duration(seconds: 92));
    expect(koboldLoadTimeout(16 * gb), const Duration(seconds: 188));
    expect(koboldLoadTimeout(40 * gb), const Duration(seconds: 380));
    expect(koboldLoadTimeout(500 * gb), const Duration(minutes: 15));
  });
}
