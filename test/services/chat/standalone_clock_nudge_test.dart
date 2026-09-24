// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Clock mutators (nudge / set clock / set start date) must gate on Passage
// of Time — the only story-clock driver — not Realism, Needs, or the
// leftover standalone pref.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';

import '../../golden/support/fakes.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_clocknudge_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('StoryClock.isRunning keys off Passage of Time only', () {
    expect(StoryClock.isRunning(passageOfTimeEnabled: true), isTrue);
    expect(StoryClock.isRunning(passageOfTimeEnabled: false), isFalse);
  });

  group('ChatService nudge', () {
    late AppDatabase db;
    late StorageService storage;
    late ChatService chat;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': false,
        'passage_of_time_default': true,
      });
      db = AppDatabase.forTesting();
      storage = StorageService();
      chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(CharacterRepository(db, storage));
      await storage.initialized;
      final card = CharacterCard(
        name: 'Nia',
        firstMessage: 'Hey.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          passageOfTimeEnabled: true,
        ),
      )..dbId = 'char-clock-1';
      await chat.setActiveCharacter(card);
      await chat.setRealismEnabled(false);
      await chat.setNeedsSimEnabled(false);
    });

    tearDown(() async {
      chat.dispose();
      await db.close();
    });

    test('Realism off + Needs off + PoT on → nudge succeeds', () async {
      expect(chat.timeService.passageOfTimeEnabled, isTrue);
      final before = chat.timeService.clock;
      await chat.nudgeTimePeriod(1);
      expect(
        chat.timeService.clock.isAfter(before),
        isTrue,
        reason: 'PoT alone must be enough for the chevrons to work',
      );
    });

    test('PoT off → nudge is a no-op', () async {
      await chat.setPassageOfTimeEnabled(false);
      final before = chat.timeService.clock;
      await chat.nudgeTimePeriod(1);
      expect(chat.timeService.clock, before);
    });
  });

  testWidgets('PoT on → TimeStrip chevrons are present', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);

    final chat = FakeChatService(realismEnabled: false, needsSimEnabled: false);
    addTearDown(chat.dispose);
    expect(chat.timeService.passageOfTimeEnabled, isTrue);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(body: TimeStrip(chat: chat)),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
  });

  testWidgets('PoT off → TimeStrip chevrons are hidden', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);

    final chat = FakeChatService(realismEnabled: false, needsSimEnabled: false);
    addTearDown(chat.dispose);
    chat.timeService.setPassageOfTimeEnabled(false);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(body: TimeStrip(chat: chat)),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  test('web tools snapshot: PoT alone is a moving clock', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);
    await storage.initialized;
    await storage.realismSettings.setStandaloneClockEnabled(false);
    final fake = FakeChatService(realismEnabled: false, needsSimEnabled: false);
    addTearDown(fake.dispose);
    final facade = ChatToolsFacade(fake, storage, null);
    final time = facade.state()['time'] as Map;
    expect(
      time['clockRunning'],
      isTrue,
      reason: 'PoT on is a moving clock with Realism and Needs off',
    );
  });

  test('web tools snapshot: PoT off is a paused clock', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);
    await storage.initialized;
    final fake = FakeChatService(realismEnabled: true, needsSimEnabled: true);
    addTearDown(fake.dispose);
    fake.timeService.setPassageOfTimeEnabled(false);
    final facade = ChatToolsFacade(fake, storage, null);
    final time = facade.state()['time'] as Map;
    expect(time['clockRunning'], isFalse);
  });
}
