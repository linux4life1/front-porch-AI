// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A saved SuperGrok session must survive a relaunch. LLMProvider is built
// during the first frame, before StorageService has bound its prefs, so the
// session read has to wait for storage init — this drives that real order.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/services/xai/xai.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a saved session is signed in after boot', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? Directory.systemTemp.createTempSync('fpai_grok_boot_').path
              : null,
        );
    final key = BackendSettings().k('xai_supergrok_session');
    final saved = XaiTokens(
      accessToken: 'boot-access',
      refreshToken: 'boot-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      email: 'porch@example.com',
    );
    SharedPreferences.setMockInitialValues({key: saved.encode()});

    // Same order as main.providers.dart: provider built before init lands.
    final storage = StorageService();
    final llm = LLMProvider(
      KoboldService(storage),
      OpenRouterService(),
      storage,
      BackendManager(storage),
    );
    await storage.initialized;
    await pumpEventQueue();

    expect(llm.superGrok.isSignedIn, isTrue);
    expect(llm.superGrok.email, 'porch@example.com');
    expect(
      storage.backendSettings.bearerOverlay?.call('https://api.x.ai/v1'),
      'boot-access',
    );
  });
}
