// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The desk's Shift reaches whichever sampling-shift node the graph has, in the
// graph posted to a real loopback ComfyUI: SD3, Flux (its max_shift) and
// AuraFlow, not only AuraFlow.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/comfy_edit_presets.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

Map<String, dynamic> _graph(
  String shiftClass,
  Map<String, Object> shiftInputs,
) {
  return {
    'ckpt': {
      'class_type': 'CheckpointLoaderSimple',
      'inputs': {'ckpt_name': 'model.safetensors'},
    },
    'shift': {
      'class_type': shiftClass,
      'inputs': {
        'model': ['ckpt', 0],
        ...shiftInputs,
      },
    },
    'pos': {
      'class_type': 'CLIPTextEncode',
      'inputs': {
        'text': 'a porch',
        'clip': ['ckpt', 1],
      },
    },
    'neg': {
      'class_type': 'CLIPTextEncode',
      'inputs': {
        'text': 'blur',
        'clip': ['ckpt', 1],
      },
    },
    'latent': {
      'class_type': 'EmptyLatentImage',
      'inputs': {'width': 1024, 'height': 1024, 'batch_size': 1},
    },
    'ks': {
      'class_type': 'KSampler',
      'inputs': {
        'model': ['shift', 0],
        'positive': ['pos', 0],
        'negative': ['neg', 0],
        'latent_image': ['latent', 0],
        'seed': 1,
        'steps': 20,
        'cfg': 7.0,
        'sampler_name': 'euler',
        'scheduler': 'normal',
        'denoise': 1.0,
      },
    },
    'decode': {
      'class_type': 'VAEDecode',
      'inputs': {
        'samples': ['ks', 0],
        'vae': ['ckpt', 2],
      },
    },
    'save': {
      'class_type': 'SaveImage',
      'inputs': {
        'images': ['decode', 0],
        'filename_prefix': 'fpai',
      },
    },
  };
}

void main() {
  setUp(() => HttpOverrides.global = null);

  /// Generates [graph] as an uploaded workflow with the shift at 6.5 and
  /// returns the posted shift node's inputs.
  Future<Map<String, dynamic>> postedShiftNode(
    Map<String, dynamic> graph,
  ) async {
    Map<String, dynamic>? posted;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final path = request.uri.path;
      request.response.headers.contentType = ContentType.json;
      if (path == '/object_info') {
        request.response.write(
          jsonEncode({
            for (final node in graph.values)
              (node as Map)['class_type'].toString(): <String, dynamic>{},
          }),
        );
      } else if (request.method == 'POST' && path == '/prompt') {
        final body = jsonDecode(await utf8.decodeStream(request)) as Map;
        posted = (body['prompt'] as Map).cast<String, dynamic>();
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('stop');
      } else {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final dir = Directory.systemTemp.createTempSync('comfy-shift');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    final settings = storage.imageGenSettings;
    await settings.setImageGenBackend('comfyui');
    await settings.setComfyUiUrl('http://127.0.0.1:${server.port}');
    await settings.setComfyCreateWorkflowId(kComfyUploadedWorkflowId);
    await settings.setComfyCreateUploadedWorkflow(jsonEncode(graph));
    await settings.setImageGenModel('model.safetensors');
    await settings.setEditShift(6.5);
    final image = ImageGenService(storage);
    await image.generateImage(prompt: 'a porch at dusk');
    expect(posted, isNotNull, reason: image.statusMessage);
    return (posted!['shift'] as Map)['inputs'] as Map<String, dynamic>;
  }

  test('ModelSamplingSD3 takes the shift', () async {
    final node = await postedShiftNode(
      _graph('ModelSamplingSD3', {'shift': 3.0}),
    );
    expect(node['shift'], 6.5);
  });

  test('ModelSamplingAuraFlow takes the shift', () async {
    final node = await postedShiftNode(
      _graph('ModelSamplingAuraFlow', {'shift': 3.0}),
    );
    expect(node['shift'], 6.5);
  });

  test('ModelSamplingFlux takes the shift as its max shift', () async {
    final node = await postedShiftNode(
      _graph('ModelSamplingFlux', {
        'max_shift': 1.15,
        'base_shift': 0.5,
        'width': 1024,
        'height': 1024,
      }),
    );
    expect(node['max_shift'], 6.5);
    expect(node['base_shift'], 0.5, reason: 'only the max is the shift');
  });
}
