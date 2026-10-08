// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A swap must not trust its own "my model is loaded" note. One KoboldCpp
// process is shared: the engine can restart, Settings can load a model, and
// another swap can put the chat model back. After any of those, a story job
// that still believed its model was resident sent the rest of its run to
// the chat model. The engine now counts every load change, and the swap
// reloads its model when that count has moved since it loaded it.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/worker_gpu_swap.dart';

/// The one process: what is in memory, and the count of load changes.
class _Engine {
  String resident = 'chat';
  int generation = 0;

  void load(String model) {
    resident = model;
    generation++;
  }
}

class _Host implements GpuSwapHost {
  _Host(this.engine, this.model);
  final _Engine engine;
  final String model;

  @override
  String get label => model;

  @override
  Future<void> unload() async => engine.load('none');

  @override
  Future<void> restore() async => engine.load(model);
}

void main() {
  late _Engine engine;
  late GpuSwapOccupancy lane;

  setUp(() {
    engine = _Engine();
    lane = GpuSwapOccupancy(
      mouth: _Host(engine, 'chat'),
      worker: _Host(engine, 'lane'),
      residentGeneration: () => engine.generation,
    );
  });

  Future<String> call() => lane.hold(() async => engine.resident);

  test('three calls in a row load the lane model once', () async {
    expect(
      [await call(), await call(), await call()],
      ['lane', 'lane', 'lane'],
    );
    expect(lane.steps, ['unload-mouth:chat', 'prepare-worker:lane']);
  });

  test('after something else reloads the engine, the next call puts the '
      'lane model back instead of running on the chat model', () async {
    final served = <String>[await call()];

    // Outside this swap: Settings loads a model, the engine restarts, or
    // the chat pair is restored for a reply.
    engine.load('chat');

    served.add(await call());
    served.add(await call());

    expect(served, ['lane', 'lane', 'lane']);
    expect(lane.steps, [
      'unload-mouth:chat',
      'prepare-worker:lane',
      'stale-worker:lane',
      'unload-mouth:chat',
      'prepare-worker:lane',
    ]);
  });

  test('with no counter the old behaviour is unchanged', () async {
    final blind = GpuSwapOccupancy(
      mouth: _Host(engine, 'chat'),
      worker: _Host(engine, 'lane'),
    );
    await blind.hold(() async {});
    engine.load('chat');
    await blind.hold(() async {});
    expect(blind.steps, ['unload-mouth:chat', 'prepare-worker:lane']);
  });
}
