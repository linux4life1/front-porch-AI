// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live Mac (Carmen 1:1, Realism+PoT+Needs ON): the time eval may return
// bare minutes_elapsed 0. That used to freeze the clock (_applyElapsed
// m>0) and hide the chip. A normal send now floors to 2 min. Same
// moment needs an explicit continuous_instant flag. PoT is the only
// clock driver. No flat clock tax.

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

class _ZeroMinuteLlm extends _ScriptedLlm {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 0, "new_day": false}';
      return;
    }
    yield* super.generateStream(params);
  }
}

class _ContinuousInstantLlm extends _ScriptedLlm {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 0, "new_day": false, '
          '"continuous_instant": true}';
      return;
    }
    yield* super.generateStream(params);
  }
}

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
    bool needsEnabled = true,
    LLMService? llm,
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
          ..testLlmServiceOverride = llm ?? _ScriptedLlm();
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
        needsSimEnabled: needsEnabled,
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
      await chat!.setNeedsSimEnabled(needsEnabled);
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
    '1:1 Realism+PoT+Needs ON, bare minutes_elapsed 0 floors the clock',
    () async {
      await boot(llm: _ZeroMinuteLlm());
      expect(chat!.realismEnabled, isTrue);
      expect(chat!.needsSimEnabled, isTrue);
      expect(chat!.timeService.passageOfTimeEnabled, isTrue);
      expect(bars(), _carmenNeeds);
      final before = chat!.timeService.clock;

      await chat!.sendMessage('How are you?');
      await drainTurn();

      expect(
        chat!.timeService.clock.difference(before).inMinutes,
        2,
        reason:
            'live Mac: bare minutes_elapsed 0 froze the clock. '
            'A normal send must fail-closed to the conversational floor.',
      );
      expect(
        lastBot().activeMetadata?['time_passed'],
        '2 min',
        reason: 'floor must stamp the swipe-slot chip, not hide it',
      );
      expect(
        bars(),
        _carmenNeeds,
        reason: 'the floor advances the clock only — it never wears Needs',
      );
      expect(
        lastBot().activeMetadata?[kNeedsUnaffectedMeta],
        isTrue,
        reason: 'short no-action still shows No needs affected',
      );
    },
  );

  test(
    '1:1 explicit continuous_instant leaves the clock and says same moment',
    () async {
      await boot(llm: _ContinuousInstantLlm());
      final before = chat!.timeService.clock;

      await chat!.sendMessage('How are you?');
      await drainTurn();

      expect(
        chat!.timeService.clock,
        before,
        reason:
            'same moment is only legal with an explicit continuous_instant '
            'signal — not a bare 0',
      );
      expect(
        lastBot().activeMetadata?['time_passed'],
        'same moment',
        reason: 'the chip must name the still beat',
      );
      expect(bars(), _carmenNeeds);
      expect(lastBot().activeMetadata?[kNeedsUnaffectedMeta], isTrue);
    },
  );

  test('1:1 scripted 30 moves the clock and stamps 30 min', () async {
    await boot();
    expect(bars(), _carmenNeeds);
    expect(chat!.timeService.passageOfTimeEnabled, isTrue);
    expect(chat!.needsSimEnabled, isTrue);
    expect(chat!.realismEnabled, isTrue);
    final before = chat!.timeService.clock;

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
      chat!.timeService.clock.difference(before).inMinutes,
      30,
      reason: 'scripted 30 must move storyClockIso',
    );
    expect(
      lastBot().activeMetadata?[kNeedsUnaffectedMeta],
      isTrue,
      reason:
          'short no-action turn must stamp No needs affected so '
          'the UI proves Needs ran without moving bars',
    );
  });

  test('1:1 PoT ON with Realism and Needs OFF still advances', () async {
    await boot(
      globalRealism: false,
      cardRealism: false,
      standaloneClock: false,
      needsEnabled: false,
    );
    expect(chat!.realismEnabled, isFalse);
    expect(chat!.needsSimEnabled, isFalse);
    expect(chat!.timeService.passageOfTimeEnabled, isTrue);
    final before = chat!.timeService.clock;

    await chat!.sendMessage('How are you?');
    await drainTurn();

    expect(
      chat!.timeService.clock.difference(before).inMinutes,
      30,
      reason:
          'PoT is the only clock driver. Realism OFF + Needs OFF must '
          'not freeze a chat whose Automatic Passage of Time is on.',
    );
    expect(
      lastBot().activeMetadata?['time_passed'],
      '30 min',
      reason: 'clock beat must stamp the swipe-slot chip',
    );
  });

  test('1:1 PoT OFF gives no tick and no time chip', () async {
    await boot();
    await chat!.setPassageOfTimeEnabled(false);
    expect(chat!.timeService.passageOfTimeEnabled, isFalse);
    final before = chat!.timeService.clock;

    await chat!.sendMessage('How are you?');
    await drainTurn();

    expect(chat!.timeService.clock, before, reason: 'PoT off never ticks');
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
            'Porch Life passageOfTimeDefault seeds new chats. The card '
            'must not AND-veto the live clock.',
      );

      await chat!.sendMessage('How are you?');
      await drainTurn();

      expect(bars(), _carmenNeeds);
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
      expect(lastBot().activeMetadata?[kNeedsUnaffectedMeta], isTrue);
    },
  );

  test(
    '1:1 global PoT seed is not AND-vetoed by a card that left PoT off',
    () async {
      await boot(explicitChatToggles: false, cardPot: false, globalPot: true);
      expect(
        chat!.timeService.passageOfTimeEnabled,
        isTrue,
        reason:
            'chat-gear Automatic Passage of Time starts from the Porch '
            'Life default, not card ∧ default',
      );

      await chat!.sendMessage('How are you?');
      await drainTurn();
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
    },
  );

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

  test('1:1 Continue does not tick the story clock', () async {
    await boot();
    await chat!.sendMessage('How are you?');
    await drainTurn();
    expect(lastBot().activeMetadata?['time_passed'], '30 min');
    final afterSend = chat!.timeService.clock;

    await chat!.continueGeneration();
    await drainTurn();

    expect(
      chat!.timeService.clock,
      afterSend,
      reason: 'Continue is the same beat — it must not run the time eval',
    );
    expect(bars(), _carmenNeeds);
  });

  test(
    '1:1 send and regen stamp time when Realism is off and the clock still runs',
    () async {
      await boot(
        globalRealism: false,
        cardRealism: false,
        standaloneClock: false,
        needsEnabled: false,
      );
      expect(chat!.realismEnabled, isFalse);
      expect(chat!.needsSimEnabled, isFalse);
      expect(chat!.timeService.passageOfTimeEnabled, isTrue);

      await chat!.sendMessage('How are you?');
      await drainTurn();
      expect(
        lastBot().activeMetadata?['time_passed'],
        '30 min',
        reason: 'PoT alone stamps the chip when the Realism engine is off',
      );

      await chat!.regenerateLastMessage();
      await drainTurn();
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
    },
  );
}
