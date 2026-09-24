// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live Mac fail (Carmen 1:1, PR #303): Porch Life + card have Realism,
// Needs, and Passage of Time ON, Trust chips move, but Needs stay ~80
// and no time_passed chip lands on a normal send.
// Proven red: 1:1 send with those flags and a 30-min clock verdict
// must wear once and stamp the chip.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_11_clock_').path;
        }
        return null;
      });
}

const _carmenNeeds = {
  'hunger': 80,
  'bladder': 80,
  'energy': 80,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": true}';
      return;
    }
    if (p.contains('hunger_delta')) {
      yield '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 0, '
          '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "none"}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":1,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    if (params.systemPrompt != null) {
      yield '*Carmen leans on the rail.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedOneToOneClockWear';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;
  DebugPrintCallback? previousPrint;

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

  Future<CharacterCard> boot({
    bool explicitChatToggles = true,
    bool globalPot = true,
    bool cardPot = true,
    bool globalRealism = true,
    bool cardRealism = true,
    bool standaloneClock = false,
  }) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': globalRealism,
      'needs_sim_default': true,
      'passage_of_time_default': globalPot,
      'standalone_clock_enabled': standaloneClock,
    });
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
          ..testLlmServiceOverride = _ScriptedLlm();
    await storage!.initialized;
    if (standaloneClock) {
      await storage!.realismSettings.setStandaloneClockEnabled(true);
    }

    final carmen = CharacterCard(
      name: 'Carmen',
      firstMessage: 'Evening.',
      imagePath: '/tmp/carmen-11.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: cardRealism,
        needsSimEnabled: true,
        passageOfTimeEnabled: cardPot,
        needsBaselineHunger: 80,
        needsBaselineBladder: 80,
        needsBaselineEnergy: 80,
        needsBaselineSocial: 80,
        needsBaselineFun: 80,
        needsBaselineHygiene: 80,
        needsBaselineComfort: 80,
      ),
    );
    await repo!.addCharacter(carmen);
    await chat!.setActiveCharacter(carmen);
    if (explicitChatToggles) {
      await chat!.setRealismEnabled(cardRealism || globalRealism);
      await chat!.setNeedsSimEnabled(true);
      await chat!.setPassageOfTimeEnabled(true);
    }
    chat!.needsSimulation.restoreFromSnapshot({'vector': _carmenNeeds});
    await drainTurn();
    return carmen;
  }

  int hunger() => chat!.needsSimulation.vector['hunger'] ?? -1;

  ChatMessage lastBot() => chat!.messages.lastWhere((m) => !m.isUser);

  setUp(() {
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    chat?.dispose();
    await db?.close();
  });

  test(
    '1:1 send with PoT + Needs + Realism wears once and stamps time_passed',
    () async {
      await boot();
      expect(hunger(), 80);
      expect(chat!.timeService.passageOfTimeEnabled, isTrue);
      expect(chat!.needsSimEnabled, isTrue);
      expect(chat!.realismEnabled, isTrue);

      await chat!.sendMessage('How are you?');
      await drainTurn();

      expect(
        hunger(),
        78,
        reason: '30 min at Normal is 2 points — Carmen 1:1 must wear',
      );
      expect(
        lastBot().activeMetadata?['time_passed'],
        '30 min',
        reason: 'live fail: no time_passed chip on a normal 1:1 send',
      );
    },
  );

  test(
    '1:1 card+global seed starts the clock without extra chat toggles',
    () async {
      await boot(explicitChatToggles: false);
      expect(
        chat!.realismEnabled,
        isTrue,
        reason: 'card realism OR global default must seed the chat',
      );
      expect(
        chat!.needsSimEnabled,
        isTrue,
        reason: 'card needs AND global default must seed the chat',
      );
      expect(
        chat!.timeService.passageOfTimeEnabled,
        isTrue,
        reason:
            'card PoT AND global passageOfTimeDefault must seed the '
            'chat-scoped clock — Porch Life ON must not leave it stopped',
      );

      await chat!.sendMessage('How are you?');
      await drainTurn();

      expect(hunger(), 78);
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
    },
  );

  test(
    'frozen 1:1 clock still wears one beat and does not stamp time_passed',
    () async {
      await boot();
      await chat!.setPassageOfTimeEnabled(false);
      expect(chat!.timeService.passageOfTimeEnabled, isFalse);

      await chat!.sendMessage('How are you?');
      await drainTurn();

      expect(
        hunger(),
        78,
        reason: 'clock off is one ordinary beat — Needs must still wear',
      );
      expect(
        lastBot().activeMetadata?['time_passed'],
        isNull,
        reason: 'design: no duration chip when the clock did not move',
      );
    },
  );

  test(
    '1:1 regen wears once from the pre-wear stamp and restamps time_passed',
    () async {
      await boot();
      await chat!.sendMessage('How are you?');
      await drainTurn();
      expect(hunger(), 78);
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
      final firstSwipe = lastBot().swipeIndex;

      await chat!.regenerateLastMessage();
      await drainTurn();

      expect(
        lastBot().swipes.length,
        greaterThan(1),
        reason: 'regen is a new swipe, not a replace',
      );
      expect(lastBot().swipeIndex, isNot(firstSwipe));
      expect(
        hunger(),
        78,
        reason:
            'regen must restore the pre-wear bars then wear once — '
            'not stay 80 (skip) and not drop to 76 (double)',
      );
      expect(
        lastBot().activeMetadata?['time_passed'],
        '30 min',
        reason: 'regen is GenerationMode.normal — clock→wear→chip must run',
      );

      final regenIndex = chat!.messages.indexOf(lastBot());
      await chat!.swipeMessage(regenIndex, -1);
      await drainTurn();
      expect(
        hunger(),
        78,
        reason: 'swipe back to the first reply keeps that swipe\'s worn bars',
      );
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
    },
  );

  test(
    '1:1 send and regen wear when Realism is off and the clock still runs',
    () async {
      await boot(
        globalRealism: false,
        cardRealism: false,
        standaloneClock: true,
      );
      expect(chat!.realismEnabled, isFalse);
      expect(chat!.needsSimEnabled, isTrue);
      expect(chat!.timeService.passageOfTimeEnabled, isTrue);
      expect(hunger(), 80);

      await chat!.sendMessage('How are you?');
      await drainTurn();
      expect(
        hunger(),
        78,
        reason:
            'Needs wear answers to the Needs switch, not the '
            'Realism header — a 30-min send must drop 80→78',
      );
      expect(
        lastBot().activeMetadata?['time_passed'],
        '30 min',
        reason:
            'standalone clock + PoT still stamps the chip when '
            'the Realism engine is off',
      );

      await chat!.regenerateLastMessage();
      await drainTurn();
      expect(
        hunger(),
        78,
        reason:
            'regen must restore the pre-wear bars then wear once '
            'even when Realism is off',
      );
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
    },
  );
}
