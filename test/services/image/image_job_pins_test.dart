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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/image/edit_profile.dart';
import 'package:front_porch_ai/services/image/image_job.dart';
import 'package:front_porch_ai/services/image/image_studio_remote.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

Future<T> _withRealHttp<T>(Future<T> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

final Uint8List _png = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('planImageJob', () {
    test('create keeps the create slot when an edit model is also stored', () {
      final plan = planImageJob(
        backend: ImageGenBackend.a1111,
        intent: StudioIntent.create,
        explicitModel: null,
        createSlot: 'create-one.safetensors',
        editSlot: 'qwen-image-edit.ckpt',
        hostModel: '',
        attachedRefCount: 0,
      );
      expect(plan.model.model, 'create-one.safetensors');
      expect(plan.backend, ImageGenBackend.a1111);
      expect(plan.stopMessage, isNull);
    });

    test('edit reads the edit slot, not the create checkpoint', () {
      final plan = planImageJob(
        backend: ImageGenBackend.drawThings,
        intent: StudioIntent.edit,
        explicitModel: null,
        createSlot: 'sd_xl_base.safetensors',
        editSlot: 'qwen_image_edit_2509.ckpt',
        hostModel: '',
        attachedRefCount: 1,
      );
      expect(plan.model.model, 'qwen_image_edit_2509.ckpt');
      expect(plan.role, ImageReferenceRole.editConditioning);
      expect(plan.backend, ImageGenBackend.drawThings);
    });

    test('remote create refuses a leftover local filename', () {
      final plan = planImageJob(
        backend: ImageGenBackend.remote,
        intent: StudioIntent.create,
        explicitModel: null,
        createSlot: 'pretty.ckpt',
        editSlot: '',
        hostModel: '',
        attachedRefCount: 0,
      );
      expect(plan.model.stopped, isTrue);
      expect(plan.stopMessage, kRemoteLocalCheckpointMessage);
      expect(plan.model.clearCreateSlot, isTrue);
      expect(plan.model.clearEditSlot, isFalse);
    });

    test(
      'an edit model left in the create slot does not clear the edit slot',
      () {
        final plan = planImageJob(
          backend: ImageGenBackend.remote,
          intent: StudioIntent.edit,
          explicitModel: null,
          createSlot: 'pretty.ckpt',
          editSlot: 'also-local.safetensors',
          hostModel: '',
          attachedRefCount: 1,
        );
        expect(plan.model.clearEditSlot, isTrue);
        expect(plan.model.clearCreateSlot, isFalse);
      },
    );
  });

  group('drawThingsGenerationKnobs', () {
    test('edit uses the edit recipe, create keeps the txt2img knobs', () {
      final edit = drawThingsGenerationKnobs(
        role: ImageReferenceRole.editConditioning,
        createSteps: 4,
        createCfg: 1,
        createSampler: 16,
        createShift: 1,
        createSeedMode: 0,
        createStrength: 0.5,
        editSteps: kEditRecommendedSteps,
        editCfg: kEditRecommendedCfg,
        editSampler: kEditRecommendedSamplerInt,
        editShift: kEditRecommendedShift,
        editSeedMode: kEditRecommendedSeedMode,
        editStrength: null,
      );
      expect(edit.steps, kEditRecommendedSteps);
      expect(edit.cfg, kEditRecommendedCfg);
      expect(edit.sampler, kEditRecommendedSamplerInt);
      expect(edit.shift, kEditRecommendedShift);
      expect(edit.seedMode, kEditRecommendedSeedMode);
      expect(edit.strength, kEditRecommendedStrength);

      final create = drawThingsGenerationKnobs(
        role: ImageReferenceRole.none,
        createSteps: 4,
        createCfg: 1,
        createSampler: 16,
        createShift: 1,
        createSeedMode: 0,
        createStrength: 0.5,
        editSteps: 99,
        editCfg: 9,
        editSampler: 3,
        editShift: 8,
        editSeedMode: 1,
        editStrength: 0.2,
      );
      expect(create.steps, 4);
      expect(create.cfg, 1);
      expect(create.sampler, 16);
      expect(create.strength, 0.5);
      expect(edit.steps, isNot(create.steps));
      expect(edit.sampler, isNot(create.sampler));
    });
  });

  test('generateImage dispatches every backend from the shared plan', () {
    final source = File(
      'lib/services/image_gen_service.generate.dart',
    ).readAsStringSync();
    expect(source.contains('planImageJob'), isTrue);
    expect(source.contains('drawThingsGenerationKnobs'), isTrue);
    expect(source.contains('plan.backend == ImageGenBackend.a1111'), isTrue);
    expect(
      source.contains('plan.backend == ImageGenBackend.drawThings'),
      isTrue,
    );
    expect(source.contains('plan.backend == ImageGenBackend.comfyUi'), isTrue);
    expect(source.contains('plan.backend == ImageGenBackend.remote'), isTrue);
  });

  group('generateImage honors the plan', () {
    late Directory temp;
    late _HoldServer server;
    late _JobStorage storage;
    late ImageGenService service;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('image_job_pin_');
      server = await _HoldServer.start();
      storage = _JobStorage(temp.path);
      await storage.imageGenSettings.setImageGenBackend('a1111');
      await storage.imageGenSettings.setLocalImageGenUrl(server.baseUrl);
      service = ImageGenService(storage);
    });

    tearDown(() async {
      await server.close();
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    test('create loads the create checkpoint, not the edit model', () {
      return _withRealHttp(() async {
        await storage.imageGenSettings.setImageGenModel(
          'create-one.safetensors',
        );
        await storage.imageGenSettings.setImageGenEditModel(
          'qwen-image-edit.ckpt',
        );
        final bytes = await service.generateImage(
          prompt: 'a porch',
          intent: StudioIntent.create,
        );
        expect(bytes, _png);
        expect(server.checkpoint, 'create-one.safetensors');
        expect(server.txt2imgCount, 1);
      });
    });

    test('A1111 edit is refused before any request', () {
      return _withRealHttp(() async {
        final bytes = await service.generateImage(
          prompt: 'change the coat',
          intent: StudioIntent.edit,
          referenceImage: Uint8List.fromList(<int>[9, 9, 9]),
        );
        expect(bytes, isNull);
        expect(server.txt2imgCount, 0);
        expect(server.optionsCount, 0);
        expect(service.statusMessage, isNot(contains('successfully')));
        expect(service.statusMessage, isNotEmpty);
      });
    });

    test('a second generate while one is running returns null', () {
      return _withRealHttp(() async {
        server.holdTxt2Img = Completer<void>();
        final started = Completer<void>();
        server.onTxt2Img = () {
          if (!started.isCompleted) started.complete();
        };
        final first = service.generateImage(prompt: 'hold');
        await started.future.timeout(const Duration(seconds: 5));
        final second = await service.generateImage(prompt: 'overlap');
        expect(second, isNull);
        expect(service.statusMessage, kAlreadyGeneratingMessage);
        expect(server.txt2imgCount, 1);
        server.holdTxt2Img!.complete();
        expect(await first, _png);
      });
    });

    test(
      'remote create clears a leftover checkpoint and does not call out',
      () {
        return _withRealHttp(() async {
          await storage.imageGenSettings.setImageGenBackend('remote');
          await storage.imageGenSettings.setImageGenModel('pretty.ckpt');
          final bytes = await service.generateImage(prompt: 'a porch');
          expect(bytes, isNull);
          expect(service.statusMessage, kRemoteLocalCheckpointMessage);
          expect(storage.imageGenSettings.imageGenModel, isEmpty);
          expect(server.requestLog, isEmpty);
        });
      },
    );
  });
}

class _HoldServer {
  _HoldServer._(this._server);

  final HttpServer _server;
  String get baseUrl => 'http://${_server.address.host}:${_server.port}';
  int txt2imgCount = 0;
  int optionsCount = 0;
  String checkpoint = '';
  final List<String> requestLog = [];
  Completer<void>? holdTxt2Img;
  void Function()? onTxt2Img;

  static Future<_HoldServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _HoldServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final key = '${req.method} ${req.uri.path}';
    final body = await utf8.decodeStream(req);
    requestLog.add(key);
    try {
      switch (key) {
        case 'POST /sdapi/v1/unload-checkpoint':
          req.response.statusCode = 200;
        case 'POST /sdapi/v1/options':
          optionsCount++;
          final decoded = body.isEmpty
              ? const <String, dynamic>{}
              : jsonDecode(body) as Map<String, dynamic>;
          checkpoint = decoded['sd_model_checkpoint']?.toString() ?? checkpoint;
          req.response.statusCode = 200;
        case 'GET /sdapi/v1/options':
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'sd_model_checkpoint': checkpoint}));
        case 'GET /sdapi/v1/progress':
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'progress': 0}));
        case 'POST /sdapi/v1/txt2img':
          txt2imgCount++;
          onTxt2Img?.call();
          final hold = holdTxt2Img;
          if (hold != null) await hold.future;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'images': [base64Encode(_png)],
            }),
          );
        default:
          req.response.statusCode = HttpStatus.notFound;
      }
    } finally {
      await req.response.close();
    }
  }
}

class _JobStorage extends ChangeNotifier implements StorageService {
  _JobStorage(String root)
    : rootPath = root,
      charactersDir = Directory(p.join(root, 'Characters'));

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
