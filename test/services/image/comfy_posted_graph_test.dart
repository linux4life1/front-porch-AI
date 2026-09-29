// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'city96_test_loader.dart';

/// A real loopback ComfyUI. Records the graph posted to `/prompt`.
Future<HttpServer> _comfy(
  void Function(Map<String, dynamic>) onPrompt, {
  bool serveObjectInfo = true,
  void Function()? onObjectInfo,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/object_info') {
      onObjectInfo?.call();
      if (!serveObjectInfo) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('unread');
      } else {
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
      }
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

/// A gate whose locator fails the test when called: no graph in this file
/// may look for a real ComfyUI-GGUF install. A test that needs a loader hands
/// in its own temp file.
City96Gate _noRealInstall() => City96Gate(
  locate: (_) async => fail('a real ComfyUI-GGUF install was looked up'),
);

void main() {
  setUp(() {
    HttpOverrides.global = null;
    final saved = City96Gate.instance;
    City96Gate.instance = _noRealInstall();
    addTearDown(() => City96Gate.instance = saved);
  });

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

  test(
    'a checkpoint create still posts when the node list cannot be read',
    () async {
      Map<String, dynamic>? posted;
      final server = await _comfy(
        (graph) => posted = graph,
        serveObjectInfo: false,
      );
      addTearDown(server.close);
      final image = await _studio(
        server,
        workflowId: 'sd',
        choices: const {'%MODEL_CHECKPOINT%': 'v1-5-pruned.safetensors'},
      );
      await image.generateImage(prompt: 'a porch at dusk');

      expect(posted, isNotNull, reason: image.statusMessage);
      expect(
        image.statusMessage,
        isNot(contains('node list could not be read')),
      );
      expect(_classes(posted!), contains('CheckpointLoaderSimple'));
      expect(jsonEncode(posted), contains('v1-5-pruned.safetensors'));
    },
  );

  test(
    'a safetensors edit still posts when the node list cannot be read',
    () async {
      Map<String, dynamic>? posted;
      final server = await _comfy(
        (graph) => posted = graph,
        serveObjectInfo: false,
      );
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
          tokenValues: const {'%MODEL_DIFFUSION%': 'edit-model.safetensors'},
          primaryFile: 'edit-model.safetensors',
        );
      } catch (_) {}

      expect(posted, isNotNull);
      expect(_classes(posted!), contains('UNETLoader'));
      expect(_classes(posted!), isNot(contains('UnetLoaderGGUF')));
    },
  );

  test(
    'a gguf create does not post when the node list cannot be read',
    () async {
      Map<String, dynamic>? posted;
      final server = await _comfy(
        (graph) => posted = graph,
        serveObjectInfo: false,
      );
      addTearDown(server.close);
      final image = await _studio(
        server,
        workflowId: 'z_image_turbo',
        choices: const {
          '%MODEL_DIFFUSION%': 'z-image-turbo-Q5_K_M.gguf',
          '%MODEL_CLIP%': 'qwen_3_4b.safetensors',
          '%MODEL_VAE%': 'ae.safetensors',
        },
      );
      await image.generateImage(prompt: 'a porch at dusk');

      expect(posted, isNull);
      expect(image.statusMessage, contains('node list could not be read'));
    },
  );

  test(
    'a gguf text encoder does not post when the node list cannot be read',
    () async {
      Map<String, dynamic>? posted;
      final server = await _comfy(
        (graph) => posted = graph,
        serveObjectInfo: false,
      );
      addTearDown(server.close);
      final image = await _studio(
        server,
        workflowId: 'z_image_turbo',
        choices: const {
          '%MODEL_DIFFUSION%': 'z-image-turbo.safetensors',
          '%MODEL_CLIP%': 'qwen_3_4b.gguf',
          '%MODEL_VAE%': 'ae.safetensors',
        },
      );
      await image.generateImage(prompt: 'a porch at dusk');

      expect(posted, isNull);
      expect(image.statusMessage, contains('node list could not be read'));
    },
  );

  test('one create reads the node list once', () async {
    var infoHits = 0;
    Map<String, dynamic>? posted;
    final server = await _comfy(
      (graph) => posted = graph,
      onObjectInfo: () => infoHits++,
    );
    addTearDown(server.close);
    final image = await _studio(
      server,
      workflowId: 'sd',
      choices: const {'%MODEL_CHECKPOINT%': 'v1-5-pruned.safetensors'},
    );
    await image.generateImage(prompt: 'a porch at dusk');

    expect(posted, isNotNull, reason: image.statusMessage);
    expect(infoHits, 1);
  });
  group('the City96 loader update', () {
    late Directory dir;
    late File loader;
    late List<City96Question> asked;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('comfy-post-city96');
      addTearDown(() => dir.deleteSync(recursive: true));
      loader = File('${dir.path}/loader.py')
        ..writeAsStringSync(kStockCity96Loader);
      asked = [];
    });

    City96Gate tempGate({bool yes = true}) => City96Gate(
      locate: (_) async => loader,
      ask: (q) async {
        asked.add(q);
        return yes;
      },
    );

    const qwen21 = {
      '%MODEL_DIFFUSION%': 'qwen-image-2.1-Q2_K.gguf',
      '%MODEL_CLIP%': 'qwen_2.5_vl_7b.safetensors',
      '%MODEL_VAE%': 'qwen_image_vae.safetensors',
    };

    test(
      'a Qwen-Image 2.1 GGUF create updates the temp loader, asks for a restart, and does not post',
      () async {
        City96Gate.instance = tempGate();
        Map<String, dynamic>? posted;
        final server = await _comfy((graph) => posted = graph);
        addTearDown(server.close);
        final image = await _studio(
          server,
          workflowId: 'z_image_turbo',
          choices: qwen21,
        );
        await image.generateImage(prompt: 'a porch at dusk');

        expect(asked, hasLength(1));
        expect(asked.single.loaderPath, loader.path);
        expect(posted, isNull);
        expect(image.statusMessage, contains('Restart ComfyUI'));
        expect(loader.readAsStringSync(), contains('arch == "qwen3vl"'));
        expect(
          File('${loader.path}.bak').readAsStringSync(),
          kStockCity96Loader,
        );
      },
    );

    test(
      'when it cannot update, that model says so plainly and nothing is posted',
      () async {
        City96Gate.instance = City96Gate(locate: (_) async => null);
        Map<String, dynamic>? posted;
        final server = await _comfy((graph) => posted = graph);
        addTearDown(server.close);
        final image = await _studio(
          server,
          workflowId: 'z_image_turbo',
          choices: qwen21,
        );
        await image.generateImage(prompt: 'a porch at dusk');

        expect(posted, isNull);
        expect(image.statusMessage, startsWith(kCity96NeedsUpdate));
        expect(image.statusMessage, isNot(contains('Check that ComfyUI')));
      },
    );

    test(
      'a declined update blocks that model and leaves the loader alone',
      () async {
        City96Gate.instance = tempGate(yes: false);
        final server = await _comfy((_) {});
        addTearDown(server.close);
        final image = await _studio(
          server,
          workflowId: 'z_image_turbo',
          choices: qwen21,
        );
        await image.generateImage(prompt: 'a porch at dusk');

        expect(image.statusMessage, contains('chose not to'));
        expect(loader.readAsStringSync(), kStockCity96Loader);
      },
    );

    test(
      'a qwen_3_4b GGUF encoder posts without the loader being looked at',
      () async {
        Map<String, dynamic>? posted;
        final server = await _comfy((graph) => posted = graph);
        addTearDown(server.close);
        final image = await _studio(
          server,
          workflowId: 'z_image_turbo',
          choices: const {
            '%MODEL_DIFFUSION%': 'z-image-turbo-Q5_K_M.gguf',
            '%MODEL_CLIP%': 'qwen_3_4b.safetensors',
            '%MODEL_VAE%': 'ae.safetensors',
          },
        );
        await image.generateImage(prompt: 'a porch at dusk');
        expect(posted, isNotNull, reason: image.statusMessage);
      },
    );

    test(
      'a saved Qwen-Image 2.1 choice the posted graph does not use changes nothing',
      () async {
        Map<String, dynamic>? posted;
        final server = await _comfy((graph) => posted = graph);
        addTearDown(server.close);
        final home = Directory.systemTemp.createTempSync('comfy-post-saved');
        addTearDown(() => home.deleteSync(recursive: true));
        final storage = StorageService.sandbox(home.path);
        final settings = storage.imageGenSettings;
        await settings.setImageGenBackend('comfyui');
        await settings.setComfyUiUrl('http://127.0.0.1:${server.port}');
        await settings.setComfyCreateWorkflowId('sd');
        await settings.setComfyCreateModelChoice(
          'sd',
          '%MODEL_CHECKPOINT%',
          'v1-5-pruned.safetensors',
        );
        await settings.setComfyEditModelChoice(
          'qwen_image_21_edit',
          '%MODEL_DIFFUSION%',
          'qwen-image-2.1-Q2_K.gguf',
        );
        await settings.setComfyCreateModelChoice(
          'qwen_image_21',
          '%MODEL_DIFFUSION%',
          'qwen-image-2.1-Q2_K.gguf',
        );
        final image = ImageGenService(storage);
        await image.generateImage(prompt: 'a porch at dusk');
        expect(posted, isNotNull, reason: image.statusMessage);
        expect(loader.readAsStringSync(), kStockCity96Loader);
      },
    );
  });
}

Future<ImageGenService> _studio(
  HttpServer server, {
  required String workflowId,
  required Map<String, String> choices,
}) async {
  final dir = Directory.systemTemp.createTempSync('comfy-post-studio');
  addTearDown(() => dir.deleteSync(recursive: true));
  final storage = StorageService.sandbox(dir.path);
  final settings = storage.imageGenSettings;
  await settings.setImageGenBackend('comfyui');
  await settings.setComfyUiUrl('http://127.0.0.1:${server.port}');
  await settings.setComfyCreateWorkflowId(workflowId);
  for (final entry in choices.entries) {
    await settings.setComfyCreateModelChoice(
      workflowId,
      entry.key,
      entry.value,
    );
  }
  return ImageGenService(storage);
}
