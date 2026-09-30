// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Parked for follow-up PR: #303 scope freeze. Three UI extras are being
// reverted from lib; these pins must not sit red on #303. Un-skip here
// when that follow-up lands.
//
// Proven red-then-green against the lib commits that shipped the extras:
// - message bubble missing-avatar letter
//   (was test/ui/widgets/missing_avatar_fallback_test.dart :53)
//   → 2eed2a98 (letter-falls missing avatars; with c23cd249 avatar work)
// - regen / swipe-right during settle is not Reply kept
//   (was test/services/chat/settling_regen_no_reply_kept_test.dart)
//   → c23cd249 (no Reply kept)
// - failure drift does not replace a Next morning chip
//   (was test/services/chat/next_morning_drift_chip_test.dart)
//   → c23cd249 (Next morning)

@Skip(
  'Parked for follow-up PR: #303 scope freeze (bubble letter, settle Reply kept, drift Next morning)',
)
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/bubbles/message_bubble.dart';

import '../golden/support/creator_test_support.dart';
import '../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  final missing = File('/tmp/fpai-missing-avatar-does-not-exist.png');

  testWidgets('message bubble with a missing avatar file shows a letter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              text: 'Evening.',
              sender: 'Carmen',
              isUser: false,
            ),
            index: 0,
            characterImage: missing,
            character: CharacterCard(name: 'Carmen'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('C'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image), findsNothing);
    expect(find.byIcon(Icons.person), findsNothing);
  });

  group('settling Reply kept', () {
    AppDatabase? db;
    ChatService? chat;
    late _HangClockLlm llm;

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

    Future<void> waitUntil(bool Function() pred) async {
      for (var i = 0; i < 250 && !pred(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    Future<void> boot() async {
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
      llm = _HangClockLlm();
      chat =
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
      final nia = CharacterCard(
        name: 'Nia',
        firstMessage: 'Evening.',
        imagePath: '/tmp/nia-settle-kept.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
        ),
      );
      await repo.addCharacter(nia);
      await chat!.setActiveCharacter(nia);
      await drain();
    }

    tearDown(() => disposeChatThenCloseDb(chat, db));

    test('regen during a settling turn does not show Reply kept', () async {
      await boot();
      final sent = chat!.sendMessage('Hey.');
      await waitUntil(() => llm.clockCalls >= 1 && chat!.isSettlingTurn);
      expect(chat!.isSettlingTurn, isTrue);
      final regen = chat!.regenerateLastMessage();
      llm.release();
      await sent;
      await regen;
      await drain();
      expect(
        chat!.guestActivityStatus ?? '',
        isNot(contains('Reply kept')),
        reason: 'regen during settle is a new reply, not a keep',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
      'swipe-right during a settling turn does not show Reply kept',
      () async {
        await boot();
        final sent = chat!.sendMessage('Hey.');
        await waitUntil(() => llm.clockCalls >= 1 && chat!.isSettlingTurn);
        expect(chat!.isSettlingTurn, isTrue);
        final tip = chat!.messages.lastWhere((m) => !m.isUser);
        final swipe = chat!.swipeMessage(chat!.messages.indexOf(tip), 1);
        llm.release();
        await sent;
        await swipe;
        await drain();
        expect(
          chat!.guestActivityStatus ?? '',
          isNot(contains('Reply kept')),
          reason: 'swipe-right during settle must not claim the reply was kept',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group('Next morning drift', () {
    AppDatabase? db;
    ChatService? chat;
    late _ScriptedLlm llm;

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

    test('drift does not overwrite an existing Next morning chip', () async {
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
      llm = _ScriptedLlm();
      chat =
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
      final nia = CharacterCard(
        name: 'Nia',
        firstMessage: 'Evening.',
        imagePath: '/tmp/nia-nm-drift.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
        ),
      );
      await repo.addCharacter(nia);
      await chat!.setActiveCharacter(nia);
      await chat!.setStoryClock(DateTime.utc(2026, 6, 29, 16, 37));
      await drain();

      await chat!.sendMessage('See you in the morning.');
      await drain();
      final last = chat!.messages.lastWhere((m) => !m.isUser);
      expect(last.activeMetadata?['time_passed'], 'Next morning');

      await chat!.timeService.applyFailureDrift();
      expect(
        last.activeMetadata?['time_passed'],
        'Next morning',
        reason: 'failure drift must not replace the Next morning chip',
      );
    });
  });
}

class _HangClockLlm extends LLMService {
  Completer<void>? _hang;
  int clockCalls = 0;

  void release() {
    final hang = _hang;
    if (hang != null && !hang.isCompleted) hang.complete();
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Nia leans on the rail.*';
      return;
    }
    if (params.prompt.contains('minutes_elapsed')) {
      clockCalls++;
      if (clockCalls == 1) {
        _hang = Completer<void>();
        await _hang!.future;
      }
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    if (params.prompt.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SettleNoKept';
}

class _ScriptedLlm extends LLMService {
  bool nextDay = true;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Nia calls it a night.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 30, "new_day": $nextDay}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'NextMorningDrift';
}
