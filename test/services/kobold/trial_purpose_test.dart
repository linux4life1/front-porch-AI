// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The preset editor's "Time both on this card" loads each way of the preset
// as a trial. The status line says what a model is being loaded for; for a
// trial it said "for the story", which is not what the person who pressed
// the button is doing.
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
    root = Directory.systemTemp.createTempSync('fpai trial purpose');
    rig = await KoboldRig.start(root);
  });

  tearDown(() async {
    await rig.close();
    root.deleteSync(recursive: true);
  });

  test('a trial is loaded "for the speed test", not "for the story"', () async {
    final statuses = <String>[];
    rig.kobold.addListener(() => statuses.add(rig.kobold.modelLoadingStatus));
    final trialModel = rig.gguf('trial-model.gguf');

    final ran = await rig.provider.loadKoboldTrial('fpai-trial.kcpps', {
      'model_param': trialModel,
      'contextsize': 8192,
    });

    expect(ran, isTrue);
    expect(
      statuses,
      contains('Loading trial-model.gguf for the speed test...'),
    );
    expect(statuses.where((s) => s.contains('for the story')), isEmpty);
  });
}
