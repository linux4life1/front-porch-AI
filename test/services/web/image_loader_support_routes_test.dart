// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';

import 'image_desk_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = 'http://127.0.0.1:8188';
  late DeskHarness h;
  late City96Gate previous;

  setUp(() async {
    previous = City96Gate.instance;
    City96Gate.instance = City96Gate();
    h = await DeskHarness.boot();
    await h.settings.setImageGenBackend('comfyui');
    await h.settings.setComfyUiUrl(url);
  });
  tearDown(() => City96Gate.instance = previous);

  test(
    'the web route confirms and revokes the shared submission gate',
    () async {
      for (final confirmed in [true, false]) {
        final (status, response) = await h.call(
          'POST',
          '/api/image/studio/loader-support',
          {'comfyUrl': url, 'confirmed': confirmed},
        );
        expect(status, 200);
        expect(response['confirmed'], confirmed);
        expect(City96Gate.instance.hasExistingSupport(url), confirmed);
      }
    },
  );

  test(
    'a stale server or a different backend cannot acquire confirmation',
    () async {
      final (stale, _) = await h.call(
        'POST',
        '/api/image/studio/loader-support',
        {'comfyUrl': '$url/other', 'confirmed': true},
      );
      expect(stale, 400);
      await h.settings.setImageGenBackend('remote');
      final (remote, _) = await h.call(
        'POST',
        '/api/image/studio/loader-support',
        {'comfyUrl': url, 'confirmed': true},
      );
      expect(remote, 400);
      expect(City96Gate.instance.hasExistingSupport(url), isFalse);
    },
  );

  test('malformed requests do not dismiss the warning', () async {
    for (final body in [
      {'comfyUrl': url, 'confirmed': 'true'},
      {'confirmed': true},
      {'comfyUrl': url},
    ]) {
      final (status, _) = await h.call(
        'POST',
        '/api/image/studio/loader-support',
        body,
      );
      expect(status, 400);
    }
    expect(City96Gate.instance.hasExistingSupport(url), isFalse);
  });
}
