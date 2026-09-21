// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web Voice & Media enable: VoiceFacade.apply writes tts/stt flags so a
// remote user can turn engines on without the desktop tab.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/voice_facade.dart';

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
}
