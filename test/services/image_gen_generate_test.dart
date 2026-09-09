// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Behavior-pinning net for the parts of ImageGenService the existing suite
// (test/services/image_gen_service_test.dart) never touches: the 434-line
// generateImage() orchestration (Cluster A of the split map), the A1111/
// local-HTTP generator + payload wiring it drives (Cluster F), disk saves
// (Cluster B), local-server discovery/admin (Cluster E), and the remote
// model catalog (Cluster C). The existing suite pins types, buildA1111Payload
// in isolation, and the prompt thins — nothing exercises generateImage
// end-to-end, so a split that dropped a stub parameter, broke the
// _lastLoadedCheckpoint cross-part caching, or mis-routed a backend branch
// would go green everywhere else.
//
// Everything below talks to an in-process loopback HttpServer standing in
// for an AUTOMATIC1111-style local server (and, for the catalog group, an
// OpenRouter-shaped remote). No real network, no fixtures resembling real
// chat/character content — every prompt/name here is a neutral placeholder.
//
// NOT covered here (see the task's limitations writeup): the Draw Things
// gRPC generator, the ComfyUI HTTP+WS generator, and the remote OpenRouter /
// OpenAI-compatible *generation* endpoints (as opposed to the OpenRouter
// *catalog* endpoint, which IS covered below).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/capability/capability.dart'
    show StudioIntent;
import 'package:front_porch_ai/services/image/model_family.dart'
    show ModelFamily;
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

/// flutter_test's binding replaces every HttpClient with a mock that always
/// returns 400 (see flutter_test's `_MockHttpOverrides`); an un-overridden
/// HttpOverrides restores the real client so the test can talk to its own
/// loopback server. Same pattern as test/services/model_fetch_test.dart.
class _RealHttpOverrides extends HttpOverrides {}

Future<T> _withRealHttp<T>(Future<T> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

/// Deterministic, non-image fixture bytes — the service never decodes them
/// as an actual picture, only base64-round-trips and writes them to disk.
final Uint8List _fixtureBytes = Uint8List.fromList(<int>[
  0x10,
  0x20,
  0x30,
  0x40,
  0x50,
  0x60,
  0x70,
  0x80,
  0x90,
]);
final String _fixtureB64 = base64Encode(_fixtureBytes);

void main() {
  group('ImageGenService.generateImage — A1111 local HTTP path', () {
    late Directory tempDir;
    late _FakeLocalImageServer fake;
    late _FakeStorageForGenerate storage;
    late ImageGenService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('imagegen_net_');
      fake = await _FakeLocalImageServer.start();
      storage = _FakeStorageForGenerate(tempDir.path);
      await storage.imageGenSettings.setImageGenBackend('a1111');
      await storage.imageGenSettings.setLocalImageGenUrl(fake.baseUrl);
      fake.genImages = [_fixtureB64];
      service = ImageGenService(storage);
    });

    tearDown(() async {
      await fake.close();
      await tempDir.delete(recursive: true);
    });

    test(
      'routes prompt + settings into the exact txt2img payload and decodes '
      'the base64 response',
      () => _withRealHttp(() async {
        final bytes = await service.generateImage(
          prompt: 'a porch at dusk',
          negativePrompt: 'grainy',
        );
        expect(bytes, _fixtureBytes);
        expect(fake.txt2imgCount, 1);
        expect(fake.img2imgCount, 0);

        final sent = fake.lastTxt2ImgBody!;
        expect(sent['prompt'], 'a porch at dusk');
        expect(sent['negative_prompt'], 'grainy');
        expect(sent['width'], 1024);
        expect(sent['height'], 1024);
        expect(sent['steps'], storage.imageGenSettings.imageGenSteps);
        expect(sent['cfg_scale'], storage.imageGenSettings.imageGenCfgScale);
        expect(sent['sampler_name'], storage.imageGenSettings.imageGenSampler);
        expect(sent['seed'], storage.imageGenSettings.imageGenSeed);
        expect(sent.containsKey('scheduler'), isFalse); // 'Automatic' default
        expect(sent.containsKey('init_images'), isFalse);
        expect(sent.containsKey('denoising_strength'), isFalse);

        expect(service.isGenerating, isFalse);
        expect(service.statusMessage, 'Image generated successfully.');
        expect(service.lastGeneratedImage, bytes);
      }),
    );

    test(
      'a reference image routes to img2img with init_images + '
      'denoising_strength at the requested denoise',
      () => _withRealHttp(() async {
        final ref = Uint8List.fromList([9, 9, 9, 9]);
        final bytes = await service.generateImage(
          prompt: 'a porch at dusk',
          referenceImage: ref,
          denoise: 0.33,
        );
        expect(bytes, isNotNull);
        expect(fake.img2imgCount, 1);
        expect(fake.txt2imgCount, 0);

        final sent = fake.lastImg2ImgBody!;
        expect(sent['init_images'], [base64Encode(ref)]);
        expect(sent['denoising_strength'], 0.33);
        // Shared params still ride along on the img2img request too.
        expect(sent['steps'], storage.imageGenSettings.imageGenSteps);
      }),
    );

    test(
      'an empty reference image (non-null, zero bytes) still txt2imgs',
      () => _withRealHttp(() async {
        final bytes = await service.generateImage(
          prompt: 'a porch at dusk',
          referenceImage: Uint8List(0),
        );
        expect(bytes, isNotNull);
        expect(fake.txt2imgCount, 1);
        expect(fake.img2imgCount, 0);
      }),
    );

    test(
      'a configured LoRA is appended to the outgoing prompt as '
      '<lora:name:weight>',
      () => _withRealHttp(() async {
        await storage.imageGenSettings.setImageGenLora('warm_porch_style');
        await storage.imageGenSettings.setImageGenLoraWeight(0.65);
        await service.generateImage(prompt: 'a rocking chair');
        final sent = fake.lastTxt2ImgBody!;
        expect(sent['prompt'], 'a rocking chair <lora:warm_porch_style:0.65>');
      }),
    );

    test(
      'isPortrait swaps a landscape default size to portrait for the '
      'outgoing request',
      () => _withRealHttp(() async {
        await storage.imageGenSettings.setImageGenSize('1024x768');
        await service.generateImage(prompt: 'p', isPortrait: true);
        final sent = fake.lastTxt2ImgBody!;
        expect(sent['width'], 768);
        expect(sent['height'], 1024);
      }),
    );

    test(
      'an explicit size overrides the portrait auto-orientation',
      () => _withRealHttp(() async {
        await service.generateImage(
          prompt: 'p',
          isPortrait: true,
          size: '640x480',
        );
        final sent = fake.lastTxt2ImgBody!;
        expect(sent['width'], 640);
        expect(sent['height'], 480);
      }),
    );

    test(
      'an HTTP failure surfaces the server-provided detail without '
      'corrupting service state, and a later call still succeeds',
      () => _withRealHttp(() async {
        fake.genStatusCode = 500;
        fake.genErrorDetail = 'CUDA out of memory';
        final bytes = await service.generateImage(prompt: 'p');
        expect(bytes, isNull);
        expect(service.isGenerating, isFalse);
        expect(service.statusMessage, contains('CUDA out of memory'));
        expect(service.lastGeneratedImage, isNull);

        // The reentrancy guard must have been released by the finally block —
        // prove it by succeeding right after.
        fake.genStatusCode = 200;
        final retry = await service.generateImage(prompt: 'p again');
        expect(retry, isNotNull);
        expect(service.statusMessage, 'Image generated successfully.');
        expect(service.isGenerating, isFalse);
      }),
    );

    test(
      'a second overlapping call is refused while one is in flight '
      '(reentrancy guard) and the first still completes',
      () => _withRealHttp(() async {
        final f1 = service.generateImage(prompt: 'first');
        final f2 = service.generateImage(prompt: 'second');

        final r2 = await f2;
        expect(r2, isNull, reason: 'second call must be refused, not queued');

        final r1 = await f1;
        expect(r1, isNotNull);
        expect(
          fake.txt2imgCount,
          1,
          reason: 'only the first call reached the server',
        );
      }),
    );

    test(
      'an edit intent the backend cannot honor bails out before any '
      'network call',
      () => _withRealHttp(() async {
        final bytes = await service.generateImage(
          prompt: 'edit please',
          intent: StudioIntent.edit,
        );
        expect(bytes, isNull);
        expect(fake.requestLog, isEmpty);
        expect(service.statusMessage, isNotEmpty);
        expect(service.isGenerating, isFalse);
      }),
    );

    test(
      'switchLocalModel is skipped on a repeat call with the same checkpoint '
      'but re-triggered when the checkpoint changes (_lastLoadedCheckpoint '
      'caching, which crosses generateImage / _generateViaA1111 / '
      'switchLocalModel)',
      () => _withRealHttp(() async {
        await storage.imageGenSettings.setImageGenModel('checkpointA');

        await service.generateImage(prompt: 'p1');
        expect(fake.unloadCount, 1);
        expect(fake.optionsPostCount, 1);
        expect(fake.txt2imgCount, 1);

        await service.generateImage(prompt: 'p2'); // same checkpoint again
        expect(
          fake.unloadCount,
          1,
          reason: 'no redundant unload for the same checkpoint',
        );
        expect(
          fake.optionsPostCount,
          1,
          reason: 'no redundant switch for the same checkpoint',
        );
        expect(fake.txt2imgCount, 2);

        await storage.imageGenSettings.setImageGenModel('checkpointB');
        await service.generateImage(prompt: 'p3');
        expect(
          fake.optionsPostCount,
          2,
          reason: 'a different checkpoint must re-trigger the switch',
        );
        expect(fake.unloadCount, 2);
        expect(fake.txt2imgCount, 3);
      }),
    );

    test(
      'a missing local URL fails fast with no request and no crash',
      () => _withRealHttp(() async {
        await storage.imageGenSettings.setLocalImageGenUrl('');
        final bytes = await service.generateImage(prompt: 'p');
        expect(bytes, isNull);
        expect(fake.requestLog, isEmpty);
        expect(service.statusMessage, contains('No local server URL'));
        expect(service.isGenerating, isFalse);
      }),
    );
  });

  group('ImageGenService disk persistence', () {
    late Directory tempDir;
    late _FakeStorageForGenerate storage;
    late ImageGenService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('imagegen_save_');
      storage = _FakeStorageForGenerate(tempDir.path);
      service = ImageGenService(storage);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test(
      'saveImageToDisk with nothing generated and no explicit bytes returns '
      'null and creates no directory',
      () async {
        final result = await service.saveImageToDisk();
        expect(result, isNull);
        final imagesDir = Directory(
          p.join(tempDir.path, 'KoboldManager', 'images'),
        );
        expect(await imagesDir.exists(), isFalse);
      },
    );

    test(
      'saveImageToDisk writes explicit bytes under KoboldManager/images and '
      'records the path',
      () async {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final savedPath = await service.saveImageToDisk(bytes);
        expect(savedPath, isNotNull);

        final file = File(savedPath!);
        expect(await file.exists(), isTrue);
        expect(await file.readAsBytes(), bytes);
        expect(
          p.dirname(savedPath),
          p.join(tempDir.path, 'KoboldManager', 'images'),
        );
        expect(p.basename(savedPath), matches(RegExp(r'^img_\d+\.png$')));
        expect(service.lastSavedPath, savedPath);
      },
    );

    test(
      'saveImageToDisk falls back to the last generated image when no '
      'explicit bytes are given',
      () => _withRealHttp(() async {
        // Populate _lastGeneratedImage the same way a real caller would —
        // through a genuine generateImage() call against a disposable local
        // fake server — rather than reaching into private state.
        final fake = await _FakeLocalImageServer.start();
        final fallback = Uint8List.fromList([7, 7, 7]);
        fake.genImages = [base64Encode(fallback)];
        await storage.imageGenSettings.setImageGenBackend('a1111');
        await storage.imageGenSettings.setLocalImageGenUrl(fake.baseUrl);
        final generated = await service.generateImage(prompt: 'seed');
        expect(generated, fallback);
        await fake.close();

        final savedPath = await service.saveImageToDisk();
        expect(savedPath, isNotNull);
        expect(await File(savedPath!).readAsBytes(), fallback);
      }),
    );

    test(
      'saveAvatarToDisk sanitizes the character name and writes under '
      'charactersDir',
      () async {
        final bytes = Uint8List.fromList([9, 8, 7]);
        final savedPath = await service.saveAvatarToDisk(
          bytes,
          characterName: "Wren O'Malley!!",
        );
        expect(savedPath, isNotNull);

        final file = File(savedPath!);
        expect(await file.exists(), isTrue);
        expect(await file.readAsBytes(), bytes);
        expect(p.dirname(savedPath), storage.charactersDir.path);
        expect(
          p.basename(savedPath),
          matches(RegExp(r'^Wren_OMalley_\d+\.png$')),
        );
      },
    );

    test('saveAvatarToDisk with no bytes at all returns null', () async {
      final result = await service.saveAvatarToDisk(null);
      expect(result, isNull);
    });
  });

  group('ImageGenService local A1111 discovery/admin (HTTP)', () {
    late _FakeLocalImageServer fake;
    late _FakeStorageForGenerate storage;
    late ImageGenService service;

    setUp(() async {
      fake = await _FakeLocalImageServer.start();
      storage = _FakeStorageForGenerate('/does/not/matter');
      await storage.imageGenSettings.setImageGenBackend('a1111');
      service = ImageGenService(storage);
    });

    tearDown(() async {
      await fake.close();
    });

    test(
      'testLocalConnection is true on a 200 from sd-models',
      () => _withRealHttp(() async {
        expect(await service.testLocalConnection(fake.baseUrl), isTrue);
      }),
    );

    test(
      'testLocalConnection is false on a non-200',
      () => _withRealHttp(() async {
        fake.sdModelsStatusCode = 404;
        expect(await service.testLocalConnection(fake.baseUrl), isFalse);
      }),
    );

    test(
      'testLocalConnection is false when nothing is listening',
      () => _withRealHttp(() async {
        final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final deadUrl = 'http://127.0.0.1:${closed.port}';
        await closed.close(force: true);
        expect(await service.testLocalConnection(deadUrl), isFalse);
      }),
    );

    test(
      'fetchA1111Models parses titles and drops blanks',
      () => _withRealHttp(() async {
        fake.sdModelsResponse = [
          {'title': 'porchCheckpoint_v1.safetensors'},
          {'title': ''},
          {'title': 'anotherCheckpoint.ckpt'},
        ];
        final models = await service.fetchA1111Models(fake.baseUrl);
        expect(models, [
          'porchCheckpoint_v1.safetensors',
          'anotherCheckpoint.ckpt',
        ]);
      }),
    );

    test(
      'fetchA1111Models returns empty on a non-200',
      () => _withRealHttp(() async {
        fake.sdModelsStatusCode = 500;
        expect(await service.fetchA1111Models(fake.baseUrl), isEmpty);
      }),
    );

    test(
      'fetchA1111Loras prefers alias over name, drops blank entries, and '
      'classifies family from metadata when present',
      () => _withRealHttp(() async {
        fake.lorasResponse = [
          {
            'name': 'raw_file_name_sdxl',
            'alias': 'Porch Glow XL',
            'metadata': {'ss_base_model_version': 'sdxl_base_1.0'},
          },
          {'name': 'sd15_only_lora'}, // no alias, no metadata -> name-detect
          {'name': '', 'alias': ''}, // dropped
        ];
        final loras = await service.fetchA1111Loras(fake.baseUrl);
        expect(loras.map((l) => l.name), ['Porch Glow XL', 'sd15_only_lora']);
        expect(loras[0].family, ModelFamily.sdxl);
        expect(loras[0].familyFromMetadata, isTrue);
        expect(loras[1].family, ModelFamily.sd15);
        expect(loras[1].familyFromMetadata, isFalse);
      }),
    );

    test(
      'fetchA1111Samplers parses names',
      () => _withRealHttp(() async {
        fake.samplersResponse = [
          {'name': 'Euler a'},
          {'name': 'DPM++ 2M Karras'},
        ];
        expect(await service.fetchA1111Samplers(fake.baseUrl), [
          'Euler a',
          'DPM++ 2M Karras',
        ]);
      }),
    );

    test(
      'fetchA1111Schedulers degrades to an empty list on a 404 (older '
      "forks / Draw Things' A1111 shim predate the endpoint)",
      () => _withRealHttp(() async {
        fake.schedulersStatusCode = 404;
        expect(await service.fetchA1111Schedulers(fake.baseUrl), isEmpty);
      }),
    );
  });

  group('ImageGenService.fetchImageModels — remote catalog', () {
    test(
      'lists NOTHING (and makes zero network calls) when no API key is '
      'configured',
      () => _withRealHttp(() async {
        // CONTRACT REVERSED 2026-08-13 (maintainer-directed). This test
        // used to pin "no key -> the curated catalog", and that behavior is
        // exactly how a user with no account saw a real-looking model menu,
        // concluded Remote API images were free, and hit "No API key
        // configured." on Generate. No account = no models now (the studio
        // panel explains where the key lives); the catalog is reserved for
        // CONFIGURED providers without a listing endpoint — the test below
        // this one, which is unchanged. The zero-network half of the old
        // assertion still stands: an unconfigured install must never probe.
        final fake = await _FakeLocalImageServer.start();
        final storage = _FakeStorageForGenerate('/does/not/matter');
        // remoteApiKey stays '' (the BackendSettings default).
        await storage.backendSettings.setRemoteApiUrl(
          '${fake.baseUrl}/openrouter.ai',
        );
        final service = ImageGenService(storage);
        final models = await service.fetchImageModels();
        expect(models, isEmpty);
        expect(fake.requestLog, isEmpty);
        await fake.close();
      }),
    );

    test(
      'returns the curated catalog with zero network calls for a '
      'non-OpenRouter provider',
      () => _withRealHttp(() async {
        final fake = await _FakeLocalImageServer.start();
        final storage = _FakeStorageForGenerate('/does/not/matter');
        // Vault is per-URL. Bind the host first or the key parks on the
        // default OpenRouter slot and this catalog sees empty.
        await storage.backendSettings.setRemoteApiUrl(
          '${fake.baseUrl}/nano-gpt',
        );
        await storage.backendSettings.setRemoteApiKey('key-123');
        final service = ImageGenService(storage);
        final models = await service.fetchImageModels();
        expect(models, hasLength(45));
        expect(fake.requestLog, isEmpty);
        await fake.close();
      }),
    );

    test(
      'an OpenRouter-shaped URL fetches from /models?output_modalities=image, '
      'extracts pricing, falls back id->name, and drops blank ids',
      () => _withRealHttp(() async {
        final fake = await _FakeLocalImageServer.start();
        fake.openRouterModelsResponse = {
          'data': [
            {
              'id': 'zeta-image-1',
              'name': 'Zeta Image One',
              'pricing': {'prompt': '0.001', 'completion': '0.002'},
            },
            {'id': '', 'name': 'should be dropped'},
            {'id': 'alpha-image-2', 'pricing': null},
          ],
        };
        final storage = _FakeStorageForGenerate('/does/not/matter');
        await storage.backendSettings.setRemoteApiUrl(
          '${fake.baseUrl}/openrouter.ai',
        );
        await storage.backendSettings.setRemoteApiKey('key-123');
        final service = ImageGenService(storage);
        final models = await service.fetchImageModels();

        expect(fake.openRouterModelsCount, 1);
        expect(models, hasLength(2));
        // Sorted by displayName with Dart's default (ordinal/case-sensitive)
        // String.compareTo: 'Zeta Image One' (capital Z, codepoint 90) sorts
        // before 'alpha-image-2' (lowercase a, codepoint 97).
        expect(models[0].id, 'zeta-image-1');
        expect(models[0].pricingInfo, r'$0.001 / $0.002');
        expect(models[0].isPaid, isTrue);
        expect(models[1].id, 'alpha-image-2');
        expect(models[1].name, 'alpha-image-2'); // id fallback (name was null)
        expect(models[1].pricingInfo, isNull);
        await fake.close();
      }),
    );

    test(
      'an OpenRouter-shaped URL that answers non-200 degrades to an empty '
      'list instead of throwing',
      () => _withRealHttp(() async {
        final fake = await _FakeLocalImageServer.start();
        fake.openRouterStatusCode = 500;
        final storage = _FakeStorageForGenerate('/does/not/matter');
        await storage.backendSettings.setRemoteApiUrl(
          '${fake.baseUrl}/openrouter.ai',
        );
        await storage.backendSettings.setRemoteApiKey('key-123');
        final service = ImageGenService(storage);
        final models = await service.fetchImageModels();
        expect(models, isEmpty);
        await fake.close();
      }),
    );
  });
}

/// Storage double: real, mutable [ImageGenSettings]/[BackendSettings] (the
/// exact concrete subtypes generateImage()'s typed `_storage.imageGenSettings
/// .imageGen*` / `_storage.backendSettings.remoteApi*` access needs), plus a
/// fixed rootPath/charactersDir. `noSuchMethod` covers the large remainder of
/// StorageService that these paths never touch.
class _FakeStorageForGenerate extends ChangeNotifier implements StorageService {
  _FakeStorageForGenerate(String rootPathValue)
    : rootPath = rootPathValue,
      charactersDir = Directory(
        p.join(rootPathValue, 'KoboldManager', 'Characters'),
      );

  @override
  final String? rootPath;

  @override
  final Directory charactersDir;

  @override
  final ImageGenSettings imageGenSettings = ImageGenSettings();

  @override
  final BackendSettings backendSettings = BackendSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-process stand-in for an AUTOMATIC1111-style local image server, plus
/// (for the catalog group) an OpenRouter-shaped `/models` endpoint mounted
/// under a synthetic `/openrouter.ai/...` path — `_isOpenRouterStyle` only
/// checks the URL for the substring "openrouter.ai", so this keeps the
/// OpenRouter catalog branch reachable over loopback with zero real network.
class _FakeLocalImageServer {
  _FakeLocalImageServer._(this._server);

  final HttpServer _server;
  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  /// Every request seen, as `"METHOD /path"` — asserted empty by tests that
  /// expect an early bail (no backend call should have happened at all).
  final List<String> requestLog = [];
  final List<String> unexpectedPaths = [];

  // ── txt2img / img2img ────────────────────────────────────────────────
  int txt2imgCount = 0;
  int img2imgCount = 0;
  Map<String, dynamic>? lastTxt2ImgBody;
  Map<String, dynamic>? lastImg2ImgBody;
  int genStatusCode = 200;
  List<String> genImages = const [];
  String? genErrorDetail;

  // ── checkpoint switch ───────────────────────────────────────────────
  int unloadCount = 0;
  int optionsPostCount = 0;
  int optionsGetCount = 0;
  String currentCheckpoint = '';

  // ── discovery/admin ─────────────────────────────────────────────────
  int sdModelsStatusCode = 200;
  List<Map<String, dynamic>> sdModelsResponse = const [];
  int lorasStatusCode = 200;
  List<Map<String, dynamic>> lorasResponse = const [];
  int samplersStatusCode = 200;
  List<Map<String, dynamic>> samplersResponse = const [];
  int schedulersStatusCode = 200;
  List<Map<String, dynamic>> schedulersResponse = const [];

  // ── OpenRouter-shaped catalog ────────────────────────────────────────
  int openRouterModelsCount = 0;
  int openRouterStatusCode = 200;
  Map<String, dynamic> openRouterModelsResponse = const {'data': []};

  static Future<_FakeLocalImageServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeLocalImageServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final method = req.method;
    final path = req.uri.path;
    String rawBody = '';
    try {
      rawBody = await utf8.decodeStream(req);
    } catch (_) {
      // Nothing to read (typical for GET) — proceed with an empty body.
    }
    requestLog.add('$method $path');
    try {
      if (path.startsWith('/openrouter.ai/models')) {
        openRouterModelsCount++;
        req.response.statusCode = openRouterStatusCode;
        if (openRouterStatusCode == 200) {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(openRouterModelsResponse));
        }
        return;
      }
      switch ('$method $path') {
        case 'POST /sdapi/v1/txt2img':
          txt2imgCount++;
          lastTxt2ImgBody = rawBody.isEmpty
              ? const {}
              : jsonDecode(rawBody) as Map<String, dynamic>;
          _writeGenResponse(req);
        case 'POST /sdapi/v1/img2img':
          img2imgCount++;
          lastImg2ImgBody = rawBody.isEmpty
              ? const {}
              : jsonDecode(rawBody) as Map<String, dynamic>;
          _writeGenResponse(req);
        case 'GET /sdapi/v1/progress':
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'progress': 0.0}));
        case 'POST /sdapi/v1/unload-checkpoint':
          unloadCount++;
          req.response.statusCode = 200;
        case 'POST /sdapi/v1/options':
          optionsPostCount++;
          final decoded = rawBody.isEmpty
              ? const <String, dynamic>{}
              : jsonDecode(rawBody) as Map<String, dynamic>;
          currentCheckpoint =
              decoded['sd_model_checkpoint']?.toString() ?? currentCheckpoint;
          req.response.statusCode = 200;
        case 'GET /sdapi/v1/options':
          optionsGetCount++;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({'sd_model_checkpoint': currentCheckpoint}),
          );
        case 'GET /sdapi/v1/sd-models':
          req.response.statusCode = sdModelsStatusCode;
          if (sdModelsStatusCode == 200) {
            req.response.headers.contentType = ContentType.json;
            req.response.write(jsonEncode(sdModelsResponse));
          }
        case 'GET /sdapi/v1/loras':
          req.response.statusCode = lorasStatusCode;
          if (lorasStatusCode == 200) {
            req.response.headers.contentType = ContentType.json;
            req.response.write(jsonEncode(lorasResponse));
          }
        case 'GET /sdapi/v1/samplers':
          req.response.statusCode = samplersStatusCode;
          if (samplersStatusCode == 200) {
            req.response.headers.contentType = ContentType.json;
            req.response.write(jsonEncode(samplersResponse));
          }
        case 'GET /sdapi/v1/schedulers':
          req.response.statusCode = schedulersStatusCode;
          if (schedulersStatusCode == 200) {
            req.response.headers.contentType = ContentType.json;
            req.response.write(jsonEncode(schedulersResponse));
          }
        default:
          unexpectedPaths.add('$method $path');
          req.response.statusCode = HttpStatus.notFound;
      }
    } finally {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  void _writeGenResponse(HttpRequest req) {
    req.response.statusCode = genStatusCode;
    req.response.headers.contentType = ContentType.json;
    if (genStatusCode == 200) {
      req.response.write(jsonEncode({'images': genImages}));
    } else {
      req.response.write(jsonEncode({'detail': genErrorDetail ?? 'error'}));
    }
  }
}
