// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The desk judges Ready from state, never writes what the person picked, keeps
// saved / template / legacy Comfy graphs, and shows a control for every
// setting a generate reads. The ComfyUI here is a real loopback server serving
// the official Flux.2 Klein template; every GGUF loader is a temp file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart';
import 'package:front_porch_ai/services/image/comfy_workflow_convert.dart';
import 'package:front_porch_ai/services/image/image_studio_remote.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk.dart';

import '../../services/image/city96_test_loader.dart';
import '../../services/image/city96_test_probe.dart';

const _kleinId = 'comfy:default:image_flux2_klein_text_to_image';
const _kleinFile =
    'test/fixtures/comfy_templates/image_flux2_klein_text_to_image.json';

const _kleinPicks = {
  '%MODEL_DIFFUSION%': 'flux-2-klein-base-4b.safetensors',
  '%MODEL_CLIP%': 'qwen_3_4b.safetensors',
  '%MODEL_VAE%': 'flux2-vae.safetensors',
  '%MODEL_DIFFUSION_2%': 'flux-2-klein-4b.safetensors',
  '%MODEL_CLIP_2%': 'qwen_3_4b.safetensors',
  '%MODEL_VAE_2%': 'flux2-vae.safetensors',
};

class _Comfy {
  _Comfy(this.server);

  final HttpServer server;
  int objectInfoReads = 0;
  DateTime lastRequest = DateTime.now();

  String get url => 'http://127.0.0.1:${server.port}';
}

/// A real loopback ComfyUI: a node list, the Klein template, and the model
/// lists a desk asks for.
Future<_Comfy> _serve() async {
  final template =
      jsonDecode(File(_kleinFile).readAsStringSync()) as Map<String, dynamic>;
  final classes = convertComfyUiToApi(
    template,
  ).values.whereType<Map>().map((n) => n['class_type'].toString()).toSet();
  List<Object> spec(String kind) => [kind, <String, Object>{}];
  Map<String, dynamic> loader(String input, List<String> files) => {
    'input': {
      'required': {
        input: [files],
      },
    },
  };
  final info = <String, dynamic>{
    for (final c in {
      ...classes,
      'UnetLoaderGGUF',
      'CLIPLoaderGGUF',
      'TextEncodeQwenImage21',
      'EmptySD3LatentImage',
      'KSampler',
      'VAEDecode',
      'SaveImage',
    })
      c: <String, dynamic>{},
    'RandomNoise': {
      'input': {
        'required': {'noise_seed': spec('INT')},
      },
    },
    'UNETLoader': loader('unet_name', ['flux-2-klein-4b.safetensors']),
    'CLIPLoader': loader('clip_name', ['qwen_3_4b.safetensors']),
    'VAELoader': loader('vae_name', ['flux2-vae.safetensors']),
  };
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final comfy = _Comfy(server);
  server.listen((request) async {
    comfy.lastRequest = DateTime.now();
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;
    if (path == '/object_info') {
      comfy.objectInfoReads++;
      request.response.write(jsonEncode(info));
    } else if (path == '/templates/image_flux2_klein_text_to_image.json') {
      request.response.write(File(_kleinFile).readAsStringSync());
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  addTearDown(() => server.close(force: true));
  return comfy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test answers every HTTP call with a 400. The loopback ComfyUI
  // needs real sockets; tests that must not reach the internet put this back.
  final noInternet = HttpOverrides.current;
  late Directory dir;
  late StorageService storage;

  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('desk-state');
    addTearDown(() => dir.deleteSync(recursive: true));
    storage = StorageService.sandbox(dir.path);
  });

  /// Settings need their preferences before anything is written to them.
  Future<void> initSettings() async {
    final prefs = await SharedPreferences.getInstance();
    storage.imageGenSettings.initializeBase(prefs, storage.notifyListeners);
    storage.imageGenSettings.load();
  }

  /// Waits for real loopback requests, then lets the frame catch up.
  Future<void> settle(
    WidgetTester tester, [
    _Comfy? comfy,
    int atLeast = 2,
    int stepMs = 100,
  ]) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: stepMs)),
      );
      await tester.pump();
      final quiet =
          comfy == null ||
          DateTime.now().difference(comfy.lastRequest).inMilliseconds > 400;
      if (i >= atLeast && quiet && find.text('Checking…').evaluate().isEmpty) {
        break;
      }
    }
  }

  Future<void> pumpDesk(
    WidgetTester tester, {
    _Comfy? comfy,
    bool edit = false,
    Size size = const Size(700, 4000),
  }) async {
    await tester.binding.setSurfaceSize(size);
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
            body: SingleChildScrollView(child: StudioDesk(editMode: edit)),
          ),
        ),
      ),
    );
    await tester.pump();
    await settle(tester, comfy);
  }

  Future<void> useKlein(_Comfy comfy) async {
    final s = storage.imageGenSettings;
    await s.setImageGenBackend('comfyui');
    await s.setComfyUiUrl(comfy.url);
    await s.setComfyCreateWorkflowId(_kleinId);
    for (final e in _kleinPicks.entries) {
      await s.setComfyCreateModelChoice(_kleinId, e.key, e.value);
    }
  }

  group('a template graph', () {
    testWidgets('is Ready and is not replaced by a bundled graph', (
      tester,
    ) async {
      await initSettings();
      final comfy = (await tester.runAsync(_serve))!;
      await useKlein(comfy);
      final s = storage.imageGenSettings;
      final before = Map<String, String>.from(s.comfyCreateModelChoices);

      await pumpDesk(tester, comfy: comfy);

      expect(find.text('Ready to generate.'), findsOneWidget);
      expect(s.comfyCreateWorkflowId, _kleinId);
      expect(s.comfyCreateModelChoices, before);
    });

    testWidgets('lists the graph\'s own files, each with a way to change it', (
      tester,
    ) async {
      await initSettings();
      final comfy = (await tester.runAsync(_serve))!;
      await useKlein(comfy);
      await pumpDesk(tester, comfy: comfy);

      expect(find.text('This graph also loads'), findsOneWidget);
      expect(find.text('Text encoder'), findsOneWidget);
      expect(find.text('Text encoder 2'), findsOneWidget);
      expect(find.text('VAE'), findsOneWidget);
      expect(find.text('VAE 2'), findsOneWidget);
      expect(find.text('Diffusion model 2'), findsOneWidget);
      expect(find.text('Change'), findsNWidgets(5));
    });

    testWidgets('picking a model keeps the graph and fills its own slot', (
      tester,
    ) async {
      await initSettings();
      final comfy = (await tester.runAsync(_serve))!;
      await useKlein(comfy);
      await pumpDesk(tester, comfy: comfy);
      final s = storage.imageGenSettings;

      await tester.tap(find.text('Change model'));
      await tester.pump();
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText == 'Search families or files',
        ),
        'my-klein.safetensors',
      );
      await tester.pump();
      await tester.tap(find.text('Use this name'));
      await settle(tester, comfy);

      expect(s.comfyCreateWorkflowId, _kleinId);
      expect(
        s.comfyCreateModelChoice(_kleinId, '%MODEL_DIFFUSION%'),
        'my-klein.safetensors',
      );
    });

    testWidgets('an explicit encoder that looks wrong is kept and listed', (
      tester,
    ) async {
      await initSettings();
      final comfy = (await tester.runAsync(_serve))!;
      await useKlein(comfy);
      await storage.imageGenSettings.setComfyCreateModelChoice(
        _kleinId,
        '%MODEL_CLIP%',
        'clip_l.safetensors',
      );
      await pumpDesk(tester, comfy: comfy);

      expect(find.text('clip_l.safetensors'), findsOneWidget);
      expect(
        storage.imageGenSettings.comfyCreateModelChoice(
          _kleinId,
          '%MODEL_CLIP%',
        ),
        'clip_l.safetensors',
      );
    });
  });

  testWidgets(
    'readiness is judged when a setting changes, not on every frame',
    (tester) async {
      await initSettings();
      final comfy = (await tester.runAsync(_serve))!;
      await useKlein(comfy);
      await pumpDesk(tester, comfy: comfy);
      final settled = comfy.objectInfoReads;
      expect(settled, greaterThan(0));

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      storage.imageGenSettings.notify();
      await storage.imageGenSettings.setImageGenSteps(12);
      await settle(tester, comfy);
      expect(
        comfy.objectInfoReads,
        settled,
        reason: 'frames and unrelated settings do not re-read the node list',
      );

      await storage.imageGenSettings.setComfyCreateModelChoice(
        _kleinId,
        '%MODEL_VAE%',
        'flux2-vae.safetensors2',
      );
      await settle(tester, comfy);
      expect(comfy.objectInfoReads, greaterThan(settled));
    },
  );

  testWidgets(
    'a model that needs the GGUF loader update says so, only for it',
    (tester) async {
      await initSettings();
      final comfy = (await tester.runAsync(_serve))!;
      final s = storage.imageGenSettings;
      await s.setImageGenBackend('comfyui');
      await s.setComfyUiUrl(comfy.url);
      await s.setComfyCreateWorkflowId('qwen_image_21');
      for (final e in {
        '%MODEL_DIFFUSION%': 'qwen-image-2.1-Q2_K.gguf',
        '%MODEL_CLIP%': 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf',
        '%MODEL_VAE%': 'qwen_image_2.1_vae_bf16.safetensors',
      }.entries) {
        await s.setComfyCreateModelChoice('qwen_image_21', e.key, e.value);
      }
      final loader = File('${dir.path}/loader.py')
        ..writeAsStringSync(kStockCity96Loader);
      final saved = City96Gate.instance;
      City96Gate.instance = City96Gate(
        locate: (_) async => loader,
        probe: const FakeProbe(me: 1000),
        pidFor: (_) async => 100,
      );
      addTearDown(() => City96Gate.instance = saved);

      await pumpDesk(tester, comfy: comfy);

      expect(find.textContaining(kCity96NeedsUpdate), findsOneWidget);
      expect(find.text('Ready to generate.'), findsNothing);
      expect(loader.readAsStringSync(), kStockCity96Loader);
    },
  );

  group('Update loader…', () {
    late File loader;
    late _Comfy comfy;
    var asked = 0;
    var answers = <bool?>[];

    Future<void> useQwen21(WidgetTester tester) async {
      await initSettings();
      comfy = (await tester.runAsync(_serve))!;
      final s = storage.imageGenSettings;
      await s.setImageGenBackend('comfyui');
      await s.setComfyUiUrl(comfy.url);
      await s.setComfyCreateWorkflowId('qwen_image_21');
      for (final e in {
        '%MODEL_DIFFUSION%': 'qwen-image-2.1-Q2_K.gguf',
        '%MODEL_CLIP%': 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf',
        '%MODEL_VAE%': 'qwen_image_2.1_vae_bf16.safetensors',
      }.entries) {
        await s.setComfyCreateModelChoice('qwen_image_21', e.key, e.value);
      }
      loader = File('${dir.path}/loader.py')
        ..writeAsStringSync(kStockCity96Loader);
      asked = 0;
      final saved = City96Gate.instance;
      City96Gate.instance = City96Gate(
        locate: (_) async => loader,
        probe: const FakeProbe(me: 1000),
        pidFor: (_) async => 100,
        // The real writer starts processes, which a widget test's fake clock
        // cannot wait for; the writer has its own tests.
        write: (loader, text) async => loader.writeAsStringSync(text),
        ask: (_) async {
          asked++;
          return answers.removeAt(0);
        },
      );
      addTearDown(() => City96Gate.instance = saved);
      await pumpDesk(tester, comfy: comfy);
    }

    testWidgets('is offered when the model needs the update, and asks once', (
      tester,
    ) async {
      answers = [true];
      await useQwen21(tester);

      expect(find.textContaining(kCity96NeedsUpdate), findsOneWidget);
      expect(find.text('Update loader…'), findsOneWidget);
      expect(asked, 0, reason: 'nothing is asked until it is pressed');

      await tester.tap(find.text('Update loader…'));
      await settle(tester, comfy, 60, 30);

      expect(asked, 1);
      expect(loader.readAsStringSync(), contains('qwen3vl'));
      expect(find.textContaining('Restart ComfyUI'), findsWidgets);
      expect(find.text('Update loader…'), findsNothing);
      expect(find.text('Ready to generate.'), findsNothing);
    });

    testWidgets('asks again each time it is pressed, after a "no"', (
      tester,
    ) async {
      answers = [false, true];
      await useQwen21(tester);

      await tester.tap(find.text('Update loader…'));
      await settle(tester, comfy, 60, 30);
      expect(asked, 1);
      expect(loader.readAsStringSync(), kStockCity96Loader);
      expect(find.text('Update loader…'), findsOneWidget);

      await tester.tap(find.text('Update loader…'));
      await settle(tester, comfy, 60, 30);
      expect(asked, 2);
      expect(loader.readAsStringSync(), contains('qwen3vl'));
    });

    testWidgets('a closed window is not a "no": the button stays', (
      tester,
    ) async {
      answers = [null];
      await useQwen21(tester);

      await tester.tap(find.text('Update loader…'));
      await settle(tester, comfy, 60, 30);

      expect(loader.readAsStringSync(), kStockCity96Loader);
      expect(find.text('Update loader…'), findsOneWidget);
    });

    testWidgets('is not offered when the loader cannot be changed here', (
      tester,
    ) async {
      answers = [];
      await useQwen21(tester);
      loader.writeAsStringSync('# a fork of ComfyUI-GGUF\n');
      await tester.tap(find.text('Check'));
      await settle(tester, comfy, 60, 30);

      expect(find.textContaining('does not recognize'), findsOneWidget);
      expect(find.text('Update loader…'), findsNothing);
    });
  });

  group('every setting a generate reads has a control', () {
    testWidgets('Remote: host, model list, style, prompt format, review', (
      tester,
    ) async {
      await initSettings();
      HttpOverrides.global = noInternet;
      final s = storage.imageGenSettings;
      final host = kImageStudioRemoteHosts.first.url;
      await s.setImageGenBackend('remote');
      await s.setImageRemoteApiUrl(host);
      await storage.backendSettings.setRemoteApiKeyFor(host, 'test-key');
      await pumpDesk(tester);

      await tester.tap(find.textContaining('Advanced'));
      await tester.pump();
      expect(find.text('Nano-GPT'), findsWidgets);
      expect(find.text('Style'), findsOneWidget);
      expect(find.text('Prompt format'), findsOneWidget);
      expect(find.text('Review AI prompts before generating'), findsOneWidget);
      // Remote APIs take no seed and no negative prompt.
      expect(find.text('Seed'), findsNothing);
      expect(find.text('Negative prompt'), findsNothing);

      // The model list is not empty once a key is set.
      await tester.tap(find.text('Change model'));
      await tester.pump();
      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('Comfy: seed, negative prompt, style, review', (tester) async {
      await initSettings();
      final comfy = (await tester.runAsync(_serve))!;
      await useKlein(comfy);
      await pumpDesk(tester, comfy: comfy);
      final s = storage.imageGenSettings;

      await tester.tap(find.textContaining('Advanced'));
      await tester.pump();
      expect(find.text('Seed'), findsOneWidget);
      expect(find.text('Negative prompt'), findsOneWidget);
      expect(find.text('CFG Zero'), findsNothing);
      // Comfy graphs read the sampling shift, so it has a slider here too.
      expect(find.text('Shift'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '-1'), '42');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(s.imageGenSeed, 42);

      final review = find.widgetWithText(
        SwitchListTile,
        'Review AI prompts before generating',
      );
      final was = s.imageGenPromptReview;
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pump();
      expect(s.imageGenPromptReview, !was);
    });

    testWidgets('Draw Things: port, shift, seed mode, TeaCache, CFG Zero', (
      tester,
    ) async {
      await initSettings();
      final s = storage.imageGenSettings;
      await s.setImageGenBackend('drawthings');
      await tester.binding.setSurfaceSize(const Size(700, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ImageGenService>(
              create: (_) => _NoGrpcImageGen(storage),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: StudioDesk())),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.textContaining('Advanced'));
      await tester.pump();

      expect(find.text('Draw Things port'), findsOneWidget);
      expect(find.text('Shift'), findsOneWidget);
      expect(find.text('Seed mode'), findsOneWidget);
      expect(find.text('TeaCache'), findsOneWidget);
      expect(find.text('CFG Zero'), findsOneWidget);
      expect(find.text('Negative prompt'), findsOneWidget);

      await tester.tap(find.widgetWithText(SwitchListTile, 'TeaCache'));
      await tester.tap(find.widgetWithText(SwitchListTile, 'CFG Zero'));
      await tester.pump();
      expect(s.drawThingsTeaCache, isTrue);
      expect(s.drawThingsCfgZeroStar, isTrue);
    });
  });
}

/// Draw Things is a gRPC server on this machine. A test never dials it.
class _NoGrpcImageGen extends ImageGenService {
  _NoGrpcImageGen(super.storage);

  @override
  Future<bool> testLocalConnection(String baseUrl) async => false;

  @override
  Future<List<String>> fetchDrawThingsModels(String baseUrl) async => const [];

  @override
  Future<Map<String, String>> fetchDrawThingsModelVersions(
    String baseUrl,
  ) async => const {};

  @override
  Future<List<LoraOption>> fetchDrawThingsLoras(String baseUrl) async =>
      const [];
}
