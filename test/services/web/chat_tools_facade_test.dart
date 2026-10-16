// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';

import '../../golden/support/fakes.dart';

/// A fake with one set-aside character goal and one card goal from before
/// v58 (no origin column yet), for the web's objective JSON.
class _GoalsChat extends FakeChatService {
  _GoalsChat() : super(activeCharacter: CharacterCard(name: 'Vera'));

  static Objective _o(String id, {bool primary = false, String? status}) =>
      Objective(
        id: id,
        characterId: 'vera',
        objective: 'goal $id',
        tasks: '[]',
        active: true,
        isPrimary: primary,
        checkFrequency: 3,
        injectionDepth: 4,
        servedAmbition: primary ? null : 'open a bakery',
        createdAt: DateTime(2026),
        origin: primary ? null : 'character',
        status: status,
      );

  @override
  List<Objective> getObjectivesForGroupCharacter(CharacterCard character) => [
    _o('main', primary: true),
    _o('side', status: 'dormant'),
  ];
}

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
      // Memory + recap blocks are present with defaults from StorageService.
      expect((s['memory'] as Map).containsKey('ragEnabled'), isTrue);
      expect((s['memory'] as Map).containsKey('journalEnabled'), isTrue);
      expect((s['summary'] as Map).containsKey('text'), isTrue);
    });

    test('applySettings only writes keys that are present', () async {
      final beforeWindow = storage.memorySettings.ragWindowSize;
      await facade.applySettings({
        'ragEnabled': true,
        'journalInterval': 9,
        'unknownKey': 'ignored',
      });
      expect(storage.memorySettings.ragEnabled, isTrue);
      expect(storage.memorySettings.journalInterval, 9);
      // A setting we never passed must stay untouched.
      expect(storage.memorySettings.ragWindowSize, beforeWindow);
    });

    test('applySettings ignores wrong-typed values', () async {
      final before = storage.memorySettings.journalInterval;
      await facade.applySettings({'journalInterval': 'not-an-int'});
      expect(storage.memorySettings.journalInterval, before);
    });

    // 2026-10-16, objectives that keep up: the web's goals panel shows a
    // set-aside goal dimmed and needs to know who the goal is from.
    test('objective JSON carries dormant and origin for the web', () {
      final f = ChatToolsFacade(_GoalsChat(), storage, null);
      final obj = f.state()['objectives'] as Map;
      final primary = obj['primary'] as Map;
      final side = (obj['secondary'] as List).single as Map;
      expect(primary['dormant'], isFalse);
      expect(primary['origin'], 'user', reason: 'pre-v58, no served ambition');
      expect(side['dormant'], isTrue);
      expect(side['origin'], 'character');
    });

    test('objective task ops return false when the id is unknown', () async {
      expect(await facade.generateTasks('missing'), isFalse);
      expect(await facade.toggleTask('missing', 0), isFalse);
      expect(await facade.clearObjective('missing'), isFalse);
    });
  });
}
