// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What a real loopback ComfyUI is sent: a graph posts its own sampling shift
// until Shift is moved for it, then the moved value reaches its ModelSampling
// `shift` (SD3, AuraFlow), and Flux's max_shift is never the Shift control's.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/comfy_edit_presets.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
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

  /// The whole graph a generate of [graph] posts.
  Future<Map<String, dynamic>> postedGraph(
    Map<String, dynamic> graph, {
    double? moved,
  }) async {
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
    if (moved != null) {
      await settings.setComfyShift(
        kComfyUploadedWorkflowId,
        moved,
        edit: false,
      );
    }
    final image = ImageGenService(storage);
    await image.generateImage(prompt: 'a porch at dusk');
    expect(posted, isNotNull, reason: image.statusMessage);
    return posted!;
  }

  /// The inputs of node [id] in the graph a generate posts.
  Future<Map<String, dynamic>> postedNode(
    Map<String, dynamic> graph,
    String id, {
    double? moved,
  }) async {
    final posted = await postedGraph(graph, moved: moved);
    return (posted[id] as Map)['inputs'] as Map<String, dynamic>;
  }

  /// Generates [graph] as an uploaded workflow, with Shift moved to
  /// [moved] when it is given, and returns the posted shift node's inputs.
  Future<Map<String, dynamic>> postedShiftNode(
    Map<String, dynamic> graph, {
    double? moved,
  }) => postedNode(graph, 'shift', moved: moved);

  for (final type in ['ModelSamplingSD3', 'ModelSamplingAuraFlow']) {
    test('$type posts its own shift until Shift is moved', () async {
      final graph = _graph(type, {'shift': 4.5});
      expect((await postedShiftNode(graph))['shift'], 4.5);
    });

    test('$type takes the shift once it is moved for the graph', () async {
      final graph = _graph(type, {'shift': 4.5});
      expect((await postedShiftNode(graph, moved: 6.5))['shift'], 6.5);
    });
  }

  test(
    'a shift on a node that is not ModelSampling is left alone, moved or not',
    () async {
      final graph = _graph('ModelSamplingSD3', {'shift': 4.5});
      graph['video'] = {
        'class_type': 'SomeVideoNode',
        'inputs': {
          'model': ['ckpt', 0],
          'shift': 9.5,
          'max_shift': 4.25,
        },
      };
      for (final moved in [null, 6.5]) {
        final other = await postedNode(graph, 'video', moved: moved);
        expect(other['shift'], 9.5, reason: 'moved: $moved');
        expect(other['max_shift'], 4.25);
        // The real shift node beside it does follow Shift.
        final real = await postedNode(graph, 'shift', moved: moved);
        expect(real['shift'], moved ?? 4.5);
      }
    },
  );

  test('ModelSamplingFlux keeps its max shift, moved or not', () async {
    final graph = _graph('ModelSamplingFlux', {
      'max_shift': 1.15,
      'base_shift': 0.5,
      'width': 1024,
      'height': 1024,
    });
    for (final moved in [null, 6.5]) {
      final node = await postedShiftNode(graph, moved: moved);
      expect(node['max_shift'], 1.15, reason: 'moved: $moved');
      expect(node['base_shift'], 0.5);
    }
  });
}
