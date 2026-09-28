// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// A real loopback ComfyUI. Records the graph posted to `/prompt`.
Future<HttpServer> _comfy(void Function(Map<String, dynamic>) onPrompt) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/object_info') {
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
    } else if (request.method == 'POST' && path == '/upload/image') {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'name': 'ref.png'}));
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

void main() {
  setUp(() => HttpOverrides.global = null);

  test('a create post does not send a gguf file as UNETLoader', () async {
    Map<String, dynamic>? posted;
    final server = await _comfy((graph) => posted = graph);
    addTearDown(server.close);
    final dir = Directory.systemTemp.createTempSync('comfy-post-create');
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
    final image = ImageGenService(storage);
    await image.generateImage(prompt: 'a porch at dusk');

    expect(posted, isNotNull, reason: image.statusMessage);
    final classes = _classes(posted!);
    expect(classes, contains('UnetLoaderGGUF'));
    expect(classes, isNot(contains('UNETLoader')));
  });

  test('an edit post does not send a gguf file as UNETLoader', () async {
    Map<String, dynamic>? posted;
    final server = await _comfy((graph) => posted = graph);
    addTearDown(server.close);
    final comfy = ComfyUiService(baseUrl: 'http://127.0.0.1:${server.port}');
    try {
      await comfy.generateImageEdit(
        referenceImageBytes: Uint8List.fromList(const [1, 2, 3, 4]),
        workflowTemplate: {
          'unet': {
            'class_type': 'UNETLoader',
            'inputs': {
              'unet_name': '%MODEL_DIFFUSION%',
              'weight_dtype': 'default',
            },
          },
        },
        tokenValues: const {'%MODEL_DIFFUSION%': 'edit-model.gguf'},
      );
    } catch (_) {}

    expect(posted, isNotNull);
    final classes = _classes(posted!);
    expect(classes, contains('UnetLoaderGGUF'));
    expect(classes, isNot(contains('UNETLoader')));
  });
}
