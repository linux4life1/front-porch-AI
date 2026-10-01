// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's ready check finds ComfyUI too: an address nobody gave is
// switched to the ComfyUI that answers, and one the person gave is kept, with
// the other named as `neighborUrl`. A real loopback ComfyUI stands in.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/comfy_url_probe.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

import 'image_desk_harness.dart';

Future<HttpServer> _comfy() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    switch (request.uri.path) {
      case '/system_stats':
        request.response.write(
          jsonEncode({
            'system': {'comfyui_version': '0.3.60'},
          }),
        );
      case '/object_info':
        request.response.write('{}');
      default:
        request.response.statusCode = 404;
    }
    await request.response.close();
  });
  return server;
}

Future<int> _deadPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

void main() {
  late DeskHarness h;
  late HttpServer live;
  late String dead;

  setUp(() async {
    HttpOverrides.global = null;
    live = await _comfy();
    addTearDown(() => live.close(force: true));
    dead = 'http://127.0.0.1:${await _deadPort()}';
    h = await DeskHarness.boot();
    await h.settings.setImageGenBackend('comfyui');
    h.facade.comfyFinder = ComfyUrlFinder(
      processes: () async => [
        ComfyProcessSnapshot(command: 'python main.py --port ${live.port}'),
      ],
      desktopPort: () async => null,
      fallbackPorts: const [],
    );
  });

  test(
    'an address nobody gave is switched to the ComfyUI that answers',
    () async {
      await h.settings.adoptFoundComfyUiUrl(dead);

      final (status, body) = await h.call('GET', '/api/image/studio/ready');

      final url = 'http://127.0.0.1:${live.port}';
      expect(status, 200);
      expect(body['reachable'], isTrue);
      expect(body['savedUrl'], url);
      expect(body['neighborUrl'], '');
      expect(h.settings.comfyUiUrl, url);
    },
  );

  test('an address the person gave is kept, and the other is named', () async {
    await h.settings.setComfyUiUrl(dead);

    final (_, body) = await h.call('GET', '/api/image/studio/ready');

    expect(body['reachable'], isFalse);
    expect(body['savedUrl'], dead);
    expect(body['neighborUrl'], 'http://127.0.0.1:${live.port}');
    expect(h.settings.comfyUiUrl, dead);
  });
}
