// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/image_facade.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory') {
      return Directory.systemTemp.createTempSync('fpai_docs_').path;
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('ImageFacade config', () {
    late StorageService storage;
    late ImageFacade facade;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      facade = ImageFacade(ImageGenService(storage), storage);
    });

    test('config reflects updates; api key write-only', () async {
      expect(facade.config()['backend'], 'remote'); // default

      await facade.updateConfig({
        'backend': 'a1111',
        'size': '512x512',
        'steps': 30,
        'localUrl': 'http://127.0.0.1:7860',
        'remoteApiUrl': 'https://api.example/v1',
      });

      final c = facade.config();
      expect(c['backend'], 'a1111');
      expect(c['size'], '512x512');
      expect(c['steps'], 30);
      expect(c['localUrl'], 'http://127.0.0.1:7860');
      expect(c['remoteApiUrl'], 'https://api.example/v1');
      // Key never echoed back, only its presence.
      expect(c.containsKey('apiKey'), isFalse);
      expect(c['hasApiKey'], isFalse);

      await facade.updateConfig({'apiKey': 'sk-secret'});
      expect(facade.config()['hasApiKey'], isTrue);
    });

    test('generate rejects an empty prompt', () async {
      expect(await facade.generate({'prompt': '   '}), isNull);
    });

    test('savedImageFile resolves real files and blocks traversal', () async {
      final root = Directory.systemTemp.createTempSync('fpai_img_root_');
      await storage.setRootPath(root.path);
      final imagesDir = Directory('${root.path}/KoboldManager/images')
        ..createSync(recursive: true);
      File('${imagesDir.path}/img_1.png').writeAsBytesSync([1, 2, 3]);

      expect(facade.savedImageFile('img_1.png'), isNotNull);
      expect(facade.savedImageFile('missing.png'), isNull);
      // Path-traversal / absolute / nested names are rejected outright.
      expect(facade.savedImageFile('../secret.png'), isNull);
      expect(facade.savedImageFile('sub/img_1.png'), isNull);
      expect(facade.savedImageFile(''), isNull);
    });
  });
}
