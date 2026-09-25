// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// B4: import applies the head clock. Fork after reload must not inherit
// the parent's live trust when the tip has no realism_state.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/fpchat_codec.dart';
import 'package:front_porch_ai/services/chat/fpchat_format.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/character_id.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_imp_fork_').path;
        }
        return null;
      });
}

CharacterCard _misty() => CharacterCard(
  name: 'Misty',
  frontPorchExtensions: FrontPorchExtensions(
    realismEnabled: true,
    shortTermBond: 45,
    longTermBond: 10,
    trustLevel: 45,
  ),
)..dbId = 'char-misty';

Uint8List _stBytes() {
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'messages': [
          {'name': 'User', 'is_user': true, 'mes': 'hello from ST'},
          {'name': 'Misty', 'is_user': false, 'mes': 'hi back'},
        ],
      }),
    ),
  );
}

Uint8List _livedInFpchat({required bool realismOn}) {
  final bot = ChatMessage(
    text: 'Still here.',
    sender: 'Misty',
    isUser: false,
    metadata: {
      if (realismOn)
        'realism_state': {
          'trustLevel': 11,
          'affectionScore': 42,
          'timeOfDay': 'evening',
          'dayCount': 4,
          'storyClock': '2020-01-04T19:00:00.000Z',
          'storyStartDate': '2020-01-01',
        },
    },
  );
  final root = {
    'format': kFpchatFormatId,
    'version': kFpchatFormatVersion,
    'messages': [
      {'name': 'User', 'is_user': true, 'mes': 'hey'},
      {'name': 'Misty', 'is_user': false, 'mes': 'Still here.'},
    ],
    'fpai': {
      'version': 1,
      'kind': 'timeline',
      'stamp_version': kFpchatStampVersion,
      'character': {'name': 'Misty', 'stable_group_id': _misty().stableGroupId},
      'session': {
        'realism_enabled': realismOn,
        'needs_sim_enabled': false,
        'time_of_day': 'evening',
        'day_count': 4,
        'story_clock': '2020-01-04T19:00:00.000Z',
        'story_start_date': '2020-01-01',
        'trust_level': 11,
        'affection_score': 42,
        'summary': '',
        'summary_last_index': 2,
      },
      'messages_extra': [messagesExtraEntry(1, bot)],
    },
  };
  return encodeFpchatZip(chatJson: root);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late UserPersonaService personas;
  late ChatService chat;
  late String personaId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    personas = UserPersonaService(db);
    chat = ChatService(
      KoboldService(storage),
      personas,
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    personaId = personas.persona.id;
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  Future<void> drain() async {
    for (var i = 0; i < 80 && (chat.isGenerating || chat.isSettlingTurn); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('B4: lived-in .fpchat import keeps the head clock', () async {
    await chat.startFreshChatWith(character: _misty(), personaId: personaId);
    final outcome = await chat.importChatPackage(
      _livedInFpchat(realismOn: true),
    );
    expect(outcome.fullRestore, isTrue);
    expect(chat.timeService.dayCount, 4);
    expect(chat.timeService.clock, DateTime.utc(2020, 1, 4, 19, 0));
  });

  test('B4: Realism-off .fpchat import keeps the head clock', () async {
    await chat.startFreshChatWith(character: _misty(), personaId: personaId);
    final outcome = await chat.importChatPackage(
      _livedInFpchat(realismOn: false),
    );
    expect(outcome.fullRestore, isTrue);
    expect(chat.timeService.dayCount, 4);
    expect(chat.timeService.clock, DateTime.utc(2020, 1, 4, 19, 0));
  });

  test(
    'reload-then-fork of stamp-less ST does not inherit parent trust',
    () async {
      await chat.startFreshChatWith(character: _misty(), personaId: personaId);
      await chat.importChatPackage(_stBytes());
      chat.relationshipService.loadScalars(
        affectionScore: 200,
        longTermScore: 0,
        trustLevel: 200,
      );
      await chat.flushPendingSaves();
      await chat.reloadCurrentSession();
      await drain();
      chat.relationshipService.loadScalars(
        affectionScore: 200,
        longTermScore: 0,
        trustLevel: 200,
      );
      await chat.forkFromMessage(1);
      expect(
        chat.relationshipService.trustLevel,
        45,
        reason: 'clock stamps must not stop the realism walk at a bare pair',
      );
      expect(chat.relationshipService.affectionScore, 45);
    },
  );
}
