// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A send that lands while New chat or a chat load is still running is
// refused with the reason, as it is while a character opens. It used to run
// against a chat being torn down: New chat mints its id twice, so a /join in
// between wrote the guest's entrance but never said "joined the scene" and
// left the join busy (the web Director journey's intermittent failure); a
// /join before the reset lost the guest from the cast as well.
//
// Proven red: calling _openNewChat / _openSession straight from startNewChat
// / loadSession (no _whileSwitchingChat) writes the entrance into the chat
// the switch opened, and sendBusyReason says nothing mid-switch. Without
// the cancel in startNewChat, New chat over a streaming reply waits out the
// 15 s settle bound instead of switching at once.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_join_new_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  /// Streams a reply that never ends on its own, a slow local model.
  bool drip = false;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (drip) {
      for (var i = 0; i < 2000; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        yield 'on ';
      }
      return;
    }
    if (params.systemPrompt != null) {
      yield '*Riley steps onto the porch.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedJoinDuringNewChat';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  ChatService? chat;
  DebugPrintCallback? previousPrint;

  setUp(() {
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
  });
  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    await disposeChatThenCloseDb(chat, db);
  });

  late _ScriptedLlm llm;

  Future<ChatService> boot() async {
    llm = _ScriptedLlm();
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
    final storage = StorageService();
    final repo = CharacterRepository(db!, storage);
    final c = chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db!),
            storage,
            WorldRepository(storage, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    final host = CharacterCard(
      name: 'Flora',
      firstMessage: 'Evening.',
      imagePath: '/tmp/flora-host-jn.png',
    );
    final guest = CharacterCard(
      name: 'Riley',
      firstMessage: 'Hi.',
      imagePath: '/tmp/riley-guest-jn.png',
    );
    await repo.addCharacter(host);
    await repo.addCharacter(guest);
    await c.setActiveCharacter(host);
    return c;
  }

  Future<void> settle(ChatService c) async {
    for (var i = 0; i < 400 && (c.isGenerating || c.isSettlingTurn); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  /// Sends `/join Riley` once [switching] has moved past its first await,
  /// i.e. while the switch is still running.
  Future<String?> joinMidSwitch(
    ChatService c,
    Future<void> Function() switching,
  ) async {
    final before = c.currentSessionId;
    final done = switching();
    for (var i = 0; i < 500 && c.currentSessionId == before; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(c.currentSessionId, isNot(before), reason: 'switch is under way');
    final busy = c.sendBusyReason;
    await c.sendMessage('/join Riley');
    await done;
    await settle(c);
    return busy;
  }

  void expectNoHalfJoin(ChatService c) {
    expect(c.messages.map((m) => m.sender), [
      'Flora',
    ], reason: 'no entrance written into the chat the switch opened');
    expect(c.sceneGuestCards, isEmpty);
    expect(c.isGuestBusy, isFalse);
    expect(c.isLoadingSession, isFalse);
  }

  Future<void> expectJoinWorks(ChatService c) async {
    final statuses = <String?>[];
    void record() => statuses.add(c.guestActivityStatus);
    c.addListener(record);
    await c.sendMessage('/join Riley');
    await settle(c);
    c.removeListener(record);
    expect(c.sceneGuestCards.map((g) => g.name), ['Riley']);
    expect(statuses, contains('Riley joined the scene'));
    expect(c.messages.last.sender, 'Riley');
  }

  test(
    'a /join sent while New chat is still opening is refused, then works',
    () async {
      final c = await boot();
      final busy = await joinMidSwitch(c, c.startNewChat);
      expect(busy, 'The chat is still opening.');
      expectNoHalfJoin(c);
      await expectJoinWorks(c);
    },
  );

  test(
    'a /join sent while another chat is loading is refused, then works',
    () async {
      final c = await boot();
      final first = c.currentSessionId!;
      await c.startNewChat();
      final busy = await joinMidSwitch(c, () => c.loadSession(first));
      expect(busy, 'The chat is still opening.');
      expect(c.currentSessionId, first);
      expectNoHalfJoin(c);
      await expectJoinWorks(c);
    },
  );

  test(
    'New chat during a streaming reply cuts it and switches at once',
    () async {
      final c = await boot();
      final first = c.currentSessionId!;
      llm.drip = true;
      unawaited(c.sendMessage('hello'));
      for (var i = 0; i < 500 && !c.isGenerating; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(c.isGenerating, isTrue, reason: 'the reply is streaming');
      final sw = Stopwatch()..start();
      await c.startNewChat();
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      expect(c.currentSessionId, isNot(first));
      expect(c.isGenerating, isFalse);
      expect(c.messages.map((m) => m.sender), ['Flora']);
      llm.drip = false;
      await c.loadSession(first);
      // The old chat keeps the line and, as Stop does, whatever was on screen.
      expect(c.messages.take(2).map((m) => m.sender), ['Flora', 'User']);
      expect(c.messages[1].text, 'hello');
    },
  );
}
