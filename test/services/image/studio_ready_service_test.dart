// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One Ready rule. It talks to a real loopback ComfyUI that serves the official
// Flux.2 Klein template and a node list, the way Comfy does, and runs the same
// workflow through the readiness service and through a generate. Every loader
// the GGUF gate could touch is a temp file.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart';
import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/image/comfy_workflow_convert.dart';
import 'package:front_porch_ai/services/image/studio_readiness.dart';
import 'package:front_porch_ai/services/image/studio_ready_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'city96_test_loader.dart';

const _kleinId = 'comfy:default:image_flux2_klein_text_to_image';
const _kleinFile =
    'test/fixtures/comfy_templates/'
    'image_flux2_klein_text_to_image.json';

/// The nodes the Klein template uses, with the widgets a live `/object_info`
/// lists for the ones whose values a conversion has no other way to place.
Map<String, dynamic> _kleinObjectInfo() {
  List<Object> spec(String kind) => [kind, <String, Object>{}];
  Map<String, dynamic> node(Map<String, Object> required) => {
    'input': {'required': required},
  };
  final template =
      jsonDecode(File(_kleinFile).readAsStringSync()) as Map<String, dynamic>;
  final classes = convertComfyUiToApi(
    template,
  ).values.whereType<Map>().map((n) => n['class_type'].toString()).toSet();
  return {
    for (final c in classes) c: <String, dynamic>{},
    'RandomNoise': node({'noise_seed': spec('INT')}),
    'KSamplerSelect': node({
      'sampler_name': [
        ['euler', 'dpmpp_2m'],
      ],
    }),
    'Flux2Scheduler': node({
      'steps': spec('INT'),
      'width': spec('INT'),
      'height': spec('INT'),
    }),
    'CFGGuider': node({
      'model': spec('MODEL'),
      'positive': spec('CONDITIONING'),
      'negative': spec('CONDITIONING'),
      'cfg': spec('FLOAT'),
    }),
    'PrimitiveInt': node({'value': spec('INT')}),
  };
}

/// A real loopback ComfyUI. Serves [objectInfo] and one template, and keeps
/// the graph a generate posts to `/prompt`.
Future<HttpServer> _comfy({
  required Map<String, dynamic> objectInfo,
  required void Function(Map<String, dynamic>) onPrompt,
  Map<String, String> templates = const {},
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/object_info') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(objectInfo));
    } else if (request.method == 'GET' && templates.containsKey(path)) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(templates[path]);
    } else if (request.method == 'POST' && path == '/upload/image') {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'name': 'ref.png'}));
    } else if (request.method == 'POST' && path == '/prompt') {
      final body = jsonDecode(await utf8.decodeStream(request));
      onPrompt(((body as Map)['prompt'] as Map).cast<String, dynamic>());
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

const _kleinPicks = {
  '%MODEL_DIFFUSION%': 'flux-2-klein-base-4b.safetensors',
  '%MODEL_CLIP%': 'qwen_3_4b.safetensors',
  '%MODEL_VAE%': 'flux2-vae.safetensors',
  '%MODEL_DIFFUSION_2%': 'flux-2-klein-4b.safetensors',
  '%MODEL_CLIP_2%': 'qwen_3_4b.safetensors',
  '%MODEL_VAE_2%': 'flux2-vae.safetensors',
};

void main() {
  late Directory dir;
  late StorageService storage;

  setUp(() {
    HttpOverrides.global = null;
    dir = Directory.systemTemp.createTempSync('studio-ready');
    addTearDown(() => dir.deleteSync(recursive: true));
    storage = StorageService.sandbox(dir.path);
  });

  Future<HttpServer> serveKlein(
    void Function(Map<String, dynamic>) onPrompt,
  ) async {
    final server = await _comfy(
      objectInfo: _kleinObjectInfo(),
      onPrompt: onPrompt,
      templates: {
        '/templates/image_flux2_klein_text_to_image.json': File(
          _kleinFile,
        ).readAsStringSync(),
      },
    );
    addTearDown(server.close);
    final settings = storage.imageGenSettings;
    await settings.setImageGenBackend('comfyui');
    await settings.setComfyUiUrl('http://127.0.0.1:${server.port}');
    await settings.setComfyCreateWorkflowId(_kleinId);
    for (final e in _kleinPicks.entries) {
      await settings.setComfyCreateModelChoice(_kleinId, e.key, e.value);
    }
    return server;
  }

  test(
    'a template workflow with its files picked is Ready, and a generate posts '
    'the graph Ready judged',
    () async {
      Map<String, dynamic>? posted;
      await serveKlein((g) => posted = g);
      final settings = storage.imageGenSettings;

      final report = await checkStudioReady(settings: settings, edit: false);
      expect(report.readiness.kind, StudioReady.ready);
      expect(report.ready, isTrue);
      expect(report.workflowId, _kleinId);

      final image = ImageGenService(storage);
      await image.generateImage(prompt: 'a porch at dusk');
      expect(posted, isNotNull, reason: image.statusMessage);

      // The widget values only a live node list can place are on both graphs.
      final judged = report.readiness.graph!;
      for (final id in judged.keys) {
        final a = judged[id] as Map;
        final b = posted![id] as Map;
        expect(b['class_type'], a['class_type'], reason: id);
        if (a['class_type'] == 'RandomNoise') {
          expect((a['inputs'] as Map).containsKey('noise_seed'), isTrue);
          expect((b['inputs'] as Map).containsKey('noise_seed'), isTrue);
        }
        if (a['class_type'] == 'Flux2Scheduler') {
          expect((a['inputs'] as Map)['steps'], isA<int>());
          expect((b['inputs'] as Map)['steps'], (a['inputs'] as Map)['steps']);
        }
      }
    },
  );

  test('a saved or template graph is judged on its own template', () async {
    await serveKlein((_) {});
    final report = await checkStudioReady(
      settings: storage.imageGenSettings,
      edit: false,
    );
    expect(report.readiness.kind, StudioReady.ready);
  });

  test('a file left empty is not Ready', () async {
    await serveKlein((_) {});
    final settings = storage.imageGenSettings;
    await settings.setComfyCreateModelChoice(_kleinId, '%MODEL_VAE%', '');
    final report = await checkStudioReady(settings: settings, edit: false);
    expect(report.readiness.kind, StudioReady.missingFile);
  });

  test('a ComfyUI that cannot be read is unreachable', () async {
    final server = await serveKlein((_) {});
    await server.close(force: true);
    final report = await checkStudioReady(
      settings: storage.imageGenSettings,
      edit: false,
    );
    expect(report.readiness.kind, StudioReady.unreachable);
  });

  group('an Edit template workflow', () {
    const editId = 'comfy:default:edit-parity';

    /// A saved-style UI graph. ImageScaleToTotalPixels is a node no bundled
    /// widget table knows, so its value only lands when the live node list is
    /// used to convert.
    final template = jsonEncode({
      'nodes': [
        {
          'id': 1,
          'type': 'LoadImage',
          'widgets_values': ['in.png', 'image'],
        },
        {
          'id': 2,
          'type': 'ImageScaleToTotalPixels',
          'inputs': [
            {'name': 'image', 'link': 1},
          ],
          'widgets_values': ['lanczos', 1.5],
        },
        {
          'id': 3,
          'type': 'UNETLoader',
          'widgets_values': ['unet.safetensors', 'default'],
        },
        {
          'id': 4,
          'type': 'CLIPLoader',
          'widgets_values': ['clip.safetensors', 'qwen_image', 'default'],
        },
        {
          'id': 5,
          'type': 'VAELoader',
          'widgets_values': ['vae.safetensors'],
        },
        {
          'id': 6,
          'type': 'TextEncodeQwenImageEditPlus',
          'widgets_values': ['change the light'],
        },
        {
          'id': 7,
          'type': 'KSampler',
          'widgets_values': [1, 'randomize', 20, 4, 'euler', 'simple', 1],
        },
        {
          'id': 8,
          'type': 'SaveImage',
          'widgets_values': ['out'],
        },
      ],
      'links': [
        [1, 1, 0, 2, 0, 'IMAGE'],
      ],
    });

    Map<String, dynamic> info() {
      Map<String, dynamic> node(Map<String, Object> required) => {
        'input': {'required': required},
      };
      return {
        for (final c in [
          'LoadImage',
          'UNETLoader',
          'CLIPLoader',
          'VAELoader',
          'TextEncodeQwenImageEditPlus',
          'KSampler',
          'SaveImage',
        ])
          c: <String, dynamic>{},
        'ImageScaleToTotalPixels': node({
          'image': ['IMAGE', <String, Object>{}],
          'upscale_method': [
            ['lanczos', 'bilinear'],
          ],
          'megapixels': ['FLOAT', <String, Object>{}],
        }),
      };
    }

    Future<void> setUpEdit(HttpServer server) async {
      final settings = storage.imageGenSettings;
      await settings.setImageGenBackend('comfyui');
      await settings.setComfyUiUrl('http://127.0.0.1:${server.port}');
      await settings.setComfyEditWorkflowId(editId);
      for (final e in {
        '%MODEL_DIFFUSION%': 'unet.safetensors',
        '%MODEL_CLIP%': 'clip.safetensors',
        '%MODEL_VAE%': 'vae.safetensors',
      }.entries) {
        await settings.setComfyEditModelChoice(editId, e.key, e.value);
      }
    }

    test('is Ready, and its generate posts the graph Ready judged', () async {
      Map<String, dynamic>? posted;
      final server = await _comfy(
        objectInfo: info(),
        onPrompt: (g) => posted = g,
        templates: {'/templates/edit-parity.json': template},
      );
      addTearDown(server.close);
      await setUpEdit(server);

      final report = await checkStudioReady(
        settings: storage.imageGenSettings,
        edit: true,
      );
      expect(report.readiness.kind, StudioReady.ready);

      final image = ImageGenService(storage);
      await image.generateImage(
        prompt: 'change the light',
        referenceImage: Uint8List.fromList(const [1, 2, 3, 4]),
        intent: StudioIntent.edit,
      );
      expect(posted, isNotNull, reason: image.statusMessage);

      Map inputsOf(Map<String, dynamic> graph) =>
          graph.values.whereType<Map>().firstWhere(
                (n) => n['class_type'] == 'ImageScaleToTotalPixels',
              )['inputs']
              as Map;
      expect(inputsOf(report.readiness.graph!)['megapixels'], 1.5);
      expect(inputsOf(posted!)['megapixels'], 1.5);
      expect(inputsOf(posted!)['upscale_method'], 'lanczos');
    });
  });

  group('the GGUF loader gate', () {
    late File loader;
    var located = 0;

    City96Gate gate() => City96Gate(
      locate: (_) async {
        located++;
        return loader;
      },
    );

    Future<void> serveQwen21() async {
      final server = await _comfy(
        objectInfo: {
          for (final c in [
            'UnetLoaderGGUF',
            'CLIPLoaderGGUF',
            'UNETLoader',
            'CLIPLoader',
            'VAELoader',
            'TextEncodeQwenImage21',
            'EmptySD3LatentImage',
            'KSampler',
            'VAEDecode',
            'SaveImage',
          ])
            c: <String, dynamic>{},
        },
        onPrompt: (_) {},
      );
      addTearDown(server.close);
      final settings = storage.imageGenSettings;
      await settings.setImageGenBackend('comfyui');
      await settings.setComfyUiUrl('http://127.0.0.1:${server.port}');
      await settings.setComfyCreateWorkflowId('qwen_image_21');
      for (final e in {
        '%MODEL_DIFFUSION%': 'qwen-image-2.1-Q2_K.gguf',
        '%MODEL_CLIP%': 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf',
        '%MODEL_VAE%': 'qwen_image_2.1_vae_bf16.safetensors',
      }.entries) {
        await settings.setComfyCreateModelChoice(
          'qwen_image_21',
          e.key,
          e.value,
        );
      }
    }

    setUp(() {
      located = 0;
      loader = File(p.join(dir.path, 'loader.py'))
        ..writeAsStringSync(kStockCity96Loader);
    });

    test(
      'the 2.1 GGUF pair on a stock loader says that model needs the update, '
      'and nothing is written',
      () async {
        await serveQwen21();
        final report = await checkStudioReady(
          settings: storage.imageGenSettings,
          edit: false,
          gate: gate(),
        );
        expect(report.readiness.kind, StudioReady.needsLoaderUpdate);
        expect(report.ready, isFalse);
        expect(report.readiness.message, startsWith(kCity96NeedsUpdate));
        expect(located, 1);
        expect(loader.readAsStringSync(), kStockCity96Loader);
        expect(File('${loader.path}.bak').existsSync(), isFalse);
      },
    );

    test('an updated loader is Ready', () async {
      await serveQwen21();
      final updated = City96Gate(
        locate: (_) async => loader,
        ask: (_) async => true,
      );
      final graph = {
        '1': {
          'class_type': 'UnetLoaderGGUF',
          'inputs': {'unet_name': 'qwen-image-2.1-Q2_K.gguf'},
        },
      };
      await updated.ensure(comfyUrl: 'http://127.0.0.1:8188', graph: graph);
      final report = await checkStudioReady(
        settings: storage.imageGenSettings,
        edit: false,
        gate: gate(),
      );
      expect(report.readiness.kind, StudioReady.ready);
    });

    test('a model that is not the pair never looks for a loader', () async {
      final server = await _comfy(
        objectInfo: {
          for (final c in [
            'UnetLoaderGGUF',
            'CLIPLoaderGGUF',
            'UNETLoader',
            'CLIPLoader',
            'VAELoader',
            'CLIPTextEncode',
            'ConditioningZeroOut',
            'EmptySD3LatentImage',
            'ModelSamplingAuraFlow',
            'KSampler',
            'VAEDecode',
            'SaveImage',
          ])
            c: <String, dynamic>{},
        },
        onPrompt: (_) {},
      );
      addTearDown(server.close);
      final settings = storage.imageGenSettings;
      await settings.setImageGenBackend('comfyui');
      await settings.setComfyUiUrl('http://127.0.0.1:${server.port}');
      await settings.setComfyCreateWorkflowId('z_image_turbo');
      for (final e in {
        '%MODEL_DIFFUSION%': 'z-image-turbo-Q5_K_M.gguf',
        '%MODEL_CLIP%': 'qwen_3_4b.safetensors',
        '%MODEL_VAE%': 'ae.safetensors',
      }.entries) {
        await settings.setComfyCreateModelChoice(
          'z_image_turbo',
          e.key,
          e.value,
        );
      }
      final report = await checkStudioReady(
        settings: settings,
        edit: false,
        gate: gate(),
      );
      expect(report.readiness.kind, StudioReady.ready);
      expect(located, 0);
    });
  });
}
