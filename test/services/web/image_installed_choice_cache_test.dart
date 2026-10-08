// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/image_facade.dart';

/// Loopback ComfyUI. The node list grows after the first read, the way a
/// model appears once a download has landed.
Future<HttpServer> _comfy({
  required bool Function() includeNew,
  required void Function() onObjectInfo,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.method == 'GET' && request.uri.path == '/object_info') {
      onObjectInfo();
      final names = [
        'old.safetensors',
        if (includeNew()) 'just-downloaded.safetensors',
      ];
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'UNETLoader': {
            'input': {
              'required': {
                'unet_name': [names],
              },
            },
          },
        }),
      );
    } else {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  return server;
}

void main() {
  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'a file downloaded after a generate is selectable on the phone',
    () async {
      var includeNew = false;
      var hits = 0;
      final server = await _comfy(
        includeNew: () => includeNew,
        onObjectInfo: () => hits++,
      );
      addTearDown(server.close);
      final dir = Directory.systemTemp.createTempSync('installed-cache');
      addTearDown(() => dir.deleteSync(recursive: true));
      final storage = StorageService.sandbox(dir.path);
      await storage.imageGenSettings.setImageGenBackend('comfyui');
      await storage.imageGenSettings.setComfyUiUrl(
        'http://127.0.0.1:${server.port}',
      );
      final image = ImageGenService(storage);
      final facade = ImageFacade(image, storage);

      await image.fetchComfySamplers('');
      expect(hits, 1);
      includeNew = true;

      final choice = await facade.installedChoice(
        workflowId: 'z_image_turbo',
        file: 'just-downloaded.safetensors',
        lora: false,
      );

      expect(hits, 2);
      expect(choice['accept'], isTrue);
    },
  );
}
