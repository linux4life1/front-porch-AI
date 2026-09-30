// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E: rung 4 applies to a greeting-as-tip (reverses b2a83292's
// strip in _resolveVisibleAfter). Own dayCount>1 opens at that
// day, not live. Live wins only when the greeting has no own
// after, no chip, no real snap and no dayCount above 1. A
// today's-date seed-leak snap is not a real snap.
//
// Open of a planted greeting runs backfill AFTER the first
// applyTip. backfill calls resolveSlotAfter (no strip) and
// writes a pair, so a pin that observes the post-backfill
// clock never sees the strip. The Day 5 open pin marks
// clock_backfill_done and stores dayCount only inside
// realism_state (the _captureRealismState shape) so hydrate
// ends on _resolveVisibleAfter.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show StoryClock, resolveSlotAfter;
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_greet_rung4_').path;
        }
        return null;
      });
}

const _startIso = '2026-06-28';
final _june28 = DateTime.utc(2026, 6, 28);
final _liveDay3 = DateTime.utc(2026, 6, 30, 16, 0);
final _liveLate = DateTime.utc(2026, 9, 25, 22, 30);
final _day5LiveTod = DateTime.utc(2026, 7, 2, 22, 30);

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'GreetRung4';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  ChatService? chat;

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

  Future<void> boot() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
      'passage_of_time_default': true,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    final storage = StorageService();
    final repo = CharacterRepository(db!, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db!),
            storage,
            WorldRepository(storage, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _SilentLlm();
    await storage.initialized;
    final nia = CharacterCard(
      name: 'Nia',
      firstMessage: 'Morning.',
      imagePath: '/tmp/nia-greet-rung4.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
      ),
    );
    await repo.addCharacter(nia);
    await chat!.setActiveCharacter(nia);
    await drain();
  }

  Future<void> plant({
    required Map<String, dynamic>? greetingMeta,
    required String clock,
    String start = _startIso,
    int day = 3,
    String tod = 'afternoon',
  }) async {
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    await db!.deleteMessagesForSession(sid);
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'gr0',
        sessionId: sid,
        position: 0,
        sender: 'Nia',
        isUser: false,
        swipes: const Value('["Morning."]'),
        metadata: Value(greetingMeta == null ? null : jsonEncode(greetingMeta)),
      ),
    );
    await db!.patchSession(
      SessionsCompanion(
        id: Value(sid),
        passageOfTimeEnabled: const Value(true),
        passageOfTimeGateMigrated: const Value(true),
        storyClock: Value(clock),
        storyStartDate: Value(start),
        timeOfDay: Value(tod),
        dayCount: Value(day),
      ),
    );
    await chat!.reloadCurrentSession();
    await drain();
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('resolver: greeting-as-tip dayCount 5 is Day 5, not live', () {
    final hit = resolveSlotAfter(
      {
        'realism_state': {'dayCount': 5},
        'story_day': 5,
      },
      isTip: true,
      greetingIsTip: true,
      isGreeting: true,
      liveClock: _liveLate,
      startDate: _june28,
    );
    expect(hit, _day5LiveTod);
    expect(hit, isNot(_liveLate));
  });

  test('resolver: greeting-as-tip with nothing takes live', () {
    final hit = resolveSlotAfter(
      {},
      isTip: true,
      greetingIsTip: true,
      isGreeting: true,
      liveClock: _liveLate,
      startDate: _june28,
    );
    expect(hit, _liveLate);
  });

  test('resolver: today-seed greeting snap is ignored; takes live', () {
    final today = StoryClock.todayAnchor();
    final leak = DateTime.utc(today.year, today.month, today.day, 9, 0);
    final hit = resolveSlotAfter(
      {
        'realism_state': {'storyClock': StoryClock.serializeClock(leak)},
      },
      isTip: true,
      greetingIsTip: true,
      isGreeting: true,
      liveClock: _liveDay3,
      startDate: _june28,
      greetingClock: leak,
    );
    expect(
      hit,
      _liveDay3,
      reason:
          'today-stamped greeting snap ($leak) is the seed leak, '
          'not a real snap; greeting-as-tip takes live',
    );
    expect(hit, isNot(leak));
  });

  test('open: greeting-as-tip dayCount 5 opens at Day 5, not live', () async {
    await boot();
    await plant(
      greetingMeta: {
        // Same keys _applyGreetingOpeningSeed writes onto
        // activeMetadata via _captureRealismState. Loaded
        // messages have empty swipeMetadata, so
        // activeMetadata == metadata. No stored pair.
        // clock_backfill_done stops backfill from writing
        // a Day-5 pair through resolveSlotAfter (no strip)
        // and hiding the _resolveVisibleAfter strip.
        'realism_state': {
          'affectionScore': 0,
          'trustLevel': 0,
          'dayCount': 5,
          'timeOfDay': 'night',
          'storyStartDate': _startIso,
        },
        'clock_backfill_done': true,
      },
      clock: StoryClock.serializeClock(_liveLate),
      day: 90,
      tod: 'night',
    );
    expect(
      chat!.timeService.clock,
      _day5LiveTod,
      reason:
          'rung 4 applies to greeting-as-tip; dayCount 5 from '
          '2026-06-28 at live TOD is 2026-07-02 22:30, not live '
          '${chat!.timeService.clock}',
    );
    expect(chat!.timeService.dayCount, 5);
    expect(chat!.timeService.clock, isNot(_liveLate));
  });

  test(
    'open: greeting-as-tip with nothing (no after/chip/snap/day>1) takes live',
    () async {
      await boot();
      await plant(
        greetingMeta: {
          'realism_state': {'dayCount': 1, 'timeOfDay': 'morning'},
        },
        clock: StoryClock.serializeClock(_liveDay3),
        day: 3,
      );
      expect(
        chat!.timeService.clock,
        _liveDay3,
        reason:
            'live wins only when greeting has no own after, no chip, '
            'no real snap and no dayCount above 1',
      );
    },
  );

  test(
    'open: today-seed greeting snap is ignored; greeting takes live',
    () async {
      await boot();
      final today = StoryClock.todayAnchor();
      final leak = DateTime.utc(today.year, today.month, today.day, 9, 0);
      await plant(
        greetingMeta: {
          'realism_state': {'storyClock': StoryClock.serializeClock(leak)},
        },
        clock: StoryClock.serializeClock(_liveDay3),
        day: 3,
      );
      expect(
        chat!.timeService.clock,
        _liveDay3,
        reason:
            'chat startDate 2026-06-28, snap stamped $leak (today) '
            'with no other own data is the seed leak — take live, '
            'do not freeze on the today stamp '
            '(actual ${chat!.timeService.clock})',
      );
      expect(StoryClock.dateOnly(chat!.timeService.clock), isNot(today));
    },
  );
}
