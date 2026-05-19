// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/services/storage_service.dart';

void setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getApplicationDocumentsDirectory') {
      final tmp = Directory.systemTemp.createTempSync('fpai_storage_');
      return tmp.path;
    }
    return null;
  });
}

Future<StorageService> createStorageService([
  Map<String, Object> initialValues = const {},
]) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final service = StorageService();
  await service.initialized;
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  group('StorageService — characterAvatarDir', () {
    test('returns correct avatars path for a character name', () async {
      final svc = await createStorageService();
      final dir = svc.characterAvatarDir('Carly');
      expect(dir.path.contains('Carly'), isTrue);
      expect(dir.path.contains('avatars'), isTrue);
    });

    test('sanitizes special characters from character name', () async {
      final svc = await createStorageService();
      final dir = svc.characterAvatarDir('Carly @#\$%');
      expect(dir.path.contains('@'), isFalse);
      expect(dir.path.contains('#'), isFalse);
      expect(dir.path.contains('%'), isFalse);
    });

    test('handles spaces in character name', () async {
      final svc = await createStorageService();
      final dir = svc.characterAvatarDir('Maggie the Cat');
      expect(dir.path.contains('Maggie_the_Cat'), isTrue);
    });

    test('handles hyphens in character name', () async {
      final svc = await createStorageService();
      final dir = svc.characterAvatarDir('Dark-Signer Carly');
      expect(dir.path.contains('Dark-Signer'), isTrue);
    });

    test('handles empty character name', () async {
      final svc = await createStorageService();
      final dir = svc.characterAvatarDir('');
      expect(dir.path.contains('avatars'), isTrue);
    });
  });

  group('StorageService — resolveCharacterImage', () {
    test('resolves basename to full path', () async {
      final svc = await createStorageService();
      final file = svc.resolveCharacterImage('Carly.png');
      expect(file.path.contains('Carly.png'), isTrue);
    });

    test('returns absolute path unchanged', () async {
      final svc = await createStorageService();
      final file = svc.resolveCharacterImage('/absolute/path/to/image.png');
      expect(file.path, '/absolute/path/to/image.png');
    });

    test('resolves subdirectory path correctly', () async {
      final svc = await createStorageService();
      final file = svc.resolveCharacterImage('Carly/avatars/avatar_1.png');
      expect(file.path.contains('Carly/avatars/avatar_1.png'), isTrue);
    });
  });

  group('StorageService — charactersDir', () {
    test('returns characters directory path', () async {
      final svc = await createStorageService();
      expect(svc.charactersDir.path.contains('KoboldManager'), isTrue);
      expect(svc.charactersDir.path.contains('Characters'), isTrue);
    });
  });
}
