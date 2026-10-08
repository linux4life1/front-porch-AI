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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_realism_read.dart';
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
}
