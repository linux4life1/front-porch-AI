// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Image Studio remote chips write the Studio-scoped URL only.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/image_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });

  late StorageService storage;
  late ImageFacade facade;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    facade = ImageFacade(ImageGenService(storage), storage);
  });

  test('remoteApiUrl on image config does not rewrite chat\'s mouth', () async {
    final chatBefore = storage.backendSettings.remoteApiUrl;
    await facade.updateConfig({'remoteApiUrl': kNanoGptApiV1});
    expect(storage.imageGenSettings.imageRemoteApiUrl, kNanoGptApiV1);
    expect(storage.backendSettings.remoteApiUrl, chatBefore);
    expect(facade.config()['remoteApiUrl'], kNanoGptApiV1);
    expect(facade.config()['imageRemoteHost'], 'nano');
  });

  test(
    'imageRemoteHost chip parks on Studio URL and lists vault keys',
    () async {
      await storage.backendSettings.setRemoteApiKeyFor(
        kNanoGptApiV1,
        'sk-nano',
      );
      await facade.updateConfig({'imageRemoteHost': 'nano'});
      expect(storage.imageGenSettings.imageRemoteApiUrl, kNanoGptApiV1);
      expect(storage.backendSettings.remoteApiUrl, isNot(kNanoGptApiV1));
      final hosts = facade.config()['imageRemoteHosts'] as List;
      expect(
        hosts.cast<Map>().singleWhere((h) => h['id'] == 'nano')['hasKey'],
        isTrue,
      );
      expect(
        hosts.cast<Map>().singleWhere((h) => h['id'] == 'openrouter')['hasKey'],
        isFalse,
      );
    },
  );

  test('remoteModels labels include Pro / paid', () async {
    await storage.backendSettings.setRemoteApiKeyFor(kNanoGptApiV1, 'sk-nano');
    await facade.updateConfig({'imageRemoteHost': 'nano'});
    final body = await facade.remoteModels();
    final models = (body['models'] as List).cast<Map>();
    expect(models, isNotEmpty);
    expect(models.any((m) => '${m['label']}'.contains('· Pro')), isTrue);
    expect(models.any((m) => '${m['label']}'.contains('· paid')), isTrue);
    expect(models.first['isPaid'], isFalse);
  });
}
