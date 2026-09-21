// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Switching OpenRouter ↔ Nano-GPT (and oMLX / Kobold) must blank the
// live picker. The previous host's model id is stale. Keys still restore.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _openRouter = kOpenRouterApiV1;
const _nanoGpt = kNanoGptApiV1;

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_test_').path;
        }
        return null;
      });
}

Future<StorageService> _storage([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final service = StorageService();
  await service.initialized;
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  test('switching URL clears the live model', () async {
    final storage = await _storage();
    await storage.backendSettings.setRemoteApiUrl(_openRouter);
    await storage.backendSettings.setRemoteModelName('x-ai/grok-4.6');
    await storage.backendSettings.setRemoteApiUrl(_nanoGpt);
    await storage.backendSettings.setRemoteModelName(
      'moonshotai/kimi-k2.6:thinking',
    );

    await storage.backendSettings.setRemoteApiUrl(_openRouter);
    expect(storage.backendSettings.remoteModelName, isEmpty);
    expect(
      storage.backendSettings.remoteApiModelFor(_openRouter),
      'x-ai/grok-4.6',
    );
    await storage.backendSettings.setRemoteApiUrl(_nanoGpt);
    expect(storage.backendSettings.remoteModelName, isEmpty);
    expect(
      storage.backendSettings.remoteApiModelFor(_nanoGpt),
      'moonshotai/kimi-k2.6:thinking',
    );
  });

  test(
    'oMLX backend clears the live model without overwriting the URL slot',
    () async {
      final storage = await _storage();
      await storage.backendSettings.setBackendType('openRouter');
      await storage.backendSettings.setRemoteApiUrl(_openRouter);
      await storage.backendSettings.setRemoteModelName('x-ai/grok-4.6');

      await storage.backendSettings.setBackendType('omlx');
      expect(storage.backendSettings.remoteModelName, isEmpty);
      await storage.backendSettings.setRemoteModelName('mlx-community/foo');
      expect(storage.backendSettings.remoteApiUrl, _openRouter);

      await storage.backendSettings.setBackendType('openRouter');
      expect(storage.backendSettings.remoteModelName, isEmpty);
      await storage.backendSettings.setBackendType('omlx');
      expect(storage.backendSettings.remoteModelName, isEmpty);
    },
  );
}
