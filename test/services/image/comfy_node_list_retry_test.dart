// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Loopback ComfyUI. [serveGgufLoader] can flip on after the first read,
/// the way the loader exists only after ComfyUI is restarted.
Future<HttpServer> _comfy({
  required bool Function() serveGgufLoader,
  required void Function() onObjectInfo,
  required void Function(Map<String, dynamic>) onPrompt,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/object_info') {
      onObjectInfo();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'UNETLoader': {
            'input': {
              'required': {
                'unet_name': <Object>[],
                'weight_dtype': ['default'],
              },
            },
          },
          if (serveGgufLoader())
            'UnetLoaderGGUF': {
              'input': {
                'required': {'unet_name': <Object>[]},
              },
            },
          'KSampler': {
            'input': {
              'required': {
                'sampler_name': [
                  ['euler'],
                ],
              },
            },
          },
        }),
      );
    } else if (request.method == 'POST' && path == '/prompt') {
      final raw = await utf8.decodeStream(request);
      final body = jsonDecode(raw);
      if (body is Map && body['prompt'] is Map) {
        onPrompt((body['prompt'] as Map).cast<String, dynamic>());
      }
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('stop');
    } else {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  return server;
}

Set<String> _classes(Map<String, dynamic> graph) {
  return {
    for (final node in graph.values)
      if (node is Map && node['class_type'] is String)
        node['class_type'] as String,
  };
}

Future<ImageGenService> _studio(HttpServer server) async {
  final dir = Directory.systemTemp.createTempSync('comfy-node-retry');
  addTearDown(() => dir.deleteSync(recursive: true));
  final storage = StorageService.sandbox(dir.path);
  final settings = storage.imageGenSettings;
  await settings.setImageGenBackend('comfyui');
  await settings.setComfyUiUrl('http://127.0.0.1:${server.port}');
  await settings.setComfyCreateWorkflowId('z_image_turbo');
  await settings.setComfyCreateModelChoice(
    'z_image_turbo',
    '%MODEL_DIFFUSION%',
    'z-image-turbo-Q5_K_M.gguf',
  );
  await settings.setComfyCreateModelChoice(
    'z_image_turbo',
    '%MODEL_CLIP%',
    'qwen_3_4b.safetensors',
  );
  await settings.setComfyCreateModelChoice(
    'z_image_turbo',
    '%MODEL_VAE%',
    'ae.safetensors',
  );
  return ImageGenService(storage);
}

void main() {
  setUp(() => HttpOverrides.global = null);

  test(
    'a gguf create uses a loader that appeared after the list was cached',
    () async {
      var serveGguf = false;
      var hits = 0;
      Map<String, dynamic>? posted;
      final server = await _comfy(
        serveGgufLoader: () => serveGguf,
        onObjectInfo: () => hits++,
        onPrompt: (graph) => posted = graph,
      );
      addTearDown(server.close);
      final image = await _studio(server);

      await image.fetchComfySamplers('');
      expect(hits, 1);
      serveGguf = true;
      await image.generateImage(prompt: 'a porch at dusk');

      expect(hits, 2, reason: image.statusMessage);
      expect(posted, isNotNull, reason: image.statusMessage);
      expect(_classes(posted!), contains('UnetLoaderGGUF'));
      expect(_classes(posted!), isNot(contains('UNETLoader')));
    },
  );

  test(
    'a gguf create still refuses when the fresh list has no loader',
    () async {
      var hits = 0;
      Map<String, dynamic>? posted;
      final server = await _comfy(
        serveGgufLoader: () => false,
        onObjectInfo: () => hits++,
        onPrompt: (graph) => posted = graph,
      );
      addTearDown(server.close);
      final image = await _studio(server);

      await image.fetchComfySamplers('');
      await image.generateImage(prompt: 'a porch at dusk');

      expect(hits, 2);
      expect(posted, isNull);
      expect(image.statusMessage, contains('missing the UnetLoaderGGUF'));
    },
  );
}
