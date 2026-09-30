// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live Mac (Carmen 1:1, Realism+PoT+Needs ON): the time eval may return
// bare minutes_elapsed 0. That used to freeze the clock (_applyElapsed
// m>0) and hide the chip. A normal send now floors to 2 min. Same
// moment needs an explicit continuous_instant flag. PoT is the only
// clock driver. No flat clock tax.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show kNeedsUnaffectedMeta;
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

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

class _QuotedInstantLlm extends _ScriptedLlm {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 0, "new_day": false, '
          '"continuous_instant": "true"}';
      return;
    }
    yield* super.generateStream(params);
  }
}

class _NegativeMinuteLlm extends _ScriptedLlm {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": -8, "new_day": false}';
      return;
    }
    yield* super.generateStream(params);
  }
}

class _ThrowingTimeLlm extends _ScriptedLlm {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains('minutes_elapsed')) {
      throw Exception('time eval down');
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
    bool needsEnabled = true,
    LLMService? llm,
  }) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': globalRealism,
      'needs_sim_default': true,
      'passage_of_time_default': globalPot,
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

  tearDown(() => disposeChatThenCloseDb(chat, db));

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
    await boot(globalRealism: false, cardRealism: false, needsEnabled: false);
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
          'not freeze a chat whose Porch Life Passage of Time is on.',
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
            'Porch Life Passage of Time is the only clock gate. '
            'A new chat with that row ON must run.',
      );

      await chat!.sendMessage('How are you?');
      await drainTurn();

      expect(bars(), _carmenNeeds);
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
      expect(lastBot().activeMetadata?[kNeedsUnaffectedMeta], isTrue);
    },
  );

  test('1:1 card PoT OFF is ignored when Porch Life is ON', () async {
    await boot(explicitChatToggles: false, cardPot: false, globalPot: true);
    expect(storage!.realismSettings.passageOfTimeDefault, isTrue);
    expect(
      chat!.timeService.passageOfTimeEnabled,
      isTrue,
      reason: 'Porch Life is the only clock gate. Card off is not a veto.',
    );
    final before = chat!.timeService.clock;

    await chat!.sendMessage('How are you?');
    await drainTurn();

    expect(chat!.timeService.clock.difference(before).inMinutes, 30);
    expect(lastBot().activeMetadata?['time_passed'], '30 min');
  });

  test(
    '1:1 old-schema leftover PoT false + lived-in clock migrates, sends, and regens',
    () async {
      await boot(explicitChatToggles: false, cardPot: false);
      expect(storage!.realismSettings.passageOfTimeDefault, isTrue);
      await chat!.flushPendingSaves();

      // First-open freeze writes storyClock via an unawaited patch. Wait
      // until that lands so the leftover plant is not overwritten.
      final sid = chat!.currentSessionId!;
      for (var i = 0; i < 40; i++) {
        final seeded = await db!.getSessionById(sid);
        if (seeded?.storyClock != null && seeded!.storyClock!.isNotEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // Carmen is a pre-PR transcript: leftover per-chat PoT false, a
      // lived-in session clock, and every existing bot stamp is
      // pre-calendar (timeOfDay + dayCount, no storyClock, no
      // story_clock_before). The greeting snap is Day 1 morning — the
      // "rolled back to match timeline" trap that used to pin 9:00 AM.
      // Stall (_turnsSinceClockMoved) is in-memory and reset on load;
      // leftover PoT false is the persisted pause.
      const livedIso = '2026-06-30T14:30:00.000Z';
      const startIso = '2026-06-28';
      final lived = DateTime.utc(2026, 6, 30, 14, 30);
      const day1Morning = {
        'timeOfDay': 'morning',
        'dayCount': 1,
        'characterEmotion': 'neutral',
        'emotionIntensity': 'mild',
      };
      final greetingMeta = jsonEncode({'realism_state': day1Morning});
      final lastBotMeta = jsonEncode({'realism_state': day1Morning});

      await db!.deleteMessagesForSession(sid);
      await db!.insertMessage(
        MessagesCompanion.insert(
          id: 'carmen-old-g',
          sessionId: sid,
          position: 0,
          sender: 'Carmen',
          isUser: false,
          swipes: Value(jsonEncode(['Evening.'])),
          metadata: Value(greetingMeta),
          swipeMetadata: Value(jsonEncode([jsonDecode(greetingMeta)])),
        ),
      );
      await db!.insertMessage(
        MessagesCompanion.insert(
          id: 'carmen-old-u',
          sessionId: sid,
          position: 1,
          sender: 'You',
          isUser: true,
          swipes: Value(jsonEncode(['Hey.'])),
        ),
      );
      await db!.insertMessage(
        MessagesCompanion.insert(
          id: 'carmen-old-b',
          sessionId: sid,
          position: 2,
          sender: 'Carmen',
          isUser: false,
          swipes: Value(jsonEncode(['*Carmen leans on the rail.*'])),
          metadata: Value(lastBotMeta),
          swipeMetadata: Value(jsonEncode([jsonDecode(lastBotMeta)])),
        ),
      );
      await db!.patchSession(
        SessionsCompanion(
          id: Value(sid),
          passageOfTimeEnabled: const Value(false),
          passageOfTimeGateMigrated: const Value(false),
          storyClock: const Value(livedIso),
          storyStartDate: const Value(startIso),
          timeOfDay: const Value('afternoon'),
          dayCount: const Value(3),
        ),
      );
      final planted = await db!.getSessionById(sid);
      expect(
        planted!.storyClock,
        livedIso,
        reason: 'leftover plant must survive the first-open clock freeze',
      );

      await chat!.reloadCurrentSession();
      await drainTurn();

      expect(
        chat!.timeService.clock,
        lived,
        reason:
            'hydrate must pick up the session clock, not synthesize '
            'Day 1 9:00 from the pre-calendar greeting snap',
      );
      expect(chat!.messages.length, greaterThanOrEqualTo(3));
      final row = await db!.getSessionById(sid);
      expect(
        row!.passageOfTimeGateMigrated,
        isTrue,
        reason: 'one-shot migrate must set the flag',
      );
      expect(
        chat!.timeService.passageOfTimeEnabled,
        isTrue,
        reason:
            'Porch Life ON runs the clock. Leftover per-chat false and '
            'card OFF are not a gate.',
      );
      expect(storage!.realismSettings.passageOfTimeDefault, isTrue);

      // Regen the existing last reply first — no story_clock_before, and
      // the previous accepted snap is Day 1 morning. Must keep the
      // session clock, not synthesize 9:00 AM.
      await chat!.regenerateLastMessage();
      await drainTurn();
      expect(
        chat!.timeService.clock.difference(lived).inMinutes,
        30,
        reason:
            'regen of a pre-calendar last bot must advance from the '
            'saved session clock, not Day 1 9:00 AM',
      );
      expect(lastBot().activeMetadata?['time_passed'], '30 min');

      await chat!.sendMessage('How are you?');
      await drainTurn();
      expect(
        chat!.timeService.clock.difference(lived).inMinutes,
        60,
        reason: 'send must keep advancing from the lived-in clock, not 9:00 AM',
      );
      expect(lastBot().activeMetadata?['time_passed'], '30 min');

      // Rejected swipe looks like the old last bot: pre-calendar snap,
      // no storyClock. story_clock_before on this send still rewinds.
      final rs = lastBot().activeMetadata?['realism_state'];
      if (rs is Map) {
        rs.remove('storyClock');
        rs.remove('storyStartDate');
        rs['timeOfDay'] = 'morning';
        rs['dayCount'] = 1;
      }

      await chat!.regenerateLastMessage();
      await drainTurn();
      expect(
        chat!.timeService.clock.difference(lived).inMinutes,
        60,
        reason:
            'regen must not apply the previous bot\'s Day 1 morning snap '
            'or roll the sidebar back to 9:00 AM',
      );
      expect(lastBot().activeMetadata?['time_passed'], '30 min');

      await storage!.realismSettings.setPassageOfTimeDefault(false);
      expect(chat!.timeService.passageOfTimeEnabled, isFalse);
      final frozen = chat!.timeService.clock;
      await chat!.sendMessage('Still there?');
      await drainTurn();
      expect(
        chat!.timeService.clock,
        frozen,
        reason: 'Porch Life OFF freezes even with leftover per-chat ignored',
      );
      expect(lastBot().activeMetadata?['time_passed'], isNull);
    },
  );

  test('1:1 Porch Life OFF means no advance', () async {
    await boot();
    await storage!.realismSettings.setPassageOfTimeDefault(false);
    expect(chat!.timeService.passageOfTimeEnabled, isFalse);
    final before = chat!.timeService.clock;

    await chat!.sendMessage('How are you?');
    await drainTurn();

    expect(chat!.timeService.clock, before);
    expect(lastBot().activeMetadata?['time_passed'], isNull);
  });

  test('1:1 Porch Life OFF then ON flips live on an open chat', () async {
    await boot();
    await storage!.realismSettings.setPassageOfTimeDefault(false);
    expect(chat!.timeService.passageOfTimeEnabled, isFalse);
    final origin = chat!.timeService.clock;

    await chat!.sendMessage('How are you?');
    await drainTurn();
    expect(chat!.timeService.clock, origin);
    expect(lastBot().activeMetadata?['time_passed'], isNull);

    await storage!.realismSettings.setPassageOfTimeDefault(true);
    expect(chat!.timeService.passageOfTimeEnabled, isTrue);

    await chat!.sendMessage('Still there?');
    await drainTurn();
    expect(chat!.timeService.clock.difference(origin).inMinutes, 30);
    expect(lastBot().activeMetadata?['time_passed'], '30 min');
  });

  test(
    '1:1 quoted continuous_instant string fails closed to the floor',
    () async {
      await boot(llm: _QuotedInstantLlm());
      final before = chat!.timeService.clock;

      await chat!.sendMessage('How are you?');
      await drainTurn();

      expect(
        chat!.timeService.clock.difference(before).inMinutes,
        2,
        reason:
            'only a real JSON boolean true is same-moment. '
            '"continuous_instant":"true" is garbage — floor, not freeze',
      );
      expect(lastBot().activeMetadata?['time_passed'], '2 min');
      expect(bars(), _carmenNeeds);
    },
  );

  test('1:1 negative minutes_elapsed fails closed to the floor', () async {
    await boot(llm: _NegativeMinuteLlm());
    final before = chat!.timeService.clock;

    await chat!.sendMessage('How are you?');
    await drainTurn();

    expect(chat!.timeService.clock.difference(before).inMinutes, 2);
    expect(lastBot().activeMetadata?['time_passed'], '2 min');
    expect(bars(), _carmenNeeds);
  });

  test('1:1 time-eval throw uses the same floor as a missing key', () async {
    await boot(llm: _ThrowingTimeLlm());
    final before = chat!.timeService.clock;

    await chat!.sendMessage('How are you?');
    await drainTurn();

    expect(
      chat!.timeService.clock.difference(before).inMinutes,
      2,
      reason: 'every send-path failure is conversationalFloorMinutes, not 5',
    );
    expect(lastBot().activeMetadata?['time_passed'], '2 min');
  });

  test(
    '1:1 regen restamps time_passed and does not invent clock wear',
    () async {
      await boot();
      final origin = chat!.timeService.clock;
      await chat!.sendMessage('How are you?');
      await drainTurn();
      expect(bars(), _carmenNeeds);
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
      expect(
        chat!.timeService.clock.difference(origin).inMinutes,
        30,
        reason: 'send path must stay the working +30 contract',
      );
      final firstSwipe = lastBot().swipeIndex;
      final firstChip = lastBot().activeMetadata?['time_passed'];

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
      expect(
        chat!.timeService.clock.difference(origin).inMinutes,
        30,
        reason:
            'regen rewinds to story_clock_before then re-applies. '
            'Live Mac 87d79eba: merge rollback left the sidebar at Day 1 9:00.',
      );

      for (var i = 0; i < 2; i++) {
        await chat!.regenerateLastMessage();
        await drainTurn();
      }
      expect(
        chat!.timeService.clock.difference(origin).inMinutes,
        30,
        reason: 'three regens must not accumulate minutes',
      );

      final regenIndex = chat!.messages.indexOf(lastBot());
      await chat!.swipeMessage(regenIndex, -1);
      await drainTurn();
      expect(bars(), _carmenNeeds);
      expect(
        lastBot().activeMetadata?['time_passed'],
        firstChip,
        reason: 'older swipe keeps its own time chip',
      );
    },
  );

  test(
    '1:1 leftover abort under regen settling hold still advances the clock',
    () async {
      await boot();
      final origin = chat!.timeService.clock;
      await chat!.sendMessage('How are you?');
      await drainTurn();
      expect(chat!.timeService.clock.difference(origin).inMinutes, 30);

      // Yield's fast path used to leave this latched. Regen then holds
      // settling, so generate's finally never cleared it, and postgen
      // skipped clock + stamp (live Carmen regen, no [Realism:Time]).
      chat!.debugRequestPostGenAbort();
      await chat!.regenerateLastMessage();
      await drainTurn();

      expect(
        chat!.timeService.clock.difference(origin).inMinutes,
        30,
        reason:
            'abort leftover from a prior yield must not freeze regen. '
            'Rewind, re-eval, apply the same 30, no accumulation.',
      );
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
      await boot(globalRealism: false, cardRealism: false, needsEnabled: false);
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
