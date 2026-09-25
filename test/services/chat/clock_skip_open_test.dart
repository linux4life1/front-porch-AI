// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// S-h: opening a chat whose greeting has no snap must not undo a
// chip-less time-skip whose snap is older than its after.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show slotClockAfter;
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_skip_open_').path;
        }
        return null;
      });
}

const _start = '2026-06-28';
const _snapIso = '2026-06-28T09:00:00.000Z';
const _skipIso = '2026-06-30T16:00:00.000Z';
final _skip = DateTime.utc(2026, 6, 30, 16, 0);

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SkipOpen';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  ChatService? chat;

  Future<void> drain() async {
    for (
      var i = 0;
      i < 400 && (chat!.isGenerating || chat!.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'open does not undo a chip-less skip whose snap is older than after',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'needs_sim_default': true,
        'passage_of_time_default': true,
      });
      db = AppDatabase.forTesting();
      final storage = StorageService();
      final repo = CharacterRepository(db!, storage);
      chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db!),
              storage,
              WorldRepository(storage, db!),
            )
            ..setDatabase(db!)
            ..setCharacterRepository(repo)
            ..testLlmServiceOverride = _SilentLlm();
      await storage.initialized;
      final nia = CharacterCard(
        name: 'Nia',
        firstMessage: 'Evening.',
        imagePath: '/tmp/nia-skip-open.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
        ),
      );
      await repo.addCharacter(nia);
      await chat!.setActiveCharacter(nia);
      await drain();
      await chat!.flushPendingSaves();
      final sid = chat!.currentSessionId!;
      await db!.deleteMessagesForSession(sid);
      final rows = [
        {'sender': 'Nia', 'user': false, 'text': 'Evening.', 'meta': null},
        {'sender': 'You', 'user': true, 'text': '(ooc: skip to afternoon)'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'The light has moved.',
          'meta': {
            'time_skip_to': 'Tue, Jun 30 · 4:00 PM',
            'story_clock_before': '2026-06-30T14:00:00.000Z',
            'story_clock_after': _skipIso,
            'realism_state': {'storyClock': _snapIso, 'storyStartDate': _start},
          },
        },
      ];
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final meta = r['meta'] as Map<String, dynamic>?;
        await db!.insertMessage(
          MessagesCompanion.insert(
            id: 'so$i',
            sessionId: sid,
            position: i,
            sender: r['sender'] as String,
            isUser: r['user'] as bool,
            swipes: Value(jsonEncode([r['text'] as String])),
            metadata: Value(meta == null ? null : jsonEncode(meta)),
          ),
        );
      }
      await db!.patchSession(
        SessionsCompanion(
          id: Value(sid),
          passageOfTimeEnabled: const Value(true),
          passageOfTimeGateMigrated: const Value(true),
          storyClock: const Value(_skipIso),
          storyStartDate: const Value(_start),
          timeOfDay: const Value('afternoon'),
          dayCount: const Value(3),
        ),
      );
      await chat!.reloadCurrentSession();
      await drain();

      final tip = chat!.messages.lastWhere((m) => !m.isUser);
      expect(slotClockAfter(tip.activeMetadata), _skip);
      expect(chat!.timeService.clock, _skip);
      expect(tip.activeMetadata?['story_clock_after'], _skipIso);
    },
  );
}
