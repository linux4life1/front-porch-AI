// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone draws the Needs bars from the realism feed, so the feed sends
// them while Needs run and only then: Realism AND this chat's Needs switch
// AND Porch Life Needs, read live. It used to send them on the chat's
// stored switch alone, so with Realism or Porch Life Needs off the phone
// showed frozen bars that read as live (maintainer, 2026-10-08). A real
// chat, so the Porch Life switch is the real setting, flipped mid-chat.
// The desktop sidebar: test/ui/chat_components/needs_bars_follow_gate_test.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_realism_read.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/services/chat/refractory.dart' show Refractory;
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/character_state.dart'
    show BondBars;
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_needs_feed_').path;
        }
        return null;
      });
}

const _bars = {
  'hunger': 80,
  'bladder': 80,
  'energy': 80,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  ChatService? chat;

  Future<void> boot() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    final repo = CharacterRepository(db!, storage!);
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo);
    await storage!.initialized;
    final carmen = CharacterCard(
      name: 'Carmen',
      firstMessage: 'Evening.',
      imagePath: '/tmp/carmen-needs-feed.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
      ),
    );
    await repo.addCharacter(carmen);
    await chat!.setActiveCharacter(carmen);
    await chat!.setRealismEnabled(true);
    await chat!.setNeedsSimEnabled(true);
    chat!.needsSimulation.restoreFromSnapshot({'vector': _bars});
  }

  bool feedSendsBars() {
    final snap = ChatRealismRead(chat!).snapshot();
    final sent = (snap['needs'] as Map).isNotEmpty;
    expect(snap['needsEnabled'], sent);
    return sent;
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('all three on: the feed sends the bars', () async {
    await boot();
    expect(feedSendsBars(), isTrue);
  });

  test(
    'Porch Life Needs off: no bars, on again: bars, Realism stays',
    () async {
      await boot();
      await storage!.realismSettings.setNeedsSimDefault(false);
      expect(feedSendsBars(), isFalse);
      expect(
        chat!.realismEnabled,
        isTrue,
        reason: 'Realism does not need Needs',
      );
      expect(
        chat!.needsSimEnabled,
        isTrue,
        reason: 'the chat keeps its switch',
      );
      expect(chat!.needsSimulation.vector, _bars, reason: 'hidden, not erased');

      await storage!.realismSettings.setNeedsSimDefault(true);
      expect(feedSendsBars(), isTrue);
    },
  );

  test("this chat's Needs off with Realism on: no bars", () async {
    await boot();
    await chat!.setNeedsSimEnabled(false);
    expect(chat!.realismEnabled, isTrue);
    expect(feedSendsBars(), isFalse);
  });

  test('Realism off with both Needs switches on: no bars', () async {
    await boot();
    await chat!.setRealismEnabled(false);
    expect(chat!.needsSimEnabled, isTrue);
    expect(feedSendsBars(), isFalse);
  });

  // The phone's Lust line follows Afterglow in this chat, as the desktop's
  // Lust bar does: Porch Life (with 18+) allows it and the chat's switch is on.
  test("the Lust line's flag follows Porch Life and this chat's own "
      'switch', () async {
    await boot();
    bool lustOn() => ChatRealismRead(chat!).snapshot()['lustOn'] as bool;
    expect(lustOn(), isFalse, reason: 'Porch Life Afterglow is off');

    await storage!.realismSettings.setAdultThemesEnabled(true);
    await storage!.realismSettings.setNsfwCooldownDefault(true);
    expect(lustOn(), isTrue, reason: "the card started the chat's switch on");

    await chat!.setAfterglowEnabled(false);
    expect(lustOn(), isFalse, reason: "this chat's switch is off");
  });

  // The phone's line under Lust is the desktop's recovery chip, in its words,
  // while Afterglow runs. The group twin: needs_bars_group_gate_test.dart.
  test("the recovery line under Lust follows Afterglow, in the desktop's "
      'words', () async {
    await boot();
    await storage!.realismSettings.setAdultThemesEnabled(true);
    await storage!.realismSettings.setNsfwCooldownDefault(true);
    chat!.nsfwService.setRefractory(Refractory.fromMinutes(30));
    Object? line() => ChatRealismRead(chat!).snapshot()['refractoryLabel'];
    expect(line(), startsWith('Refractory: '));
    expect(line(), chat!.nsfwService.refractoryWords.chip);

    await storage!.realismSettings.setNsfwCooldownDefault(false);
    expect(line(), isEmpty, reason: 'Porch Life Afterglow off');
  });

  // Off hides Lust and recovery and keeps them (zeroing them was a bug): the
  // desktop's Lust bar, the phone's insight feed and its chat tools show
  // neither while this chat's switch is off, and both where they were once
  // it is back on.
  testWidgets("this chat's Afterglow off hides Lust and recovery on the "
      "desktop and in the phone's feeds; on shows them where they were", (
    tester,
  ) async {
    await tester.runAsync(boot);
    final c = chat!;
    try {
      await tester.runAsync(() async {
        await storage!.realismSettings.setAdultThemesEnabled(true);
        await storage!.realismSettings.setNsfwCooldownDefault(true);
      });
      c.nsfwService.setArousalLevel(60);
      c.nsfwService.setRefractory(Refractory.fromMinutes(30));
      final chip = c.nsfwService.refractoryWords.chip;
      Map<String, dynamic> feed() => ChatRealismRead(c).snapshot();
      Map<dynamic, dynamic> tools() =>
          ChatToolsFacade(c, storage!, null).state()['nsfw'] as Map;
      Future<void> desktop() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(width: 340, child: BondBars(chat: c)),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await desktop();
      expect(find.text('Lust: Intense'), findsOneWidget);

      await tester.runAsync(() => c.setAfterglowEnabled(false));
      await desktop();
      expect(find.textContaining('Lust:'), findsNothing, reason: 'desktop');
      expect(find.text(chip), findsNothing);
      expect(feed()['lustOn'], isFalse);
      expect((feed()['arousal'] as Map)['level'], 0, reason: 'insight feed');
      expect(feed()['refractoryLabel'], isEmpty);
      expect(tools()['cooldownEnabled'], isFalse);
      expect(tools()['arousalLevel'], 0, reason: 'chat tools');
      expect(tools()['refractoryLabel'], isEmpty);
      expect(c.nsfwService.arousalLevel, 60, reason: 'hidden, kept');

      await tester.runAsync(() => c.setAfterglowEnabled(true));
      await desktop();
      expect(find.text('Lust: Intense'), findsOneWidget);
      expect(find.text(chip), findsOneWidget);
      expect((feed()['arousal'] as Map)['level'], 60);
      expect(feed()['refractoryLabel'], chip);
      expect(tools()['arousalLevel'], 60);
      expect(tools()['refractoryLabel'], chip);
    } finally {
      final d = db;
      chat = null;
      db = null;
      await tester.runAsync(() => disposeChatThenCloseDb(c, d));
    }
  });
}
