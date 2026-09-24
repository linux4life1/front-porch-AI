// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live Mac fail (Carmen 1:1, PR #303 a80): Passage of Time is on but
// the story clock does not advance on send — Needs + PoT with Realism
// off left _clockRunning false, so the time eval never ran. Missing
// chip is a symptom. Needs is a clock driver. No flat clock tax.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show kNeedsUnaffectedMeta;
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

  Map<String, int> bars() =>
      Map<String, int>.from(chat!.needsSimulation.vector);

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
    '1:1 send stamps time_passed and does not tax every Need from the clock',
    () async {
      await boot();
      expect(bars(), _carmenNeeds);
      expect(chat!.timeService.passageOfTimeEnabled, isTrue);
      expect(chat!.needsSimEnabled, isTrue);
      expect(chat!.realismEnabled, isTrue);

      await chat!.sendMessage('How are you?');
      await drainTurn();

      expect(
        bars(),
        _carmenNeeds,
        reason:
            'scene eval returned zeros — a 30-min clock must not '
            'drop Hunger+Bladder+Energy+Social+Fun+Hygiene+Comfort',
      );
      expect(
        lastBot().activeMetadata?['time_passed'],
        '30 min',
        reason: 'live fail: no time_passed chip on a normal 1:1 send',
      );
      expect(
        lastBot().activeMetadata?[kNeedsUnaffectedMeta],
        isTrue,
        reason:
            'short no-action turn must stamp No needs affected so '
            'the UI proves Needs ran without moving bars',
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

      expect(bars(), _carmenNeeds);
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
      expect(lastBot().activeMetadata?[kNeedsUnaffectedMeta], isTrue);
    },
  );

  test('frozen 1:1 clock does not stamp time_passed or invent wear', () async {
    await boot();
    await chat!.setPassageOfTimeEnabled(false);
    expect(chat!.timeService.passageOfTimeEnabled, isFalse);

    await chat!.sendMessage('How are you?');
    await drainTurn();

    expect(bars(), _carmenNeeds, reason: 'a stopped clock is not a body tax');
    expect(
      lastBot().activeMetadata?['time_passed'],
      isNull,
      reason: 'design: no duration chip when the clock did not move',
    );
    expect(
      lastBot().activeMetadata?[kNeedsUnaffectedMeta],
      isTrue,
      reason: 'no-action still proves Needs ran when time did not move',
    );
  });

  test(
    '1:1 regen restamps time_passed and does not invent clock wear',
    () async {
      await boot();
      await chat!.sendMessage('How are you?');
      await drainTurn();
      expect(bars(), _carmenNeeds);
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
        bars(),
        _carmenNeeds,
        reason:
            'regen must not apply a board-wide clock tax — '
            'scene eval is still zeros',
      );
      expect(
        lastBot().activeMetadata?['time_passed'],
        '30 min',
        reason: 'regen is GenerationMode.normal — clock→chip must run',
      );

      final regenIndex = chat!.messages.indexOf(lastBot());
      await chat!.swipeMessage(regenIndex, -1);
      await drainTurn();
      expect(bars(), _carmenNeeds);
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
    },
  );

  test(
    '1:1 PoT+Needs send advances story time when Realism and standalone are off',
    () async {
      await boot(
        globalRealism: false,
        cardRealism: false,
        standaloneClock: false,
      );
      expect(chat!.realismEnabled, isFalse);
      expect(chat!.needsSimEnabled, isTrue);
      expect(chat!.timeService.passageOfTimeEnabled, isTrue);
      final before = chat!.timeService.clock;

      await chat!.sendMessage('How are you?');
      await drainTurn();

      expect(
        chat!.timeService.clock.difference(before).inMinutes,
        30,
        reason:
            'live Mac a80: PoT ON + Needs ON + Realism off left '
            '_clockRunning false, so the time eval never ran and '
            'minutes stayed 0. Needs is a clock driver.',
      );
      expect(
        lastBot().activeMetadata?['time_passed'],
        '30 min',
        reason: 'clock beat must stamp the swipe-slot chip',
      );
      expect(bars(), _carmenNeeds);
    },
  );

  test(
    '1:1 send and regen stamp time when Realism is off and the clock still runs',
    () async {
      await boot(
        globalRealism: false,
        cardRealism: false,
        standaloneClock: true,
      );
      expect(chat!.realismEnabled, isFalse);
      expect(chat!.needsSimEnabled, isTrue);
      expect(chat!.timeService.passageOfTimeEnabled, isTrue);
      expect(bars(), _carmenNeeds);

      await chat!.sendMessage('How are you?');
      await drainTurn();
      expect(
        bars(),
        _carmenNeeds,
        reason:
            'Needs stay put when the scene eval is zero — the '
            'clock chip is not a body tax',
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
      expect(bars(), _carmenNeeds);
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
    },
  );
}
