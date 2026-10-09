// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// "Check vision support" against a REAL KoboldCpp reached as a Custom
// (OpenAI-compatible) URL. With no mmproj, KoboldCpp answers an image
// request 200 and drops the image, so only its own version reply can say
// "no vision". Skipped unless KOBOLD_LIVE_BIN and KOBOLD_LIVE_MODEL (a
// text-only model) are set; see kobold_engine_live_test.dart. Run:
//   KOBOLD_LIVE_BIN=… KOBOLD_LIVE_MODEL=… flutter test --tags kobold_live \
//     test/live/kobold_vision_check_live_test.dart

@Tags(['kobold_live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/capability/model_capabilities.dart';
import 'package:front_porch_ai/services/capability/vision_support_resolver.dart';

import 'live_engine.dart';

void main() {
  late Directory root;

  // `flutter test` answers every HTTP call itself unless this is cleared.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai vision live');
    root = Directory(temp.resolveSymbolicLinksSync());
  });

  tearDown(() async {
    VisionSupportResolver.instance.clear();
    await stopLiveEnginesUnder(root);
    await root.delete(recursive: true);
  });

  test(
    'a KoboldCpp running a text-only model, reached at its /v1 URL, is '
    'checked as no vision',
    () async {
      final exe = await copyEngineInto(root);
      final port = await freePort();
      await LiveEngine.start(exe, [
        '--model',
        liveEngineModel,
        '--port',
        '$port',
        '--contextsize',
        '2048',
        '--skiplauncher',
      ]);
      await waitForLiveModel(port);
      final version = await liveGet(port, '/api/extra/version');
      expect(
        (version as Map?)?['vision'],
        isFalse,
        reason: 'KOBOLD_LIVE_MODEL must be a text-only model with no mmproj',
      );

      final support = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: 'http://127.0.0.1:$port/v1',
        apiKey: '',
        modelName: (await liveLoadedModel(port))!,
      );
      expect(support.supported, isFalse);
      expect(support.source, VisionSource.none);
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: liveEngineSkip,
  );
}
