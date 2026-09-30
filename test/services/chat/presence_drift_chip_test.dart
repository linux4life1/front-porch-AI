// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Presence-drift chip on a reply matches that reply's own before/after
// pair (label text / minutes), including after regen and swipe.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show
        minutesFromTimePassed,
        slotClockAfter,
        slotClockBefore,
        timePassedLabel;
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_drift_chip_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  int nextMinutes = 30;
  bool withUser = true;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Nia leans on the rail.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": $withUser}';
      return;
    }
    if (p.contains('hunger_delta')) {
      yield '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 0, '
          '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "none"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": $nextMinutes, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedDriftChip';
}

void _expectChipMatchesPair(ChatMessage msg, {required String reason}) {
  final before = slotClockBefore(msg.activeMetadata);
  final after = slotClockAfter(msg.activeMetadata);
  expect(before, isNotNull, reason: reason);
  expect(after, isNotNull, reason: reason);
  final mins = after!.difference(before!).inMinutes;
  expect(
    msg.activeMetadata?['time_passed'],
    timePassedLabel(minutes: mins, nextMorning: false, isSkip: false),
    reason: reason,
  );
  expect(minutesFromTimePassed(msg.activeMetadata?['time_passed']), mins);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  ChatService? chat;
  late _ScriptedLlm llm;

  Future<void> drainTurn() async {
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
      imagePath: '/tmp/nia-drift-chip.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
      ),
    );
    await repo.addCharacter(nia);
    await chat!.setActiveCharacter(nia);
    await drainTurn();
  }

  ChatMessage lastBot() => chat!.messages.lastWhere((m) => !m.isUser);

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'presence-drift chip matches the reply pair after send, regen, and swipe',
    () async {
      await boot();
      llm.nextMinutes = 30;
      await chat!.sendMessage('How long has it been?');
      await drainTurn();
      final first = lastBot();
      _expectChipMatchesPair(
        first,
        reason: 'send stamps a chip that names the before→after minutes',
      );
      final firstChip = first.activeMetadata?['time_passed'];
      final firstAfter = slotClockAfter(first.activeMetadata);

      llm.nextMinutes = 5;
      await chat!.regenerateLastMessage();
      await drainTurn();
      expect(lastBot().swipes.length, greaterThan(1));
      _expectChipMatchesPair(
        lastBot(),
        reason: 'regen swipe stamps its own pair, not the rejected swipe\'s',
      );
      expect(
        lastBot().activeMetadata?['time_passed'],
        isNot(firstChip),
        reason: '5 min regen must not keep the 30 min chip',
      );

      final idx = chat!.messages.indexOf(lastBot());
      await chat!.swipeMessage(idx, -1);
      await drainTurn();
      _expectChipMatchesPair(
        lastBot(),
        reason: 'swiped-back reply keeps a chip consistent with ITS pair',
      );
      expect(lastBot().activeMetadata?['time_passed'], firstChip);
      expect(slotClockAfter(lastBot().activeMetadata), firstAfter);
    },
  );

  test(
    'presence-drift Away path (with_user false) still matches the pair',
    () async {
      await boot();
      llm.withUser = false;
      llm.nextMinutes = 30;
      await chat!.sendMessage('Where did you go?');
      await drainTurn();
      expect(
        chat!.relationshipService.withUser,
        isFalse,
        reason: 'with_user: false must land on the Away glance',
      );
      _expectChipMatchesPair(
        lastBot(),
        reason: 'Away path still stamps a chip that names the pair minutes',
      );
    },
  );
}
