// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A refused or failed Comfy run names the node and the reason Comfy gave, not
// "Prompt outputs failed validation". Talks to a real loopback ComfyUI.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

const _refusal = '''
{"error":{"type":"prompt_outputs_failed_validation","message":"Prompt outputs failed validation","details":""},
"node_errors":{"28":{"class_type":"UNETLoader","dependent_outputs":[],"errors":[{"type":"value_not_in_list","message":"Value not in list","details":"unet_name: 'z_image_turbo_bf16.safetensors' not in []"}]}}}
''';

/// Loopback ComfyUI that refuses `/prompt`, or accepts it and then reports an
/// execution error in `/history`.
Future<HttpServer> _comfy({required bool refuse}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/object_info') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'CheckpointLoaderSimple': <String, dynamic>{},
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
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      if (refuse) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(_refusal);
      } else {
        request.response.write(jsonEncode({'prompt_id': 'p1'}));
      }
    } else if (request.method == 'GET' && path == '/history/p1') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'p1': {
            'status': {
              'status_str': 'error',
              'messages': [
                [
                  'execution_error',
                  {
                    'node_id': '7',
                    'node_type': 'KSampler',
                    'exception_message': 'CUDA out of memory',
                  },
                ],
              ],
            },
            'outputs': <String, dynamic>{},
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

Future<ImageGenService> _studio(HttpServer server, Directory dir) async {
  final storage = StorageService.sandbox(dir.path);
  final settings = storage.imageGenSettings;
  await settings.setImageGenBackend('comfyui');
  await settings.setComfyUiUrl('http://127.0.0.1:${server.port}');
  await settings.setComfyCreateWorkflowId('sd');
  await settings.setComfyCreateModelChoice(
    'sd',
    '%MODEL_CHECKPOINT%',
    'v1-5-pruned.safetensors',
  );
  return ImageGenService(storage);
}

void main() {
  late Directory dir;

  setUp(() {
    HttpOverrides.global = null;
    dir = Directory.systemTemp.createTempSync('comfy-wording');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  test('a refused graph names the node and the reason Comfy gave', () async {
    final server = await _comfy(refuse: true);
    addTearDown(server.close);
    final image = await _studio(server, dir);
    final bytes = await image.generateImage(prompt: 'a porch at dusk');
    expect(bytes, isNull);
    expect(image.statusMessage, contains('node 28 (UNETLoader)'));
    expect(image.statusMessage, contains("unet_name: 'z_image_turbo_bf16"));
    expect(image.statusMessage, contains('127.0.0.1:${server.port}'));
  });

  test('a run that fails inside Comfy names the node and the error', () async {
    final server = await _comfy(refuse: false);
    addTearDown(server.close);
    final image = await _studio(server, dir);
    final bytes = await image.generateImage(prompt: 'a porch at dusk');
    expect(bytes, isNull);
    expect(image.statusMessage, contains('node 7 (KSampler)'));
    expect(image.statusMessage, contains('CUDA out of memory'));
  });
}
