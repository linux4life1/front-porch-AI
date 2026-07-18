// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/voice_facade.dart';

import '../../golden/support/fakes.dart';

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

  group('VoiceFacade', () {
    late StorageService storage;
    late VoiceFacade facade;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      facade = VoiceFacade(FakeTtsService(), FakeSttService(), storage);
    });

    test('status reflects storage flags + STT availability', () {
      final s = facade.status();
      // Defaults: TTS/STT off, so nothing is usable yet.
      expect(s['ttsEnabled'], isFalse);
      expect(s['sttEnabled'], isFalse);
      expect(s['sttAvailable'], isFalse);
      expect(s.containsKey('ttsEngine'), isTrue);
    });

    test('speak is a no-op when TTS is disabled', () async {
      expect(await facade.speak('hello'), isNull);
    });

    test('transcribe is a no-op when STT is unavailable or body empty', () async {
      expect(await facade.transcribe(const [1, 2, 3]), isNull); // STT off
      expect(await facade.transcribe(const []), isNull); // empty body
    });
  });
}
