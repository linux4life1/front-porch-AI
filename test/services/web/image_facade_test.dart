// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
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

  group('ImageFacade Recent shelf', () {
    late StorageService storage;
    late ImageFacade facade;
    late Directory root;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      facade = ImageFacade(ImageGenService(storage), storage);
      root = Directory.systemTemp.createTempSync('fpai_recent_root_');
      await storage.setRootPath(root.path);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('the phone reads the pictures the desktop Studio kept', () async {
      final entry = await rememberStudioResult(
        storage,
        Uint8List.fromList([137, 80, 78, 71, 1]),
        prompt: 'porch at dusk',
        edit: false,
      );
      final view = await facade.recent.view();
      final entries = view['entries'] as List;
      expect((entries.single as Map)['name'], entry!.name);
      expect((entries.single as Map)['prompt'], 'porch at dusk');
      expect((entries.single as Map)['url'], '/api/image/saved/${entry.name}');
      expect(facade.savedImageFile(entry.name)?.path, entry.path);
    });

    test('a chat insert keeps its picture after the shelf trims it', () async {
      await facade.recent.setLimit(kStudioRecentOff);
      final first = await facade.recent.remember(
        Uint8List.fromList([137, 80, 78, 71, 1]),
        prompt: 'first',
        edit: false,
      );
      final chatFile = facade.chatImageFile(first!.name);
      expect(chatFile, isNotNull);
      expect(
        p.dirname(chatFile!.path),
        p.join(root.path, 'KoboldManager', 'images'),
      );
      await facade.recent.remember(
        Uint8List.fromList([137, 80, 78, 71, 2]),
        prompt: 'second',
        edit: true,
      );
      expect(File(first.path).existsSync(), isFalse);
      expect(chatFile.readAsBytesSync(), [137, 80, 78, 71, 1]);
      expect(facade.savedImageFile(first.name)?.path, chatFile.path);
    });

    test('the phone can only set a limit the shelf offers', () async {
      expect(await facade.recent.setLimit(9), isFalse);
      expect(await facade.recent.setLimit(200), isTrue);
      expect((await facade.recent.view())['limit'], 200);
      expect(storage.imageGenSettings.studioRecentLimit, 200);
    });
  });
}
