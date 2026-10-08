// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's ready check and the desk looking for ComfyUI at the same time
// run one look between them, not one each. A real loopback ComfyUI stands in.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/comfy_url_probe.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

import 'image_desk_harness.dart';

void main() {
  test('the phone and the desk asking at once share one look', () async {
    HttpOverrides.global = null;
    final live = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => live.close(force: true));
    live.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/system_stats') {
        request.response.write(
          jsonEncode({
            'system': {'comfyui_version': '0.3.60'},
          }),
        );
      } else if (request.uri.path == '/object_info') {
        request.response.write('{}');
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final dead = 'http://127.0.0.1:${socket.port}';
    await socket.close();

    final h = await DeskHarness.boot();
    await h.settings.setImageGenBackend('comfyui');
    await h.settings.adoptFoundComfyUiUrl(dead);
    var scans = 0;
    final finder = ComfyUrlFinder(
      processes: () async {
        scans++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return [
          ComfyProcessSnapshot(command: 'python main.py --port ${live.port}'),
        ];
      },
      desktopPort: () async => null,
      fallbackPorts: const [],
    );
    h.facade.comfyFinder = finder;

    final desk = redialComfy(h.settings, finder: finder);
    final (status, body) = await h.call('GET', '/api/image/studio/ready');
    await desk;

    expect(status, 200);
    expect(scans, 1);
    expect(body['savedUrl'], 'http://127.0.0.1:${live.port}');
  });
}
