// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Draw Things port decides where a host is dialled, so writing it from
// the web needs the password like the host does, and it stays a real port.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/web/util/step_up.dart';

import 'image_desk_harness.dart';

void main() {
  group('the step-up decision', () {
    bool check(Map<String, dynamic> body, {int? port = 7859}) =>
        imageConfigWriteNeedsStepUp(
          body,
          currentRemoteApiUrl: 'https://openrouter.ai/api/v1',
          currentLocalUrl: 'http://127.0.0.1:7860',
          currentComfyUrl: 'http://127.0.0.1:8188',
          currentDrawThingsHost: '127.0.0.1',
          currentDrawThingsPort: port,
        );

    test('a new port needs it, the same port does not', () {
      expect(check({'drawThingsPort': 9999}), isTrue);
      expect(check({'drawThingsPort': 7859}), isFalse);
      expect(check({'steps': 20}), isFalse);
    });
  });

  group('POST /api/image/config', () {
    late DeskHarness h;

    setUp(() async => h = await DeskHarness.boot());

    test('a new port without the password is refused and not saved', () async {
      final (status, _) = await h.call('POST', '/api/image/config', {
        'drawThingsPort': 9999,
      });
      expect(status, isNot(200));
      expect(h.settings.drawThingsGrpcPort, isNot(9999));
    });

    test('with the password it is saved, kept to 1 through 65535', () async {
      Future<int> save(int port) async {
        final (status, body) = await h.call('POST', '/api/image/config', {
          'drawThingsPort': port,
          'currentPassword': kDeskPassword,
        });
        expect(status, 200, reason: '$body');
        return h.settings.drawThingsGrpcPort;
      }

      expect(await save(9999), 9999);
      expect(await save(99999), 65535);
      expect(await save(0), 1);
      expect(await save(-5), 1);
    });
  });
}
