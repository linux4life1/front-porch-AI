// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Two roles on ONE engine (the app's KoboldCpp). Loading one replaces the
// other, so nothing is unloaded first, and each role is asked every time
// whether its config is the one loaded, instead of the swap trusting its
// own memory of what it did last.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/worker_gpu_swap.dart';

class _Role implements GpuSwapHost {
  _Role(this.label, this.log);

  @override
  final String label;
  final List<String> log;
  Object? failNextRestore;

  @override
  Future<void> unload() async => log.add('unload $label');

  @override
  Future<void> restore() async {
    log.add('load $label');
    final fail = failNextRestore;
    failNextRestore = null;
    if (fail != null) throw fail;
  }
}

void main() {
  late List<String> log;
  late _Role chat;
  late _Role job;

  GpuSwapOccupancy shared({bool sameResident = false}) => GpuSwapOccupancy(
    mouth: chat,
    worker: job,
    sharedEngine: true,
    sameResident: sameResident,
  );

  setUp(() {
    log = [];
    chat = _Role('chat', log);
    job = _Role('job', log);
  });

  test('the job is loaded straight over chat, and chat straight over the '
      'job: nothing is unloaded in between', () async {
    final swap = shared();
    await swap.hold(() async => log.add('work'));
    await swap.ensureMouth();
    expect(log, ['load job', 'work', 'load chat']);
  });

  test('each role is asked every time, so a model replaced from outside is '
      'put back', () async {
    final swap = shared();
    await swap.hold(() async {});
    await swap.hold(() async {});
    await swap.ensureMouth();
    await swap.ensureMouth();
    // The roles themselves skip the reload when their config is loaded;
    // the swap never decides that for them.
    expect(log, ['load job', 'load job', 'load chat', 'load chat']);
  });

  test('"same model as chat", worked out when the swap was built, does not '
      'switch the asking off', () async {
    final swap = shared(sameResident: true);
    await swap.hold(() async {});
    expect(log, ['load job']);
  });

  test('a job that fails to load hands the engine back to chat and leaves '
      'the swap free', () async {
    final swap = shared();
    job.failNextRestore = StateError('too big');
    await expectLater(swap.hold(() async {}), throwsStateError);
    expect(log, ['load job', 'load chat']);
    expect(swap.mouthDown, isFalse);
    expect(swap.isHeld, isFalse);
  });

  test('separate engines still unload before loading', () async {
    final swap = GpuSwapOccupancy(mouth: chat, worker: job);
    await swap.hold(() async {});
    await swap.ensureMouth();
    expect(log, ['unload chat', 'load job', 'unload job', 'load chat']);
  });
}
