// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A story job on its own local model swaps it in for the job and puts the
// chat model back afterwards. The swap is kept per job, and it used to be
// built once and never again: the chat host it was built for (a remote API
// that has nothing to put back, a model picked since) was frozen into it.
// After the chat model changed, the next job put back the one that was
// picked before, or, from a remote chat, none at all, and chat then spoke
// with the job's model.
//
// The engine is a real HTTP server on loopback (see loopback_kobold.dart).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import 'loopback_kobold.dart';

void main() {
  late Directory root;
  late KoboldRig rig;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai lane chat');
    rig = await KoboldRig.start(root);
  });

  tearDown(() async {
    await rig.close();
    root.deleteSync(recursive: true);
  });

  /// One call of a job on [laneModel]: the model swapped in for it, then
  /// the chat model put back.
  Future<void> runJob(String laneModel) async {
    final job = rig.provider.laneHost(
      type: 'kobold',
      url: '',
      model: laneModel,
    )!;
    await job.hold(() async {});
    expect(rig.engine.model, 'koboldcpp/lane-model', reason: 'the job runs');
    await job.restore();
  }

  test('a chat that moved onto KoboldCpp since the job was first asked for '
      'is the model put back', () async {
    final laneModel = rig.gguf('lane-model.gguf');
    final chatModel = rig.gguf('chat-model.gguf');

    // Chat is on a remote API: nothing to put back after the job.
    await rig.storage.backendSettings.setBackendType('openRouter');
    await runJob(laneModel);

    // Chat moves onto the local engine.
    await rig.storage.backendSettings.setBackendType('kobold');
    await rig.storage.backendSettings.setLastUsedModelPath(chatModel);
    await runJob(laneModel);

    expect(
      rig.engine.model,
      'koboldcpp/chat-model',
      reason: 'the job is over: the engine is chat\'s again',
    );
  });

  test('the swap is kept while chat stays as it is, and built again when '
      'chat\'s model changes', () async {
    final laneModel = rig.gguf('lane-model.gguf');
    await rig.storage.backendSettings.setBackendType('openRouter');
    await rig.storage.backendSettings.setRemoteModelName('chat-a');

    LaneHost job() =>
        rig.provider.laneHost(type: 'kobold', url: '', model: laneModel)!;
    final first = job();

    // Two calls of one job share one swap (a method of the same object).
    expect(job().hold, first.hold);

    await rig.storage.backendSettings.setRemoteModelName('chat-b');

    expect(job().hold, isNot(first.hold));
  });

  test('a lane\'s label is what its host carries, and a lane with no model '
      'has none', () {
    final laneModel = rig.gguf('lane-model.gguf');

    expect(
      rig.provider.laneLabel(type: 'kobold', url: '', model: laneModel),
      'KoboldCpp · lane-model',
    );
    expect(
      rig.provider.laneHost(type: 'kobold', url: '', model: laneModel)!.label,
      'KoboldCpp · lane-model',
    );
    expect(
      rig.provider.laneLabel(type: 'omlx', url: '', model: 'org/mlx-qwen'),
      'oMLX · mlx-qwen',
    );
    expect(rig.provider.laneLabel(type: 'omlx', url: '', model: ''), isNull);
    expect(rig.provider.laneLabel(type: 'kobold', url: '', model: ''), isNull);
  });
}
