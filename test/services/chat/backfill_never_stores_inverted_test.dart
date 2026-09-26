// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Backfill never STORES an inverted pair. Reload/hydrate runs
// backfillSlotClocks, then every complete metadata pair is read
// DIRECTLY (not only the resolver). Legacy inverted writer pairs
// lift AFTER to BEFORE so the served clock matches the read
// clamp. Guess-write normalize keeps before <= after the same
// way. Live _writeSlotClock still keeps the after (named
// 07:30/07:30).

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show
        StoryClock,
        backfillSlotClocks,
        resolveSlotAfter,
        slotClockAfter,
        slotClockBefore;
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_bf_inverted_').path;
        }
        return null;
      });
}

const _needs = {
  'hunger': 80,
  'bladder': 80,
  'energy': 80,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

const _startIso = '2026-06-28';
const _d1_0010 = '2026-06-28T00:10:00.000Z';
const _d1_0900 = '2026-06-28T09:00:00.000Z';
const _d1_1600 = '2026-06-28T16:00:00.000Z';
const _d1_2000 = '2026-06-28T20:00:00.000Z';
const _d2_1400 = '2026-06-29T14:00:00.000Z';
const _d2_1600 = '2026-06-29T16:00:00.000Z';
const _d2_1700 = '2026-06-29T17:00:00.000Z';
const _d3_1430 = '2026-06-30T14:30:00.000Z';
const _wrongDay = '2026-09-01T14:30:00.000Z';
const _named0730 = '2026-06-28T07:30:00.000Z';
const _named0800 = '2026-06-28T08:00:00.000Z';

const _day1NineSnap = {
  'storyClock': _d1_0900,
  'storyStartDate': _startIso,
  'timeOfDay': 'morning',
  'dayCount': 1,
};

const _validPair = {
  'story_clock_before': _d1_0900,
  'story_clock_after': _d1_0900,
};

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SilentBackfillInverted';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
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

  Future<void> boot({String? storyStartTime}) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
      'passage_of_time_default': true,
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
          ..testLlmServiceOverride = _SilentLlm();
    await storage!.initialized;
    final nia = CharacterCard(
      name: 'Nia',
      firstMessage: 'Evening.',
      imagePath: '/tmp/nia-bf-inv.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        passageOfTimeEnabled: true,
        storyStartDate: _startIso,
        storyStartTime: storyStartTime,
        timeOfDay: storyStartTime == null ? 'morning' : 'evening',
        needsBaselineHunger: 80,
        needsBaselineBladder: 80,
        needsBaselineEnergy: 80,
        needsBaselineSocial: 80,
        needsBaselineFun: 80,
        needsBaselineHygiene: 80,
        needsBaselineComfort: 80,
      ),
    );
    await repo!.addCharacter(nia);
    await chat!.setActiveCharacter(nia);
    chat!.needsSimulation.restoreFromSnapshot({'vector': _needs});
    await drain();
  }

  Future<void> plant({
    required List<Map<String, Object?>> rows,
    required String clock,
    String start = _startIso,
    int day = 1,
    String tod = 'night',
  }) async {
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    await db!.deleteMessagesForSession(sid);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final meta = r['meta'] as Map<String, dynamic>?;
      final swipes = r['swipes'] as List<dynamic>?;
      await db!.insertMessage(
        MessagesCompanion.insert(
          id: 'inv$i',
          sessionId: sid,
          position: i,
          sender: r['sender'] as String,
          isUser: r['user'] as bool,
          swipes: Value(jsonEncode([r['text'] as String])),
          metadata: Value(meta == null ? null : jsonEncode(meta)),
          swipeMetadata: Value(swipes == null ? null : jsonEncode(swipes)),
        ),
      );
    }
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

  ChatMessage botAt(int i) => chat!.messages[i];

  void expectPairNotInverted(
    Map<String, dynamic>? slot, {
    required String site,
    required String which,
  }) {
    final before = slotClockBefore(slot);
    final after = slotClockAfter(slot);
    if (before == null || after == null) {
      fail('$site $which has no complete pair after backfill');
    }
    expect(
      before.isAfter(after),
      isFalse,
      reason:
          '$site $which must store before <= after; '
          'before=${StoryClock.serializeClock(before)} '
          'after=${StoryClock.serializeClock(after)}',
    );
  }

  /// Legacy writer repair lifts after to before. Reads the keys on
  /// [slot] (message.metadata), not the resolver. Served clock
  /// (live or resolved after) must stay that same before so a
  /// reload does not change what the user saw.
  void expectLiftedWriterPair(
    Map<String, dynamic>? slot, {
    required String iso,
    required DateTime served,
    required String site,
  }) {
    expect(
      slot?['story_clock_before'],
      iso,
      reason: '$site stored story_clock_before',
    );
    expect(
      slot?['story_clock_after'],
      iso,
      reason: '$site stored story_clock_after (lift after to before)',
    );
    expect(
      resolveSlotAfter(
        slot,
        isTip: true,
        liveClock: chat!.timeService.clock,
        startDate: chat!.timeService.startDate,
      ),
      served,
      reason: '$site resolved after must stay $iso',
    );
    expect(
      chat!.timeService.clock,
      served,
      reason: '$site live must stay $iso after reload',
    );
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    ':844 shape: chip-derived before is not inverted; live stays 00:10',
    () async {
      await boot();
      final lastMeta = {
        'realism_state': {
          ..._day1NineSnap,
          'storyClock': _d1_0010,
          'dayCount': 1,
          'timeOfDay': 'night',
        },
        'time_passed': '30 min',
      };
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Evening.',
            'meta': {'realism_state': _day1NineSnap},
            'swipes': [
              {'realism_state': _day1NineSnap},
            ],
          },
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Almost midnight.',
            'meta': lastMeta,
            'swipes': [Map<String, dynamic>.from(lastMeta)],
          },
        ],
        clock: _d1_0010,
        tod: 'night',
        day: 1,
      );
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 28, 0, 10),
        reason:
            'untouched :844 chat must keep live 06-28 00:10; '
            'reload must not jump',
      );
      final tip = botAt(1);
      expectPairNotInverted(
        tip.metadata,
        site: 'guess write :438 (chip time_passed, :844 shape)',
        which: 'metadata',
      );
      expectPairNotInverted(
        tip.swipeMetadata.first,
        site: 'guess write :380 (chip time_passed, :844 shape)',
        which: 'swipe[0]',
      );
    },
  );

  test(
    'repairInvertedPair :310 collapses a non-writer inverted pair',
    () async {
      await boot();
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Hi.',
            'meta': Map<String, dynamic>.from(_validPair),
            'swipes': [Map<String, dynamic>.from(_validPair)],
          },
          {'sender': 'You', 'user': true, 'text': 'Hey.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Rewound.',
            'meta': Map<String, dynamic>.from(_validPair),
            'swipes': [
              {'story_clock_before': _d1_1600, 'story_clock_after': _d1_0900},
            ],
          },
          {'sender': 'You', 'user': true, 'text': 'And.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Tip.',
            'meta': {
              'story_clock_before': _d1_1600,
              'story_clock_after': _d1_1600,
            },
          },
        ],
        clock: _d1_1600,
        tod: 'afternoon',
      );
      expectPairNotInverted(
        botAt(2).swipeMetadata.first,
        site: 'repairInvertedPair :310',
        which: 'swipe[0]',
      );
    },
  );

  test('chip time_passed inverted pair is not stored inverted', () async {
    await boot();
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Hi.',
          'meta': Map<String, dynamic>.from(_validPair),
        },
        {'sender': 'You', 'user': true, 'text': 'Hey.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Chip passed.',
          'meta': {
            'story_clock_before': _d1_1600,
            'story_clock_after': _d1_0900,
            'time_passed': '30 min',
          },
        },
      ],
      clock: _d1_1600,
      tod: 'afternoon',
    );
    expectLiftedWriterPair(
      botAt(2).metadata,
      iso: _d1_1600,
      served: DateTime.utc(2026, 6, 28, 16, 0),
      site: 'repairInvertedPair lift (time_passed writer)',
    );
  });

  test('chip time_nudged inverted pair is not stored inverted', () async {
    await boot();
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Hi.',
          'meta': Map<String, dynamic>.from(_validPair),
        },
        {'sender': 'You', 'user': true, 'text': 'Hey.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Nudged.',
          'meta': {
            'story_clock_before': _d1_1600,
            'story_clock_after': _d1_0900,
            'time_nudged': true,
          },
        },
      ],
      clock: _d1_1600,
      tod: 'afternoon',
    );
    expectLiftedWriterPair(
      botAt(2).metadata,
      iso: _d1_1600,
      served: DateTime.utc(2026, 6, 28, 16, 0),
      site: 'repairInvertedPair lift (time_nudged writer)',
    );
  });

  test('chip time_skip_to inverted pair is not stored inverted', () async {
    await boot();
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Hi.',
          'meta': Map<String, dynamic>.from(_validPair),
        },
        {'sender': 'You', 'user': true, 'text': 'Hey.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Skip.',
          'meta': {
            'story_clock_before': _d1_1600,
            'story_clock_after': _d1_0900,
            'time_skip_to': '09:00',
          },
        },
      ],
      clock: _d1_1600,
      tod: 'afternoon',
    );
    expectLiftedWriterPair(
      botAt(2).metadata,
      iso: _d1_1600,
      served: DateTime.utc(2026, 6, 28, 16, 0),
      site: 'repairInvertedPair lift (time_skip_to writer)',
    );
  });

  test('named-time writer pair is not stored inverted', () async {
    await boot();
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Hi.',
          'meta': Map<String, dynamic>.from(_validPair),
        },
        {'sender': 'You', 'user': true, 'text': 'Hey.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': "It's 7:30.",
          'meta': {
            'story_clock_before': _named0800,
            'story_clock_after': _named0730,
            'clock_from_writer': true,
          },
        },
      ],
      clock: _named0800,
      tod: 'morning',
    );
    expectLiftedWriterPair(
      botAt(2).metadata,
      iso: _named0800,
      served: DateTime.utc(2026, 6, 28, 8, 0),
      site: 'repairInvertedPair lift (named clock_from_writer)',
    );
  });

  test(
    'guess-write lifts after to a later stored before (Day 2, not the tip)',
    () {
      // No boot — clear the prior test's handles so tearDown
      // does not dispose an already-disposed ChatService.
      chat = null;
      db = null;
      // One pass, swipe slot distinct from metadata. Sharing the
      // map lets the metadata-loop repairInvertedPair hide a
      // guess-write invert on the same call.
      final start = DateTime.utc(2026, 6, 28);
      final live = DateTime.utc(2026, 6, 29, 17);
      final swipe = <String, dynamic>{
        'story_clock_before': _d2_1600,
        'realism_state': {
          'storyClock': _d2_1400,
          'storyStartDate': _startIso,
          'timeOfDay': 'afternoon',
          'dayCount': 2,
        },
      };
      final messages = [
        ChatMessage(
          text: 'Hi.',
          sender: 'Nia',
          isUser: false,
          metadata: Map<String, dynamic>.from(_validPair),
        ),
        ChatMessage(text: 'Hey.', sender: 'You', isUser: true),
        ChatMessage(
          text: 'Later before, earlier snap.',
          sender: 'Nia',
          isUser: false,
          metadata: Map<String, dynamic>.from(_validPair),
          swipeMetadata: [swipe],
        ),
        ChatMessage(text: 'And.', sender: 'You', isUser: true),
        ChatMessage(
          text: 'Tip.',
          sender: 'Nia',
          isUser: false,
          metadata: {
            'story_clock_before': _d2_1700,
            'story_clock_after': _d2_1700,
          },
        ),
      ];
      backfillSlotClocks(messages, liveClock: live, startDate: start);
      expect(
        swipe['story_clock_before'],
        _d2_1600,
        reason: 'guess-write keeps the stored before',
      );
      expect(
        swipe['story_clock_after'],
        _d2_1600,
        reason: 'guess-write lifts after to before (matches the clamp)',
      );
    },
  );

  test(
    'mid-chat legacy time_nudged lifts to 16:00/16:00; later pair untouched',
    () async {
      await boot();
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Hi.',
            'meta': Map<String, dynamic>.from(_validPair),
          },
          {'sender': 'You', 'user': true, 'text': 'Hey.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Nudged mid-chat.',
            'meta': {
              'story_clock_before': _d1_1600,
              'story_clock_after': _d1_0900,
              'time_nudged': true,
            },
          },
          {'sender': 'You', 'user': true, 'text': 'And.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Later tip.',
            'meta': {
              'story_clock_before': _d2_1700,
              'story_clock_after': _d2_1700,
            },
          },
        ],
        clock: _d2_1700,
        tod: 'afternoon',
        day: 2,
      );
      final mid = botAt(2).metadata;
      expect(mid?['story_clock_before'], _d1_1600);
      expect(
        mid?['story_clock_after'],
        _d1_1600,
        reason: 'mid-chat legacy time_nudged lifts after to before',
      );
      final later = botAt(4).metadata;
      expect(
        later?['story_clock_before'],
        _d2_1700,
        reason: 'later pair before must stay untouched',
      );
      expect(
        later?['story_clock_after'],
        _d2_1700,
        reason: 'later pair after must stay untouched',
      );
    },
  );

  test('wrong-greeting swipe :330 does not store inverted', () async {
    await boot(storyStartTime: '20:00');
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Evening.',
          'meta': <String, dynamic>{},
        },
        {'sender': 'You', 'user': true, 'text': 'Hey.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Swipe repair.',
          'meta': Map<String, dynamic>.from(_validPair),
          'swipes': [
            {
              'story_clock_before': _d1_2000,
              'story_clock_after': _d1_1600,
              'realism_state': {
                'storyClock': _d1_0900,
                'storyStartDate': _startIso,
                'timeOfDay': 'morning',
                'dayCount': 1,
              },
            },
          ],
        },
        {'sender': 'You', 'user': true, 'text': 'And.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Meta repair.',
          'meta': {
            'story_clock_before': _d1_2000,
            'story_clock_after': _d1_1600,
            'realism_state': {
              'storyClock': _d1_0900,
              'storyStartDate': _startIso,
              'timeOfDay': 'morning',
              'dayCount': 1,
            },
          },
          'swipes': [Map<String, dynamic>.from(_validPair)],
        },
        {'sender': 'You', 'user': true, 'text': 'Tip user.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Tip.',
          'meta': {
            'story_clock_before': _d1_2000,
            'story_clock_after': _d1_2000,
          },
        },
      ],
      clock: _d1_2000,
      tod: 'evening',
    );
    final swipe = botAt(2).swipeMetadata.first;
    final swipeBefore = StoryClock.parse(
      swipe?['story_clock_before'] as String?,
    );
    final swipeAfter = StoryClock.parse(swipe?['story_clock_after'] as String?);
    expect(swipeBefore, isNotNull, reason: ':330 swipe stored before');
    expect(swipeAfter, isNotNull, reason: ':330 swipe stored after');
    expect(
      swipeBefore!.isAfter(swipeAfter!),
      isFalse,
      reason:
          'wrong-greeting swipe :330 (evening card, morning snap) '
          'must store before <= after; '
          'before=${StoryClock.serializeClock(swipeBefore)} '
          'after=${StoryClock.serializeClock(swipeAfter)}',
    );
  });

  test('wrong-greeting metadata :393 does not store inverted', () async {
    await boot(storyStartTime: '20:00');
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Evening.',
          'meta': <String, dynamic>{},
        },
        {'sender': 'You', 'user': true, 'text': 'Hey.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Meta repair.',
          'meta': {
            'story_clock_before': _d1_2000,
            'story_clock_after': _d1_1600,
            'realism_state': {
              'storyClock': _d1_0900,
              'storyStartDate': _startIso,
              'timeOfDay': 'morning',
              'dayCount': 1,
            },
          },
          'swipes': [Map<String, dynamic>.from(_validPair)],
        },
        {'sender': 'You', 'user': true, 'text': 'Tip user.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Tip.',
          'meta': {
            'story_clock_before': _d1_2000,
            'story_clock_after': _d1_2000,
          },
        },
      ],
      clock: _d1_2000,
      tod: 'evening',
    );
    final meta = botAt(2).metadata;
    final metaBefore = StoryClock.parse(meta?['story_clock_before'] as String?);
    final metaAfter = StoryClock.parse(meta?['story_clock_after'] as String?);
    expect(metaBefore, isNotNull, reason: ':393 metadata stored before');
    expect(metaAfter, isNotNull, reason: ':393 metadata stored after');
    expect(
      metaBefore!.isAfter(metaAfter!),
      isFalse,
      reason:
          'wrong-greeting metadata :393 (evening card, morning snap) '
          'must store before <= after; '
          'before=${StoryClock.serializeClock(metaBefore)} '
          'after=${StoryClock.serializeClock(metaAfter)}',
    );
  });

  test('stale derived-day :352 and :409 do not store inverted', () async {
    await boot();
    final stale = {
      'story_clock_before': _wrongDay,
      'story_clock_after': _wrongDay,
      'clock_from_day_count': true,
      'story_day': 3,
      'realism_state': {'dayCount': 3, 'timeOfDay': 'afternoon'},
    };
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Hi.',
          'meta': Map<String, dynamic>.from(_validPair),
        },
        {'sender': 'You', 'user': true, 'text': 'Hey.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Swipe stale.',
          'meta': Map<String, dynamic>.from(_validPair),
          'swipes': [Map<String, dynamic>.from(stale)],
        },
        {'sender': 'You', 'user': true, 'text': 'And.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Meta stale.',
          'meta': Map<String, dynamic>.from(stale),
          'swipes': [Map<String, dynamic>.from(_validPair)],
        },
        {'sender': 'You', 'user': true, 'text': 'Tip user.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Tip.',
          'meta': {
            'story_clock_before': _d3_1430,
            'story_clock_after': _d3_1430,
          },
        },
      ],
      clock: _d3_1430,
      tod: 'afternoon',
      day: 3,
    );
    expectPairNotInverted(
      botAt(2).swipeMetadata.first,
      site: 'stale derived-day swipe :352',
      which: 'swipe[0]',
    );
    expectPairNotInverted(
      botAt(4).metadata,
      site: 'stale derived-day metadata :409',
      which: 'metadata',
    );
  });

  test('guess writes :380 and :438 do not store inverted', () async {
    await boot();
    await plant(
      rows: [
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Hi.',
          'meta': Map<String, dynamic>.from(_validPair),
        },
        {'sender': 'You', 'user': true, 'text': 'Hey.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Swipe guess.',
          'meta': Map<String, dynamic>.from(_validPair),
          'swipes': [
            {
              'time_passed': '30 min',
              'realism_state': {
                'storyClock': _d2_1400,
                'storyStartDate': _startIso,
                'timeOfDay': 'afternoon',
                'dayCount': 2,
              },
            },
          ],
        },
        {'sender': 'You', 'user': true, 'text': 'And.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Meta guess.',
          'meta': {
            'time_nudged': true,
            'realism_state': {
              'storyClock': _d2_1400,
              'storyStartDate': _startIso,
              'timeOfDay': 'afternoon',
              'dayCount': 2,
            },
          },
          'swipes': [Map<String, dynamic>.from(_validPair)],
        },
        {'sender': 'You', 'user': true, 'text': 'Skip.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Skip guess.',
          'meta': {
            'time_skip_to': '14:00',
            'realism_state': {
              'storyClock': _d2_1400,
              'storyStartDate': _startIso,
              'timeOfDay': 'afternoon',
              'dayCount': 2,
            },
          },
        },
        {'sender': 'You', 'user': true, 'text': 'Tip user.'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Tip.',
          'meta': {
            'story_clock_before': _d2_1400,
            'story_clock_after': _d2_1400,
          },
        },
      ],
      clock: _d2_1400,
      tod: 'afternoon',
      day: 2,
    );
    expectPairNotInverted(
      botAt(2).swipeMetadata.first,
      site: 'guess write :380 (chip time_passed)',
      which: 'swipe[0]',
    );
    expectPairNotInverted(
      botAt(4).metadata,
      site: 'guess write :438 (chip time_nudged)',
      which: 'metadata',
    );
    expectPairNotInverted(
      botAt(6).metadata,
      site: 'guess write :438 (chip time_skip_to)',
      which: 'metadata',
    );
  });
}
