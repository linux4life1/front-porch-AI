// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The line beside Generate says what is missing, not a bare "Not ready.", and
// a dropped-in Create graph runs with the files it names. The ComfyUI here is
// a real loopback server.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/comfy_edit_presets.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk.dart';

import '../../helpers/real_temp_dir.dart';

const _zimageId = 'comfy:default:zimage';

/// A Z-Image style graph: diffusion model, text encoder and VAE loaders.
const _zimage = {
  'unet': {
    'class_type': 'UNETLoader',
    'inputs': {'unet_name': 'z_image_turbo_bf16.safetensors'},
  },
  'clip': {
    'class_type': 'CLIPLoader',
    'inputs': {'clip_name': 'qwen_3_4b.safetensors', 'type': 'lumina2'},
  },
  'vae': {
    'class_type': 'VAELoader',
    'inputs': {'vae_name': 'ae.safetensors'},
  },
  'shift': {
    'class_type': 'ModelSamplingAuraFlow',
    'inputs': {
      'model': ['unet', 0],
      'shift': 3.1,
    },
  },
  'pos': {
    'class_type': 'CLIPTextEncode',
    'inputs': {
      'text': 'a porch',
      'clip': ['clip', 0],
    },
  },
  'neg': {
    'class_type': 'CLIPTextEncode',
    'inputs': {
      'text': 'blur',
      'clip': ['clip', 0],
    },
  },
  'latent': {
    'class_type': 'EmptySD3LatentImage',
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
      'steps': 8,
      'cfg': 1,
      'sampler_name': 'euler',
      'scheduler': 'simple',
      'denoise': 1,
    },
  },
  'decode': {
    'class_type': 'VAEDecode',
    'inputs': {
      'samples': ['ks', 0],
      'vae': ['vae', 0],
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

class _Comfy {
  _Comfy(this.server);

  final HttpServer server;
  DateTime lastRequest = DateTime.now();

  String get url => 'http://127.0.0.1:${server.port}';
}

Future<_Comfy> _serve() async {
  Map<String, dynamic> loader(String input, List<String> files) => {
    'input': {
      'required': {
        input: [files],
      },
    },
  };
  final info = <String, dynamic>{
    for (final node in _zimage.values) node['class_type'].toString(): {},
    'UNETLoader': loader('unet_name', ['z_image_turbo_bf16.safetensors']),
    'CLIPLoader': loader('clip_name', ['qwen_3_4b.safetensors']),
    'VAELoader': loader('vae_name', ['ae.safetensors']),
  };
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final comfy = _Comfy(server);
  server.listen((request) async {
    comfy.lastRequest = DateTime.now();
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;
    if (path == '/object_info') {
      request.response.write(jsonEncode(info));
    } else if (path == '/templates/zimage.json') {
      request.response.write(jsonEncode(_zimage));
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  addTearDown(() => server.close(force: true));
  return comfy;
}

const _startedTimers = #studioDeskNotReadyTimers;

void _deskTest(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) {
    final timers = <Timer>[];
    return runZoned(
      () => body(tester),
      zoneValues: {_startedTimers: timers},
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = parent.createTimer(zone, duration, callback);
          timers.add(timer);
          return timer;
        },
      ),
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final noInternet = HttpOverrides.current;
  late Directory dir;
  late StorageService storage;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    dir = realTempDir('desk-not-ready');
    addTearDown(() => dir.deleteSync(recursive: true));
    storage = StorageService.sandbox(dir.path);
  });

  Future<void> initSettings() async {
    final prefs = await SharedPreferences.getInstance();
    storage.imageGenSettings.initializeBase(prefs, storage.notifyListeners);
    storage.imageGenSettings.load();
  }

  Future<void> settle(WidgetTester tester, [_Comfy? comfy]) async {
    final timers = Zone.current[_startedTimers] as List<Timer>? ?? const [];
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      final quiet =
          comfy == null ||
          DateTime.now().difference(comfy.lastRequest).inMilliseconds > 400;
      final idle = timers.every((timer) => !timer.isActive);
      if (i >= 2 &&
          quiet &&
          idle &&
          find.text('Checking…').evaluate().isEmpty) {
        break;
      }
    }
  }

  Future<void> pumpDesk(WidgetTester tester, [_Comfy? comfy]) async {
    await tester.binding.setSurfaceSize(const Size(700, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ImageGenService>(
            create: (_) => ImageGenService(storage),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StudioDesk(editMode: false, onGenerate: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await settle(tester, comfy);
  }

  bool generateOn(WidgetTester tester) => tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, 'Generate'))
      .enabled;

  _deskTest('names the files a graph still needs', (tester) async {
    await initSettings();
    final comfy = (await tester.runAsync(_serve))!;
    final s = storage.imageGenSettings;
    await s.setImageGenBackend('comfyui');
    await s.setComfyUiUrl(comfy.url);
    await s.setComfyCreateWorkflowId(_zimageId);
    await s.setComfyCreateModelChoice(
      _zimageId,
      '%MODEL_DIFFUSION%',
      'z_image_turbo_bf16.safetensors',
    );

    await pumpDesk(tester, comfy);

    expect(
      find.text('Not ready — choose a file for Text encoder and VAE.'),
      findsOneWidget,
    );
    expect(find.text('Not ready.'), findsNothing);
    expect(generateOn(tester), isFalse);
  });

  _deskTest('a dropped-in Create graph runs with the files it names', (
    tester,
  ) async {
    await initSettings();
    final comfy = (await tester.runAsync(_serve))!;
    final s = storage.imageGenSettings;
    await s.setImageGenBackend('comfyui');
    await s.setComfyUiUrl(comfy.url);
    await s.setComfyCreateUploadedWorkflow(jsonEncode(_zimage), title: 'mine');
    await s.setComfyCreateWorkflowId(kComfyUploadedWorkflowId);

    await pumpDesk(tester, comfy);

    expect(find.text('Ready to generate.'), findsOneWidget);
    expect(generateOn(tester), isTrue);
  });

  _deskTest('a fresh install says how to set up a model', (tester) async {
    HttpOverrides.global = noInternet;
    await initSettings();

    await pumpDesk(tester);

    // A fresh install is on Remote with no key: the panel asks for one.
    expect(
      find.text('Add a Nano-GPT key, or pick another host.'),
      findsOneWidget,
    );
    expect(generateOn(tester), isFalse);
  });
}
