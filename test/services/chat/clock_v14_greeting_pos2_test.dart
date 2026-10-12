// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The real v1.4 upgrade fixture: pos 2 keeps its own 09:30 reply snap on
// open and on a later paged-window open, never a later tail stamp.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_clk_fu_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('v1.4 pos 2 greetingClock', () {
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

    Future<void> bootFixture() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      final dir = Directory.systemTemp.createTempSync('fpai_fu_v14_');
      final work = File('${dir.path}/library.db');
      File('test/fixtures/v14_upgrade/library.db').copySync(work.path);
      db = AppDatabase.forReunification(work);
      await db!.ensureSchemaIsRepaired();
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
            ..setCharacterRepository(repo!);
      await storage!.initialized;
      await repo!.loadCharacters();
    }

    tearDown(() => disposeChatThenCloseDb(chat, db));

    test('Clocked pos 2 is 09:30, not later 18:00', () async {
      await bootFixture();
      final card = repo!.characters.firstWhere((c) => c.name == 'Clocked');
      await chat!.setActiveCharacter(card);
      await chat!.loadSession('1790314133694');
      await drain();
      final pos2 = chat!.messages[2];
      expect(
        slotClockAfter(pos2.activeMetadata) ?? slotClockAfter(pos2.metadata),
        DateTime.utc(2026, 9, 25, 9, 30),
        reason: 'v14 Clocked pos 2 must not land on 09-28 18:00',
      );
    });

    test('HostOn pos 2 is 09:30, not 10:00', () async {
      await bootFixture();
      final card = repo!.characters.firstWhere((c) => c.name == 'HostOn');
      await chat!.setActiveCharacter(card);
      await chat!.loadSession('1790314131886');
      await drain();
      final pos2 = chat!.messages[2];
      expect(
        slotClockAfter(pos2.activeMetadata) ?? slotClockAfter(pos2.metadata),
        DateTime.utc(2026, 9, 25, 9, 30),
        reason: 'v14 HostOn pos 2 must not land on 10:00',
      );
    });

    test('paged-window Clocked pos 2 stays 09:30', () async {
      await bootFixture();
      final card = repo!.characters.firstWhere((c) => c.name == 'Clocked');
      await chat!.setActiveCharacter(card);
      await chat!.loadSession('1790314133694');
      await drain();
      final sid = chat!.currentSessionId!;
      final n = chat!.messages.length;
      for (var i = 0; i < 30; i++) {
        await db!.insertMessage(
          MessagesCompanion.insert(
            id: 'pad$i',
            sessionId: sid,
            position: n + i,
            sender: i.isEven ? 'You' : 'Clocked',
            isUser: i.isEven,
            swipes: Value(jsonEncode(['pad $i'])),
            metadata: Value(
              i.isEven
                  ? null
                  : jsonEncode({
                      'story_clock_before': '2026-09-28T18:00:00.000Z',
                      'story_clock_after': '2026-09-28T18:00:00.000Z',
                    }),
            ),
          ),
        );
      }
      await chat!.reloadCurrentSession();
      await drain();
      expect(chat!.messages.length, greaterThan(24));
      final pos2 = chat!.messages[2];
      expect(
        slotClockAfter(pos2.activeMetadata) ?? slotClockAfter(pos2.metadata),
        DateTime.utc(2026, 9, 25, 9, 30),
        reason: 'window guess must not move archive pos 2 to tail 18:00',
      );
    });
  });
}
