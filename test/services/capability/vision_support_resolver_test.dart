// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proof tests for resolveForActiveLlm's local-backend branch — specifically
// the .kcpps fix: when a preset owns the model (lastUsedModelPath empty), the
// resolver must interrogate the PRESET's GGUF and honor the preset's own
// `mmproj` key, instead of returning a false-negative "none" (which used to
// suppress the chat photo attachment for every preset user). Uses the same
// synthetic-GGUF builder as gguf_vision_test.dart and a real StorageService
// over mock SharedPreferences (same harness as storage_service_test.dart).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/capability/model_capabilities.dart';
import 'package:front_porch_ai/services/capability/vision_support_resolver.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Build a minimal GGUF v3 file (string KVs + optional tensor names) — the
/// same shape gguf_vision_test.dart proves the parser against.
Uint8List _buildGguf({
  required Map<String, String> kv,
  List<String> tensorNames = const [],
}) {
  final builder = BytesBuilder();
  builder.add(utf8.encode('GGUF'));
  builder.add(_u32(3));
  builder.add(_u64(tensorNames.length));
  builder.add(_u64(kv.length));
  for (final entry in kv.entries) {
    final keyBytes = utf8.encode(entry.key);
    builder.add(_u64(keyBytes.length));
    builder.add(keyBytes);
    builder.add(_u32(8)); // string type
    final valBytes = utf8.encode(entry.value);
    builder.add(_u64(valBytes.length));
    builder.add(valBytes);
  }
  for (final name in tensorNames) {
    final nameBytes = utf8.encode(name);
    builder.add(_u64(nameBytes.length));
    builder.add(nameBytes);
    builder.add(_u32(1)); // n_dims
    builder.add(_u64(1)); // dim 0
    builder.add(_u32(0)); // ggml type
    builder.add(_u64(0)); // data offset
  }
  return Uint8List.fromList(builder.takeBytes());
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asUint32List()[0] = v;
Uint8List _u64(int v) => Uint8List(8)..buffer.asUint64List()[0] = v;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // path_provider mock so StorageService._init() resolves a docs dir.
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_vsr_docs_').path;
        }
        return null;
      });

  Future<StorageService> createStorageService() async {
    SharedPreferences.setMockInitialValues({});
    final service = StorageService();
    await service.initialized;
    return service;
  }

  late Directory dir;

  setUp(() {
    VisionSupportResolver.instance.clear();
    dir = Directory.systemTemp.createTempSync('fpai_vsr_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File writeGguf(String name, Uint8List bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  File writeKcpps(Map<String, dynamic> json) =>
      File('${dir.path}/preset.kcpps')..writeAsStringSync(jsonEncode(json));

  group('resolveForActiveLlm — .kcpps preset (local backends)', () {
    test('preset-owned multimodal model + preset mmproj → supported', () async {
      final model = writeGguf(
        'qwen2vl.gguf',
        _buildGguf(kv: {'general.architecture': 'qwen2vl'}),
      );
      final mmproj = writeGguf('mmproj.gguf', Uint8List.fromList([1, 2, 3]));
      final kcpps = writeKcpps({
        'model_param': model.path,
        'mmproj': mmproj.path,
      });
      final storage = await createStorageService();
      await storage.setActiveKcppsPath(kcpps.path);

      final support = await VisionSupportResolver.instance.resolveForActiveLlm(
        backend: BackendType.kobold,
        storage: storage,
      );
      expect(support.supported, isTrue);
      expect(support.source, VisionSource.ggufWithMmproj);
    });

    test('preset-owned multimodal model, no mmproj anywhere → none', () async {
      final model = writeGguf(
        'qwen2vl.gguf',
        _buildGguf(kv: {'general.architecture': 'qwen2vl'}),
      );
      final kcpps = writeKcpps({'model_param': model.path});
      final storage = await createStorageService();
      await storage.setActiveKcppsPath(kcpps.path);

      final support = await VisionSupportResolver.instance.resolveForActiveLlm(
        backend: BackendType.kobold,
        storage: storage,
      );
      expect(support.supported, isFalse);
    });

    test('preset-owned model with embedded projector → supported '
        'without any mmproj', () async {
      final model = writeGguf(
        'gemma-vision.gguf',
        _buildGguf(
          kv: {'general.architecture': 'gemma3'},
          tensorNames: ['v.blk.0.attn_q.weight'],
        ),
      );
      final kcpps = writeKcpps({'model': model.path});
      final storage = await createStorageService();
      await storage.setActiveKcppsPath(kcpps.path);

      final support = await VisionSupportResolver.instance.resolveForActiveLlm(
        backend: BackendType.kobold,
        storage: storage,
      );
      expect(support.supported, isTrue);
      expect(support.source, VisionSource.ggufEmbedded);
    });

    test('preset model file missing on disk → falls back to '
        'lastUsedModelPath', () async {
      final pickerModel = writeGguf(
        'picker-vision.gguf',
        _buildGguf(
          kv: {'general.architecture': 'llama'},
          tensorNames: ['mm.model.fc.weight'],
        ),
      );
      final kcpps = writeKcpps({
        'model_param': '${dir.path}/deleted-model.gguf',
      });
      final storage = await createStorageService();
      await storage.setActiveKcppsPath(kcpps.path);
      await storage.setLastUsedModelPath(pickerModel.path);

      final support = await VisionSupportResolver.instance.resolveForActiveLlm(
        backend: BackendType.kobold,
        storage: storage,
      );
      expect(support.supported, isTrue);
      expect(support.source, VisionSource.ggufEmbedded);
    });

    test('no preset, no picker model → none', () async {
      final storage = await createStorageService();
      final support = await VisionSupportResolver.instance.resolveForActiveLlm(
        backend: BackendType.kobold,
        storage: storage,
      );
      expect(support, VisionSupport.none);
    });

    test('no preset: picker model + app-mapped mmproj still resolves '
        '(pre-fix behavior preserved)', () async {
      final model = writeGguf(
        'llava.gguf',
        _buildGguf(kv: {'general.architecture': 'llava'}),
      );
      final mmproj = writeGguf(
        'llava-mmproj.gguf',
        Uint8List.fromList([1, 2, 3]),
      );
      final storage = await createStorageService();
      await storage.setLastUsedModelPath(model.path);
      await storage.setModelMmproj(model.path, mmproj.path);

      final support = await VisionSupportResolver.instance.resolveForActiveLlm(
        backend: BackendType.kobold,
        storage: storage,
      );
      expect(support.supported, isTrue);
      expect(support.source, VisionSource.ggufWithMmproj);
    });

    test('unrecognized-arch model + app-mapped mmproj → supported '
        '(the Wally case: a vision model our allowlist misses)', () async {
      // Arch NOT in alwaysMultimodalArches and no embedded projector — the
      // detector calls it text-only. The user attached its companion mmproj;
      // that must be trusted and enable vision.
      final model = writeGguf(
        'qwen3-heretic.gguf',
        _buildGguf(kv: {'general.architecture': 'qwen3'}),
      );
      final mmproj = writeGguf('qwen3-mmproj.gguf', Uint8List.fromList([1, 2]));
      final storage = await createStorageService();
      await storage.setLastUsedModelPath(model.path);
      await storage.setModelMmproj(model.path, mmproj.path);

      final support = await VisionSupportResolver.instance.resolveForActiveLlm(
        backend: BackendType.kobold,
        storage: storage,
      );
      expect(support.supported, isTrue);
      expect(support.source, VisionSource.ggufWithMmproj);
    });
  });

  group('resolveRemote — LM Studio / generic OpenAI-compatible hosts', () {
    const lmUrl = 'http://localhost:1234/v1';
    const model = 'google/gemma-4-12b-qat';

    tearDown(() {
      VisionSupportResolver.instance.httpClientFactory = http.Client.new;
      VisionSupportResolver.instance.clear();
    });

    /// Install a MockClient; [onProbe] handles POST /chat/completions,
    /// [onRestModels] handles GET /api/v0/models (LM Studio), and
    /// [onOmlxStatus] handles GET /v1/models/status (oMLX). A null handler
    /// → 404, like any server without that extension.
    void mockServer({
      http.Response Function(http.Request)? onRestModels,
      http.Response Function(http.Request)? onOmlxStatus,
      http.Response Function(http.Request)? onProbe,
      void Function(String path)? onRequest,
    }) {
      VisionSupportResolver.instance.httpClientFactory = () => MockClient((
        request,
      ) async {
        onRequest?.call(request.url.path);
        if (request.url.path.endsWith('/api/v0/models')) {
          return onRestModels?.call(request) ?? http.Response('Not Found', 404);
        }
        if (request.url.path.endsWith('/v1/models/status')) {
          return onOmlxStatus?.call(request) ?? http.Response('Not Found', 404);
        }
        if (request.url.path.endsWith('/chat/completions')) {
          return onProbe?.call(request) ??
              http.Response('unexpected probe', 500);
        }
        return http.Response('Not Found', 404);
      });
    }

    String lmModels({required String type, List<String>? capabilities}) =>
        jsonEncode({
          'object': 'list',
          'data': [
            {
              'id': model,
              'object': 'model',
              'type': type,
              'state': 'not-loaded',
              'capabilities': ?capabilities,
            },
          ],
        });

    test('LM Studio REST says vlm → supported WITHOUT firing the probe '
        '(works even while the model is not loaded)', () async {
      final paths = <String>[];
      mockServer(
        onRestModels: (_) => http.Response(lmModels(type: 'vlm'), 200),
        onRequest: paths.add,
      );
      final support = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: lmUrl,
        apiKey: '',
        modelName: model,
      );
      expect(support.supported, isTrue);
      expect(support.source, VisionSource.apiMetadata);
      expect(paths.any((p) => p.endsWith('/chat/completions')), isFalse);
    });

    test('LM Studio REST says llm (text-only) → none, and cached', () async {
      var restHits = 0;
      mockServer(
        onRestModels: (_) {
          restHits++;
          return http.Response(lmModels(type: 'llm'), 200);
        },
      );
      final first = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: lmUrl,
        apiKey: '',
        modelName: model,
      );
      final second = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: lmUrl,
        apiKey: '',
        modelName: model,
      );
      expect(first.supported, isFalse);
      expect(first.source, VisionSource.none);
      expect(second.source, VisionSource.none);
      expect(restHits, 1, reason: 'definitive verdicts are cached');
    });

    test('a /api/v0/models entry WITHOUT type/capabilities is not trusted '
        '— falls through instead of caching a false none', () async {
      mockServer(
        // Matching entry, but no discriminating field (not really LM Studio).
        onRestModels: (_) => http.Response(
          jsonEncode({
            'data': [
              {'id': model, 'object': 'model'},
            ],
          }),
          200,
        ),
        onProbe: (_) => http.Response('{"choices":[]}', 200),
      );
      final support = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: lmUrl,
        apiKey: '',
        modelName: model,
      );
      expect(support.supported, isTrue);
      expect(support.source, VisionSource.probe);
    });

    test('oMLX status says vlm → supported WITHOUT firing the probe '
        '(the probe is untrustworthy on oMLX: it can 200 while silently '
        'dropping images)', () async {
      final paths = <String>[];
      mockServer(
        onOmlxStatus: (_) => http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'mlx-community/Qwen2-VL-7B',
                'engine_type': 'vlm',
                'config_model_type': 'qwen2_vl',
                'loaded': true,
              },
            ],
          }),
          200,
        ),
        onRequest: paths.add,
      );
      final support = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: 'http://localhost:8000/v1',
        apiKey: '',
        modelName: 'mlx-community/Qwen2-VL-7B',
      );
      expect(support.supported, isTrue);
      expect(support.source, VisionSource.apiMetadata);
      expect(paths.any((p) => p.endsWith('/chat/completions')), isFalse);
    });

    test('oMLX status says llm → definitive none, probe never fires '
        '(a silent-200 can no longer fake vision support)', () async {
      final paths = <String>[];
      mockServer(
        onOmlxStatus: (_) => http.Response(
          jsonEncode({
            'models': [
              {'id': 'mlx-community/Llama-3-8B', 'engine_type': 'llm'},
            ],
          }),
          200,
        ),
        // A text model on oMLX might accept the probe with 200 anyway —
        // metadata must win before that lie is ever consulted.
        onProbe: (_) => http.Response('{"choices":[]}', 200),
        onRequest: paths.add,
      );
      final support = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: 'http://localhost:8000/v1',
        apiKey: '',
        modelName: 'mlx-community/Llama-3-8B',
      );
      expect(support.supported, isFalse);
      expect(support.source, VisionSource.none);
      expect(paths.any((p) => p.endsWith('/chat/completions')), isFalse);
    });

    test('oMLX status entry without a type signal → probe decides '
        '(tri-state fall-through)', () async {
      mockServer(
        onOmlxStatus: (_) => http.Response(
          jsonEncode({
            'data': [
              {'id': 'some-model', 'loaded': true},
            ],
          }),
          200,
        ),
        onProbe: (_) => http.Response(
          '{"error":"model does not support image input"}',
          400,
        ),
      );
      final support = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: 'http://localhost:8000/v1',
        apiKey: '',
        modelName: 'some-model',
      );
      expect(support.supported, isFalse);
      expect(support.source, VisionSource.none);
    });

    test(
      'no REST endpoint (vLLM etc.) + probe 200 → supported via probe',
      () async {
        mockServer(onProbe: (_) => http.Response('{"choices":[]}', 200));
        final support = await VisionSupportResolver.instance.resolveRemote(
          apiUrl: 'http://localhost:8000/v1',
          apiKey: '',
          modelName: 'some-model',
        );
        expect(support.supported, isTrue);
        expect(support.source, VisionSource.probe);
      },
    );

    test('probe 400 naming images → definitive none', () async {
      mockServer(
        onProbe: (_) =>
            http.Response('{"error":"Model does not support images"}', 400),
      );
      final support = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: 'http://localhost:8000/v1',
        apiKey: '',
        modelName: 'text-model',
      );
      expect(support.supported, isFalse);
      expect(support.source, VisionSource.none);
    });

    test(
      'probe error that says NOTHING about vision (404 model mismatch, '
      '500 engine hiccup) → unknown, NOT cached, retry can succeed',
      () async {
        mockServer(
          onProbe: (_) => http.Response('{"error":"No models loaded"}', 404),
        );
        final first = await VisionSupportResolver.instance.resolveRemote(
          apiUrl: 'http://localhost:8000/v1',
          apiKey: '',
          modelName: 'some-model',
        );
        expect(first.supported, isFalse);
        expect(
          first.source,
          VisionSource.unknown,
          reason: 'an inconclusive error must not read as "no vision"',
        );

        // Server recovers (model finished loading) — the retry must re-probe
        // because unknown was never cached, and now succeed.
        mockServer(onProbe: (_) => http.Response('{"choices":[]}', 200));
        final second = await VisionSupportResolver.instance.resolveRemote(
          apiUrl: 'http://localhost:8000/v1',
          apiKey: '',
          modelName: 'some-model',
        );
        expect(second.supported, isTrue);
        expect(second.source, VisionSource.probe);
      },
    );

    test('server fully unreachable → unknown, not cached', () async {
      VisionSupportResolver.instance.httpClientFactory = () =>
          MockClient((_) async => throw const SocketException('refused'));
      final support = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: lmUrl,
        apiKey: '',
        modelName: model,
      );
      expect(support.source, VisionSource.unknown);
    });

    test('OpenRouter metadata path is untouched: input_modalities decide, '
        'no LM Studio REST call, no probe', () async {
      final paths = <String>[];
      VisionSupportResolver.instance.httpClientFactory = () =>
          MockClient((request) async {
            paths.add(request.url.path);
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 'anthropic/claude-3.5-sonnet',
                    'architecture': {
                      'input_modalities': ['text', 'image'],
                    },
                  },
                ],
              }),
              200,
            );
          });
      final support = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'sk-or-x',
        modelName: 'anthropic/claude-3.5-sonnet',
      );
      expect(support.supported, isTrue);
      expect(support.source, VisionSource.apiMetadata);
      expect(paths.any((p) => p.contains('/api/v0/models')), isFalse);
      expect(paths.any((p) => p.endsWith('/chat/completions')), isFalse);
    });
  });
}
