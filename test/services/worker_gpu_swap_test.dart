// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';

void main() {
  test('known local pairs can swap; generic local OpenAI cannot', () {
    expect(
      workerGpuSwapSupported(
        mouthType: 'kobold',
        mouthUrl: '',
        mouthModel: '/tmp/a.gguf',
        workerType: 'omlx',
        workerUrl: kOmlxApiV1,
        workerModel: 'mlx-qwen',
      ),
      isTrue,
    );
    expect(
      workerGpuSwapSupported(
        mouthType: 'omlx',
        mouthUrl: kOmlxApiV1,
        mouthModel: 'mlx-chat',
        workerType: 'openRouter',
        workerUrl: kLmStudioApiV1,
        workerModel: 'qwen/qwen3',
      ),
      isTrue,
    );
    expect(
      workerGpuSwapSupported(
        mouthType: 'openRouter',
        mouthUrl: 'http://127.0.0.1:8080/v1',
        mouthModel: 'llama',
        workerType: 'omlx',
        workerUrl: kOmlxApiV1,
        workerModel: 'mlx-qwen',
      ),
      isFalse,
      reason: 'llama.cpp has no documented unload we may call',
    );
  });

  test('same resident engine is supported without a second process', () {
    expect(
      workerLanesShareResident(
        mouthType: 'kobold',
        mouthUrl: '',
        mouthModel: '/tmp/a.gguf',
        workerType: 'kobold',
        workerUrl: '',
        workerModel: '/tmp/a.gguf',
      ),
      isTrue,
    );
    expect(
      workerLanesShareResident(
        mouthType: 'kobold',
        mouthUrl: '',
        mouthModel: '/tmp/a.gguf',
        workerType: 'kobold',
        workerUrl: '',
        workerModel: r'\tmp\a.gguf',
      ),
      isTrue,
      reason: 'slash direction must not force a useless unload',
    );
    expect(
      workerGpuSwapSupported(
        mouthType: 'omlx',
        mouthUrl: kOmlxApiV1,
        mouthModel: 'same-mlx',
        workerType: 'omlx',
        workerUrl: kOmlxApiV1,
        workerModel: 'same-mlx',
      ),
      isTrue,
    );
  });

  test('same GGUF different .kcpps is not same-resident', () {
    expect(
      workerLanesShareResident(
        mouthType: 'kobold',
        mouthUrl: '',
        mouthModel: '/tmp/a.gguf',
        workerType: 'kobold',
        workerUrl: '',
        workerModel: '/tmp/a.gguf',
        mouthKcpps: '/tmp/mouth.kcpps',
        workerKcpps: '/tmp/worker.kcpps',
      ),
      isFalse,
    );
    expect(
      workerLanesShareResident(
        mouthType: 'kobold',
        mouthUrl: '',
        mouthModel: '/tmp/a.gguf',
        workerType: 'kobold',
        workerUrl: '',
        workerModel: '/tmp/a.gguf',
        mouthKcpps: '/tmp/same.kcpps',
        workerKcpps: '/tmp/same.kcpps',
      ),
      isTrue,
    );
  });

  test('kobold+kobold different GGUFs are not same-resident', () {
    expect(
      workerLanesShareResident(
        mouthType: 'kobold',
        mouthUrl: '',
        mouthModel: '/tmp/mouth.gguf',
        workerType: 'kobold',
        workerUrl: '',
        workerModel: '/tmp/worker.gguf',
      ),
      isFalse,
    );
    expect(
      workerGpuSwapSupported(
        mouthType: 'kobold',
        mouthUrl: '',
        mouthModel: '/tmp/mouth.gguf',
        workerType: 'kobold',
        workerUrl: '',
        workerModel: '/tmp/worker.gguf',
      ),
      isTrue,
    );
  });

  test('workerPairAllowed stays refused until swap is available', () {
    expect(
      workerPairAllowed(
        mouthType: 'kobold',
        mouthUrl: '',
        workerType: 'omlx',
        workerUrl: kOmlxApiV1,
      ),
      isFalse,
    );
    expect(
      workerPairAllowed(
        mouthType: 'kobold',
        mouthUrl: '',
        workerType: 'omlx',
        workerUrl: kOmlxApiV1,
        gpuSwapAvailable: true,
      ),
      isTrue,
    );
  });

  test('API+API and local+API stay allowed without a swap flag', () {
    expect(
      workerPairAllowed(
        mouthType: 'openRouter',
        mouthUrl: kNanoGptApiV1,
        workerType: 'openRouter',
        workerUrl: kNanoGptApiV1,
      ),
      isTrue,
    );
    expect(
      workerPairAllowed(
        mouthType: 'kobold',
        mouthUrl: '',
        workerType: 'openRouter',
        workerUrl: kOpenRouterApiV1,
      ),
      isTrue,
    );
  });

  test('Kobold worker does not autostart beside a local mouth', () {
    expect(
      shouldEnsureKoboldProcess(
        mouthType: 'omlx',
        workerType: 'kobold',
        pairAllowed: true,
        mouthIsLocal: true,
      ),
      isFalse,
    );
    expect(
      shouldEnsureKoboldProcess(
        mouthType: 'openRouter',
        workerType: 'kobold',
        pairAllowed: true,
        mouthIsLocal: false,
      ),
      isTrue,
    );
  });

  test('occupancy unloads mouth, prepares worker, leaves worker hot', () async {
    final occ = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _RecHost('worker'),
    );
    var workRan = false;
    await occ.hold(() async {
      expect(occ.steps, ['unload-mouth:mouth', 'prepare-worker:worker']);
      workRan = true;
    });
    expect(workRan, isTrue);
    expect(occ.steps, ['unload-mouth:mouth', 'prepare-worker:worker']);
    expect(occ.mouthDown, isTrue);
    expect(occ.isHeld, isFalse);
  });

  test('next worker hold stays hot; speech ensureMouth restores', () async {
    final occ = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _RecHost('worker'),
    );
    await occ.hold(() async {});
    await occ.hold(() async {});
    expect(occ.steps.where((s) => s.startsWith('unload-mouth')).length, 1);
    expect(occ.steps.where((s) => s.startsWith('prepare-worker')).length, 1);
    await occ.ensureMouth();
    expect(occ.steps, [
      'unload-mouth:mouth',
      'prepare-worker:worker',
      'unload-worker:worker',
      'restore-mouth:mouth',
    ]);
    expect(occ.mouthDown, isFalse);
  });

  test('nested holds swap once; failed acquire still restores mouth', () async {
    final occ = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _RecHost('worker'),
    );
    await occ.hold(() async {
      await occ.hold(() async {});
    });
    expect(occ.steps.where((s) => s.startsWith('unload-mouth')).length, 1);
    expect(occ.mouthDown, isTrue);

    final failing = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _FailRestoreHost('worker'),
    );
    await expectLater(failing.hold(() async {}), throwsStateError);
    expect(failing.steps.last, 'restore-mouth:mouth');
    expect(failing.mouthDown, isFalse);
  });

  test('same-resident occupancy is a no-op', () async {
    final occ = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _RecHost('worker'),
      sameResident: true,
    );
    await occ.hold(() async {});
    expect(occ.steps, isEmpty);
  });

  test('kobold path pair drives acquire vs sameResident', () async {
    final different = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _RecHost('worker'),
      sameResident: workerLanesShareResident(
        mouthType: 'kobold',
        mouthUrl: '',
        mouthModel: '/tmp/mouth.gguf',
        workerType: 'kobold',
        workerUrl: '',
        workerModel: '/tmp/worker.gguf',
      ),
    );
    await different.hold(() async {});
    expect(different.steps, ['unload-mouth:mouth', 'prepare-worker:worker']);
    expect(different.mouthDown, isTrue);

    final same = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _RecHost('worker'),
      sameResident: workerLanesShareResident(
        mouthType: 'kobold',
        mouthUrl: '',
        mouthModel: '/tmp/a.gguf',
        workerType: 'kobold',
        workerUrl: '',
        workerModel: '/tmp/a.gguf',
      ),
    );
    await same.hold(() async {});
    expect(same.steps, isEmpty);
    expect(same.mouthDown, isFalse);
  });

  test('speech pin blocks unload until generate finishes', () async {
    final occ = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _RecHost('worker'),
    );
    await occ.hold(() async {});
    await occ.ensureMouth();
    expect(occ.steps.last, 'restore-mouth:mouth');
    occ.beginSpeech();
    var generated = false;
    final post = occ.hold(() async {
      expect(
        generated,
        isTrue,
        reason: 'post-eval unload must follow generate',
      );
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      occ.steps.where((s) => s.startsWith('unload-mouth')).length,
      1,
      reason: 'regression: post-eval unload ran before generate',
    );
    generated = true;
    occ.endSpeech();
    await post;
    expect(occ.steps.where((s) => s.startsWith('unload-mouth')).length, 2);
  });

  test('same GGUF different .kcpps drives acquire', () async {
    final occ = GpuSwapOccupancy(
      mouth: _RecHost('mouth'),
      worker: _RecHost('worker'),
      sameResident: workerLanesShareResident(
        mouthType: 'kobold',
        mouthUrl: '',
        mouthModel: '/tmp/a.gguf',
        workerType: 'kobold',
        workerUrl: '',
        workerModel: '/tmp/a.gguf',
        mouthKcpps: '/tmp/mouth.kcpps',
        workerKcpps: '/tmp/worker.kcpps',
      ),
    );
    await occ.hold(() async {});
    expect(occ.steps, ['unload-mouth:mouth', 'prepare-worker:worker']);
  });
}

class _RecHost implements GpuSwapHost {
  _RecHost(this.label);

  @override
  final String label;

  @override
  Future<void> unload() async {}

  @override
  Future<void> restore() async {}
}

class _FailRestoreHost implements GpuSwapHost {
  _FailRestoreHost(this.label);

  @override
  final String label;

  @override
  Future<void> unload() async {}

  @override
  Future<void> restore() async {
    throw StateError('worker prepare missed');
  }
}
