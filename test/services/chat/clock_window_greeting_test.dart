// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// B1: a chat longer than the 24-row open window must not guess
// greetingClock from the tail. v1.4 pos 2 keeps its own snap.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/message_clock.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_clk_win_').path;
        }
        return null;
      });
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SilentWindowClock';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;

  Future<void> drain() async {
    for (
      var i = 0;
      i < 400 && (chat!.isGenerating || chat!.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  tearDown(() async {
    chat?.dispose();
    await db?.close();
  });

  test(
    'B1: 30-row v1.4 open keeps pos 2 at the reply snap, not tail Day 4',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      db = AppDatabase.forTesting();
      storage = StorageService();
      repo = CharacterRepository(db!, storage!);
      chat =
          ChatService(
              KoboldService(storage!),
              UserPersonaService(db!),
              storage!,
              WorldRepository(storage!, db!),
            )
            ..setDatabase(db!)
            ..setCharacterRepository(repo!)
            ..testLlmServiceOverride = _SilentLlm();
      await storage!.initialized;
      final nia = CharacterCard(
        name: 'Nia',
        firstMessage: 'Hi.',
        imagePath: '/tmp/nia-window.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          passageOfTimeEnabled: true,
        ),
      );
      await repo!.addCharacter(nia);
      await chat!.setActiveCharacter(nia);
      await drain();
      await chat!.flushPendingSaves();
      final sid = chat!.currentSessionId!;
      await db!.deleteMessagesForSession(sid);

      const start = '2026-06-28';
      const replySnap = '2026-06-28T09:30:00.000Z';
      const tailSnap = '2026-07-01T18:00:00.000Z';
      final rows = <Map<String, Object?>>[
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Hi.',
          'meta': <String, dynamic>{},
        },
        {'sender': 'You', 'user': true, 'text': 'ok'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Later.',
          'meta': {
            'story_clock_before': '2026-06-28T09:00:00.000Z',
            'realism_state': {'storyClock': replySnap, 'storyStartDate': start},
          },
        },
      ];
      for (var i = 0; i < 28; i++) {
        rows.add({
          'sender': i.isEven ? 'You' : 'Nia',
          'user': i.isEven,
          'text': 'pad $i',
          if (!i.isEven)
            'meta': {
              'story_clock_before': tailSnap,
              'story_clock_after': tailSnap,
              'realism_state': {
                'storyClock': tailSnap,
                'storyStartDate': start,
              },
            },
        });
      }
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final meta = r['meta'] as Map<String, dynamic>?;
        await db!.insertMessage(
          MessagesCompanion.insert(
            id: 'w$i',
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
          storyClock: const Value(tailSnap),
          storyStartDate: const Value(start),
          timeOfDay: const Value('evening'),
          dayCount: const Value(4),
        ),
      );
      await chat!.reloadCurrentSession();
      await drain();

      expect(chat!.messages.length, greaterThan(24));
      final reply = chat!.messages[2];
      expect(
        slotClockAfter(reply.metadata),
        DateTime.utc(2026, 6, 28, 9, 30),
        reason: 'window guess must not freeze the v1.4 reply to tail Day 4',
      );
      expect(chat!.timeService.clock, DateTime.utc(2026, 7, 1, 18, 0));
    },
  );
}
