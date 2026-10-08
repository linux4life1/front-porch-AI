// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A swap to the helper model and back, when the app reads KoboldCpp's
// answer late. The wait for a reload counted from when the answer was read;
// KoboldCpp restarts its model process about half a second after the
// request arrives, so an app busy for longer than that saw a process that
// looked no younger than its wait. The restart never counted, and the swap
// waited out its whole limit (a minute or more) before giving up. The wait
// now counts from when the request was sent, for the swaps' reloads and
// unloads as for the idle load back (kobold_idle_unload_test.dart).
//
// The real LLMProvider, KoboldCpp service and swap hosts on a loopback
// engine (loopback_kobold.dart) that answers late on purpose.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';

import 'loopback_kobold.dart';

void main() {
  late Directory root;
  late KoboldRig rig;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai swap late answer');
    rig = await KoboldRig.start(root);
    final chat = rig.gguf('chat-model.gguf');
    await rig.storage.backendSettings.setLastUsedModelPath(chat);
  });

  tearDown(() async {
    await rig.close();
    root.deleteSync(recursive: true);
  });

  test('a helper model swapped in and chat put back, each answer read after '
      'the engine restarted: both finish in seconds, with no restart of the '
      'engine', () async {
    final helper = rig.gguf('helper-model.gguf');
    final job = rig.provider.laneHost(
      type: 'kobold',
      url: '',
      model: helper,
      kcpps: '',
    )!;
    rig.engine.answerAdminAfter = const Duration(milliseconds: 1200);

    await job.hold(() async {}).timeout(const Duration(seconds: 10));
    expect(rig.engine.model, 'koboldcpp/helper-model');

    await job.restore().timeout(const Duration(seconds: 10));
    expect(rig.engine.model, 'koboldcpp/chat-model');
    expect(rig.kobold.launches, 0, reason: 'no last-resort restart');
    expect(rig.kobold.running, isTrue);
  });
}
