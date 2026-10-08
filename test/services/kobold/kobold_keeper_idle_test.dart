// The engine is busy until the save that follows a chat reply is done. The
// idle unload counts from the end of that save: a reply that is saved is
// still the engine's work, and the request that waits behind the save must
// not find the model unloaded under it.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/kobold_engine_harness.dart';

/// Stands for the KoboldCpp process the app launched. The service keeps it
/// as the sign that the engine is the app's own; nothing is run or killed.
class _Launched implements Process {
  @override
  int get pid => -1;

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  IOSink get stdin => throw UnsupportedError('not a real process');

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => false;
}

void main() {
  test('a slow save keeps the engine busy: the idle time counts from the end '
      'of the save', () async {
    final h = await KoboldEngineHarness.start();
    addTearDown(h.dispose);
    h.kobold.debugKeeperPlan = () async => const KoboldKeeperPlan.keep(3);
    await h.storage.backendSettings.setIdleUnloadMinutes(10);
    h.kobold
      ..debugIdleUnloadAfter = const Duration(milliseconds: 400)
      ..debugStartIdleClock(startedByApp: _Launched());
    // The save of a big cache takes longer than the idle time.
    h.engine.beforeAdmin = (r) => r.kind == 'save'
        ? Future<void>.delayed(const Duration(milliseconds: 900))
        : Future<void>.value();
    h.engine.forgetLog();

    await h.kobold
        .generateStream(
          const GenerationParams(
            prompt: 'a chat reply',
            maxLength: 8,
            kvChat: 'A',
          ),
        )
        .toList();
    await h.kobold.waitForIdle();
    final saved = h.engine.of('save').single.endedAt!;

    // Let the idle time run out after the save, and see when the engine is
    // asked whether it is idle: that is the idle unload at work.
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (h.engine.perfAsks.every((t) => t.isBefore(saved))) {
      if (DateTime.now().isAfter(end)) fail('the idle clock never ran out');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final asked = h.engine.perfAsks.firstWhere((t) => !t.isBefore(saved));
    expect(
      asked.difference(saved),
      greaterThanOrEqualTo(const Duration(milliseconds: 300)),
      reason:
          'the engine was counted as idle while it was still saving, so '
          'the unload came straight after the save',
    );
  });
}
