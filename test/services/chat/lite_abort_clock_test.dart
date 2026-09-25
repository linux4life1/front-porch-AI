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
import '../../helpers/chat_db_teardown.dart';

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
  bool hangNextMouth = false;
  bool hangSecondClock = true;

  bool get isHanging => _hang != null && !_hang!.isCompleted;

  void releaseHang() {
    final hang = _hang;
    if (hang != null && !hang.isCompleted) hang.complete();
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      if (hangNextMouth) {
        hangNextMouth = false;
        _hang = Completer<void>();
        await _hang!.future;
      }
      yield '*Riley leans on the rail.*';
      return;
    }
    if (params.prompt.contains('minutes_elapsed')) {
      clockCalls++;
      if (hangSecondClock && clockCalls == 2) {
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

  tearDown(() => disposeChatThenCloseDb(chat, db));

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

  // 58263222: Continue returned before _setGuestStatus and skipped the
  // abort-write. cda3dc56 always sets 'Reply kept' after every branch.
  test('Continue abort: no Reply kept banner, stored pair unchanged', () async {
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
    final hang = _HangSecondClockLlm()..hangSecondClock = false;
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
      imagePath: '/tmp/flora-cont-abort.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        needsBaselineHunger: 40,
      ),
    );
    final guest = CharacterCard(
      name: 'Riley',
      firstMessage: 'Hi.',
      imagePath: '/tmp/riley-cont-abort.png',
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

    await chat!.sendMessage('Riley, say hello.');
    await drainTurn();

    final tip = chat!.messages.last;
    expect(tip.sender, 'Riley');
    final beforeIso = tip.activeMetadata?['story_clock_before'];
    final afterIso = tip.activeMetadata?['story_clock_after'];
    final metaBefore = tip.metadata?['story_clock_before'];
    final metaAfter = tip.metadata?['story_clock_after'];

    hang.hangNextMouth = true;
    final continued = chat!.continueGeneration();
    await waitUntil(() => hang.isHanging);
    expect(chat!.isGenerating || chat!.isSettlingTurn, isTrue);

    chat!.debugRequestPostGenAbort();
    hang.releaseHang();
    await continued;
    await drainTurn();

    expect(
      chat!.guestActivityStatus ?? '',
      isNot(contains('Reply kept')),
      reason:
          '58263222 Continue abort returned before Reply kept; '
          'banner must stay off',
    );
    expect(
      tip.activeMetadata?['story_clock_before'],
      beforeIso,
      reason: 'Continue abort must not rewrite the stored before',
    );
    expect(
      tip.activeMetadata?['story_clock_after'],
      afterIso,
      reason: 'Continue abort must not rewrite the stored after',
    );
    expect(
      tip.metadata?['story_clock_before'],
      metaBefore,
      reason: 'Continue abort must not rewrite metadata before',
    );
    expect(
      tip.metadata?['story_clock_after'],
      metaAfter,
      reason: 'Continue abort must not rewrite metadata after',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
