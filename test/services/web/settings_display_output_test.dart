// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/settings_facade.dart';

import '../../golden/support/fakes.dart';

class _Llm extends FakeLLMProvider {
  final OpenRouterService remote = OpenRouterService();
  @override
  OpenRouterService get openRouterService => remote;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_disp_').path;
        }
        return null;
      });

  test('read/update round-trips Display Output settings', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    final facade = SettingsFacade(storage, _Llm());

    await facade.update({
      'displayBufferEnabled': true,
      'targetDisplayTps': 42,
      'bufferDurationSeconds': 6,
    });

    final out = facade.read();
    expect(out['displayBufferEnabled'], isTrue);
    expect(out['targetDisplayTps'], closeTo(42.0, 0.001));
    expect(out['bufferDurationSeconds'], closeTo(6.0, 0.001));
    expect(storage.uiSettings.displayBufferEnabled, isTrue);
    expect(storage.uiSettings.targetDisplayTps, closeTo(42.0, 0.001));
    expect(storage.uiSettings.bufferDurationSeconds, closeTo(6.0, 0.001));
  });
}
