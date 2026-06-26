// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';

import '../../golden/support/fakes.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory') {
      return Directory.systemTemp.createTempSync('fpai_test_').path;
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('ChatToolsFacade', () {
    late StorageService storage;
    late ChatToolsFacade facade;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      // Hub is null: a unit test never broadcasts. The fake seeds chaos/nsfw/
      // time/needs deterministically (evening, day 3) and exposes empty
      // objectives, so the read snapshot is fully exercisable.
      facade = ChatToolsFacade(FakeChatService(), storage, null);
    });

    test('state() mirrors the desktop sidebar sections', () {
      final s = facade.state();
      expect(s['realismEnabled'], isTrue);
      expect((s['time'] as Map)['timeOfDay'], 'evening');
      expect((s['time'] as Map)['dayCount'], 3);
      expect((s['objectives'] as Map)['primary'], isNull);
      expect((s['objectives'] as Map)['secondary'], isEmpty);
      // Memory + summary blocks are present with defaults from StorageService.
      expect((s['memory'] as Map).containsKey('ragEnabled'), isTrue);
      expect((s['summary'] as Map).containsKey('interval'), isTrue);
    });

    test('applySettings only writes keys that are present', () async {
      final beforeWindow = storage.ragWindowSize;
      await facade.applySettings({
        'ragEnabled': true,
        'summaryInterval': 9,
        'unknownKey': 'ignored',
      });
      expect(storage.ragEnabled, isTrue);
      expect(storage.summaryInterval, 9);
      // A setting we never passed must stay untouched.
      expect(storage.ragWindowSize, beforeWindow);
    });

    test('applySettings ignores wrong-typed values', () async {
      final before = storage.summaryMaxWords;
      await facade.applySettings({'summaryMaxWords': 'not-an-int'});
      expect(storage.summaryMaxWords, before);
    });

    test('objective task ops return false when the id is unknown', () async {
      expect(await facade.generateTasks('missing'), isFalse);
      expect(await facade.toggleTask('missing', 0), isFalse);
      expect(await facade.clearObjective('missing'), isFalse);
    });
  });
}
