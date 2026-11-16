// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web Voice & Media enable: VoiceFacade.apply writes tts/stt flags so a
// remote user can turn engines on without the desktop tab.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/caption/local_caption_service.dart';
import 'package:front_porch_ai/services/expression_classifier.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/voice_facade.dart';
import 'package:front_porch_ai/services/web/routes/voice_routes.dart';

import '../../golden/support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_voice_').path;
        }
        return null;
      });

  test('apply persists ttsEnabled and sttEnabled', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    final facade = VoiceFacade(FakeTtsService(), FakeSttService(), storage);

    expect(facade.status()['ttsEnabled'], isFalse);
    final next = await facade.apply({'ttsEnabled': true, 'sttEnabled': true});
    expect(next['ttsEnabled'], isTrue);
    expect(next['sttEnabled'], isTrue);
    expect(storage.ttsSettings.ttsEnabled, isTrue);
    expect(storage.sttSettings.sttEnabled, isTrue);
  });

  // Settings rebuild 7c: the rest of the desktop Voice & Media tab rides the
  // same status / settings pair.
  group('Voice & Media host keys', () {
    late StorageService storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      await storage.initialized;
    });

    test('status carries the desktop tab keys with their defaults', () {
      final s = VoiceFacade(
        FakeTtsService(),
        FakeSttService(),
        storage,
      ).status();
      expect(s['autoSendTranscription'], isFalse);
      // Image generation starts on (ImageGenSettings' own default).
      expect(s['imageGenEnabled'], isTrue);
      expect(s['expressionEnabled'], isFalse);
      expect(s['expressionMode'], 'llm');
      expect(s['expressionDisplay'], 'sidebar');
      expect(s['expressionRerollSame'], isFalse);
      expect(s['expressionEmojiBurst'], isFalse);
      expect(s['expressionEmojiBurstSize'], 28.0);
      expect(s['expressionFallback'], 'neutral');
      // Not wired: the page hides the ONNX button and the photo card.
      expect(s['onnxModel'], isNull);
      expect(s['photoHelper'], isNull);
      // The original keys are still there (additive only).
      expect(s.keys, containsAll(['ttsEnabled', 'sttEnabled', 'voices']));
    });

    test('apply writes every key through the desktop setters', () async {
      final facade = VoiceFacade(FakeTtsService(), FakeSttService(), storage);
      final next = await facade.apply({
        'autoSendTranscription': true,
        'imageGenEnabled': false,
        'expressionEnabled': true,
        'expressionMode': 'onnx',
        'expressionDisplay': 'both',
        'expressionRerollSame': true,
        'expressionEmojiBurst': true,
        'expressionEmojiBurstSize': 44,
        'expressionFallback': 'emoji',
      });
      expect(storage.sttSettings.autoSendTranscription, isTrue);
      expect(storage.imageGenSettings.imageGenEnabled, isFalse);
      final e = storage.expressionSettings;
      expect(e.expressionEnabled, isTrue);
      expect(e.expressionClassificationMode, 'onnx');
      expect(e.expressionDisplayMode, 'both');
      expect(e.expressionRerollSame, isTrue);
      expect(e.expressionEmojiBurst, isTrue);
      expect(e.expressionEmojiBurstSize, 44.0);
      expect(e.expressionFallback, 'emoji');
      expect(next['autoSendTranscription'], isTrue);
      expect(next['expressionMode'], 'onnx');

      // And back off: auto-send round-trips both ways.
      await facade.apply({'autoSendTranscription': false});
      expect(storage.sttSettings.autoSendTranscription, isFalse);
      expect(facade.status()['autoSendTranscription'], isFalse);
    });

    test('values outside the desktop choices are ignored', () async {
      final facade = VoiceFacade(FakeTtsService(), FakeSttService(), storage);
      await facade.apply({
        'autoSendTranscription': 'yes',
        'imageGenEnabled': 0,
        'expressionMode': 'gpt',
        'expressionDisplay': 5,
        'expressionFallback': 'confetti',
        'expressionEmojiBurstSize': 'big',
      });
      expect(storage.sttSettings.autoSendTranscription, isFalse);
      expect(storage.imageGenSettings.imageGenEnabled, isTrue);
      expect(storage.expressionSettings.expressionClassificationMode, 'llm');
      expect(storage.expressionSettings.expressionDisplayMode, 'sidebar');
      expect(storage.expressionSettings.expressionFallback, 'neutral');
      expect(storage.expressionSettings.expressionEmojiBurstSize, 28.0);
    });

    test('burst size lands on the desktop slider stops', () async {
      final facade = VoiceFacade(FakeTtsService(), FakeSttService(), storage);
      Future<double> sizeAfter(num v) async {
        await facade.apply({'expressionEmojiBurstSize': v});
        return storage.expressionSettings.expressionEmojiBurstSize;
      }

      expect(await sizeAfter(31), 32.0);
      expect(await sizeAfter(100), 60.0);
      expect(await sizeAfter(3), 12.0);
    });

    test('a bad enum over HTTP answers 200, not 400', () async {
      final router = Router();
      WebVoiceRoutes(
        VoiceFacade(FakeTtsService(), FakeSttService(), storage),
        router,
      );
      final res = await router.call(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/api/voice/settings'),
          body: jsonEncode({'expressionMode': 'gpt', 'imageGenEnabled': false}),
        ),
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body['expressionMode'], 'llm');
      expect(body['imageGenEnabled'], isFalse);

      // No classifier on this host: the download verb says so.
      final onnx = await router.call(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/api/voice/onnx/download'),
        ),
      );
      expect(onnx.statusCode, 503);
    });

    test(
      'the ONNX block reads missing, then ready once the model is on disk',
      () {
        final facade = VoiceFacade(
          FakeTtsService(),
          FakeSttService(),
          storage,
          expressions: ExpressionClassifierService(storage),
        );
        expect(facade.status()['onnxModel'], {
          'state': 'missing',
          'progress': null,
          'failed': false,
        });
        final dir = Directory(
          p.join(storage.rootPath!, 'models', 'emotion_classifier'),
        )..createSync(recursive: true);
        File(p.join(dir.path, 'model.onnx')).writeAsStringSync('x');
        addTearDown(() => dir.deleteSync(recursive: true));
        expect((facade.status()['onnxModel'] as Map)['state'], 'ready');
      },
    );

    test(
      'the photo helper reads absent, installed, and Remove frees it',
      () async {
        final root = Directory.systemTemp.createTempSync('fpai_photo_');
        addTearDown(() => root.deleteSync(recursive: true));
        final caption = LocalCaptionService.instance..configure(root.path);
        final router = Router();
        final facade = VoiceFacade(
          FakeTtsService(),
          FakeSttService(),
          storage,
          caption: caption,
        );
        WebVoiceRoutes(facade, router);
        Map photo() => facade.status()['photoHelper'] as Map;
        expect(photo()['state'], 'absent');
        expect(photo()['sizeLabel'], LocalCaptionService.downloadSizeLabel);

        // Sparse files of the advertised sizes stand in for the download.
        final dir = Directory(p.join(root.path, 'caption_model'))
          ..createSync(recursive: true);
        for (final entry in const {
          'vision_encoder_quantized.onnx': 98600000,
          'embed_tokens_int8.onnx': 47300000,
          'decoder_model_merged_int8.onnx': 365000000,
          'tokenizer.json': 3500000,
        }.entries) {
          final raf = File(
            p.join(dir.path, entry.key),
          ).openSync(mode: FileMode.write);
          raf.truncateSync(entry.value);
          raf.closeSync();
        }
        expect(photo()['state'], 'installed');

        final res = await router.call(
          shelf.Request(
            'POST',
            Uri.parse('http://localhost/api/voice/photo/remove'),
          ),
        );
        expect(res.statusCode, 200);
        final body = jsonDecode(await res.readAsString()) as Map;
        expect((body['photoHelper'] as Map)['state'], 'absent');
        expect(dir.existsSync(), isFalse);
      },
    );
  });
}
