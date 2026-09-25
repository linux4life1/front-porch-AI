// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Lite / short post-gen calls `_abortSlotClockIfThisTurnTicked` at
// chat_service_generation_postgen.dart:217 and :221. Pin the abort-write
// contract: clock == before, active slot before == after, no time chip,
// honest banner.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show slotClockAfter, slotClockBefore;
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_lite_abort_').path;
        }
        return null;
      });
}

const _hostNeeds = {
  'hunger': 40,
  'bladder': 80,
  'energy': 80,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

class _HangSecondClockLlm extends LLMService {
  Completer<void>? _hang;
  int clockCalls = 0;

  void releaseHang() {
    final hang = _hang;
    if (hang != null && !hang.isCompleted) hang.complete();
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Riley leans on the rail.*';
      return;
    }
    if (params.prompt.contains('minutes_elapsed')) {
      clockCalls++;
      if (clockCalls == 2) {
        _hang = Completer<void>();
        await _hang!.future;
      }
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'HangLiteAbort';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  ChatService? chat;

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

  Future<void> waitUntil(bool Function() pred) async {
    for (var i = 0; i < 250 && !pred(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  tearDown(() async {
    chat?.dispose();
    await db?.close();
  });

  test(
    'lite abort rewrite: clock == before, pair equal, no chip, honest banner',
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
      final hang = _HangSecondClockLlm();
      chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db!),
              storage,
              WorldRepository(storage, db!),
            )
            ..setDatabase(db!)
            ..setCharacterRepository(repo)
            ..testLlmServiceOverride = hang;
      await storage.initialized;
      final host = CharacterCard(
        name: 'Flora',
        firstMessage: 'Evening.',
        imagePath: '/tmp/flora-lite-abort.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          needsBaselineHunger: 40,
        ),
      );
      final guest = CharacterCard(
        name: 'Riley',
        firstMessage: 'Hi.',
        imagePath: '/tmp/riley-lite-abort.png',
        frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
      );
      await repo.addCharacter(host);
      await repo.addCharacter(guest);
      await chat!.setActiveCharacter(host);
      await chat!.setRealismEnabled(true);
      await chat!.setNeedsSimEnabled(true);
      await chat!.setPassageOfTimeEnabled(true);
      chat!.needsSimulation.restoreFromSnapshot({'vector': _hostNeeds});
      await chat!.joinSceneGuest(guest);
      await drainTurn();
      chat!.needsSimulation.restoreFromSnapshot({'vector': _hostNeeds});

      final before = chat!.timeService.clock;
      expect(hang.clockCalls, 1);
      final sent = chat!.sendMessage('Riley, say hello.');
      await waitUntil(() => hang.clockCalls >= 2);
      expect(chat!.isSettlingTurn, isTrue);

      chat!.debugRequestPostGenAbort();
      hang.releaseHang();
      await sent;
      await drainTurn();

      final last = chat!.messages.last;
      expect(last.sender, 'Riley');
      expect(
        chat!.timeService.clock,
        before,
        reason: 'lite abort must restore the pre-tick clock',
      );
      expect(
        slotClockAfter(last.activeMetadata),
        slotClockBefore(last.activeMetadata),
        reason: 'abort-write sets after == before on the kept tip',
      );
      expect(last.activeMetadata?['time_passed'], isNull);
      expect(
        chat!.guestActivityStatus,
        contains('Reply kept. Scene time and needs weren\'t updated.'),
        reason: 'honest banner when the abort rewrote a ticked slot',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
