// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One-path clock pins. Public ChatService API only so this file
// compiles on 97a8d165. Red there; green after backfill + tip.after.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_clk_hold_').path;
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
const _livedIso = '2026-06-29T16:37:00.000Z';
const _day1NineIso = '2026-06-28T09:00:00.000Z';
const _day1SixIso = '2026-06-28T18:00:00.000Z';
const _day3Iso = '2026-06-30T16:00:00.000Z';
const _day12Iso = '2026-07-09T16:00:00.000Z';
const _midnightIso = '2026-06-28T00:10:00.000Z';
const _preMidnightIso = '2026-06-27T23:40:00.000Z';

class _ScriptedLlm extends LLMService {
  int nextMinutes = 30;
  bool nextDay = false;
  String nextReply = '*Nia leans on the rail.*';
  bool cancelOnMinutes = false;
  bool throwOnEval = false;
  Future<void> Function()? cancel;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield nextReply;
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      if (throwOnEval) {
        throwOnEval = false;
        throw Exception('hold-spec eval throw');
      }
      yield '{"relationship_delta":0,"trust_delta":1,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
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
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      if (cancelOnMinutes) {
        cancelOnMinutes = false;
        await cancel?.call();
        return;
      }
      yield '{"minutes_elapsed": $nextMinutes, "new_day": $nextDay}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedHoldSpec';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('ChatService hold spec', () {
    AppDatabase? db;
    StorageService? storage;
    CharacterRepository? repo;
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

    Future<void> boot({bool porchLife = true}) async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'needs_sim_default': true,
        'passage_of_time_default': porchLife,
      });
      db = AppDatabase.forTesting();
      storage = StorageService();
      repo = CharacterRepository(db!, storage!);
      llm = _ScriptedLlm();
      chat =
          ChatService(
              KoboldService(storage!),
              UserPersonaService(db!),
              storage!,
              WorldRepository(storage!, db!),
            )
            ..setDatabase(db!)
            ..setCharacterRepository(repo!)
            ..testLlmServiceOverride = llm;
      llm.cancel = () => chat!.cancelRealismEval();
      await storage!.initialized;
      final nia = CharacterCard(
        name: 'Nia',
        firstMessage: 'Evening.',
        imagePath: '/tmp/nia-hold-clock.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          passageOfTimeEnabled: true,
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
      required String start,
      int day = 2,
      String tod = 'afternoon',
    }) async {
      await chat!.flushPendingSaves();
      final sid = chat!.currentSessionId!;
      await db!.deleteMessagesForSession(sid);
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final meta = r['meta'] as Map<String, dynamic>?;
        final swipes =
            (r['swipes'] as List<dynamic>?)?.cast<String>() ??
            [r['text'] as String];
        final swipeMeta = r['swipeMeta'] as List<dynamic>?;
        await db!.insertMessage(
          MessagesCompanion.insert(
            id: 'h$i',
            sessionId: sid,
            position: i,
            sender: r['sender'] as String,
            isUser: r['user'] as bool,
            characterId: Value(r['cid'] as String?),
            swipes: Value(jsonEncode(swipes)),
            swipeIndex: Value(r['idx'] as int? ?? 0),
            metadata: Value(meta == null ? null : jsonEncode(meta)),
            swipeMetadata: Value(
              swipeMeta == null ? null : jsonEncode(swipeMeta),
            ),
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

    Future<void> enterGroup({
      required String groupId,
      required List<({String id, String name})> members,
      String? avatarFilename,
      bool needsEnabled = true,
    }) async {
      final blobs = buildGroupRealismBlobs(
        seeds: {for (final m in members) m.id: defaultGroupMemberRealismSeed()},
        needsEnabled: needsEnabled,
        timeOfDay: 'afternoon',
        dayCount: 3,
      );
      await db!.insertGroup(
        GroupsCompanion.insert(
          id: groupId,
          name: 'The Porch',
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      for (final m in members) {
        await db!.insertGroupMember(
          GroupMembersCompanion.insert(
            id: m.id,
            groupId: groupId,
            name: m.name,
            firstMessage: const Value('Evening.'),
            avatarFilename: avatarFilename == null
                ? const Value.absent()
                : Value('$avatarFilename${m.id}.png'),
          ),
        );
      }
      await chat!.setActiveGroup(
        GroupChat(
          id: groupId,
          name: 'The Porch',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage!, db!),
      );
      await drain();
    }

    tearDown(() async {
      chat?.dispose();
      await db?.close();
    });

    test('H1: swipe to a dayCount-only snap keeps the live clock', () async {
      await boot();
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Morning.',
            'swipes': ['Day-count only', 'Stamped later'],
            'idx': 1,
            'meta': {
              'story_clock_before': _day12Iso,
              'story_clock_after': _day12Iso,
            },
            'swipeMeta': [
              {
                'realism_state': {'dayCount': 1, 'timeOfDay': 'morning'},
              },
              {'story_clock_before': _day12Iso, 'story_clock_after': _day12Iso},
            ],
          },
        ],
        clock: _day12Iso,
        start: _startIso,
        day: 12,
      );
      expect(chat!.timeService.clock, DateTime.utc(2026, 7, 9, 16, 0));
      await chat!.selectSwipe(0, 0);
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 7, 9, 16, 0),
        reason: 'dayCount-only snap is not a clock; keep live Day 12',
      );
    });

    test('N1: guest-below swipe to frozen slot 0 keeps live plus 0', () async {
      await boot();
      Map<String, dynamic> frozen() => {
        'realism_state': {
          'storyClock': _day1NineIso,
          'storyStartDate': _startIso,
          'timeOfDay': 'morning',
          'dayCount': 1,
        },
      };
      Map<String, dynamic> lived(String after) => {
        'story_clock_before': '2026-06-30T16:00:00.000Z',
        'story_clock_after': after,
        'realism_state': {'storyClock': after, 'storyStartDate': _startIso},
      };
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Hi.',
            'swipes': ['Frozen greeting', 'Lived-in'],
            'idx': 1,
            'meta': frozen(),
            'swipeMeta': [frozen(), lived('2026-06-30T16:00:00.000Z')],
          },
          {
            'sender': 'Gita',
            'user': false,
            'cid': 'guest-gita',
            'text': 'Ten minutes later.',
            'meta': {
              'story_clock_before': '2026-06-30T16:00:00.000Z',
              'story_clock_after': '2026-06-30T16:10:00.000Z',
            },
          },
        ],
        clock: '2026-06-30T16:10:00.000Z',
        start: _startIso,
        day: 3,
      );
      expect(chat!.timeService.clock, DateTime.utc(2026, 6, 30, 16, 10));
      await chat!.selectSwipe(0, 0);
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 30, 16, 10),
        reason: 'frozen slot 0 must not delta a guest tick back to Day 1',
      );
    });

    test('evening greeting swipe and fork keep the live clock', () async {
      await boot();
      const eveningSnap = {
        'storyClock': _day1SixIso,
        'storyStartDate': _startIso,
        'timeOfDay': 'evening',
        'dayCount': 1,
      };
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Evening.',
            'meta': {'realism_state': eveningSnap},
          },
          {'sender': 'You', 'user': true, 'text': 'Hi.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Still here.',
            'meta': {'realism_state': eveningSnap},
          },
        ],
        clock: _day3Iso,
        start: _startIso,
        day: 3,
      );
      await chat!.selectSwipe(0, 0);
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 30, 16, 0),
        reason: 'Day 1 18:00 greeting snap is frozen, not a 09:00-only match',
      );
      await chat!.forkFromMessage(0);
      await drain();
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 30, 16, 0),
        reason: 'fork of an evening greeting must keep the lived-in clock',
      );
    });

    test('group Carmen fork keeps the live clock', () async {
      await boot();
      await enterGroup(
        groupId: 'grp-carmen',
        members: [(id: 'mem-nia', name: 'Nia'), (id: 'mem-bea', name: 'Bea')],
        avatarFilename: '',
      );
      const snap = {
        'timeOfDay': 'morning',
        'dayCount': 1,
        'storyClock': _day1NineIso,
        'storyStartDate': _startIso,
      };
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'cid': 'mem-nia',
            'text': 'Morning.',
            'meta': {'realism_state': snap},
          },
          {'sender': 'You', 'user': true, 'text': 'Hi.'},
          {
            'sender': 'Bea',
            'user': false,
            'cid': 'mem-bea',
            'text': 'Still here.',
            'meta': {'realism_state': snap},
          },
        ],
        clock: _day3Iso,
        start: _startIso,
        day: 3,
      );
      await chat!.forkFromMessage(2);
      await drain();
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 30, 16, 0),
        reason: 'group Carmen fork must never seed Day 1 09:00',
      );
    });

    test('re-anchor +10 on v1.4, then swipe and fork at pos 6', () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      final dir = Directory.systemTemp.createTempSync('fpai_hold_v14_');
      final work = File('${dir.path}/library.db');
      File('test/fixtures/v14_upgrade/library.db').copySync(work.path);
      db = AppDatabase.forReunification(work);
      await db!.ensureSchemaIsRepaired();
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
            ..setCharacterRepository(repo!);
      await storage!.initialized;
      await repo!.loadCharacters();
      final card = repo!.characters.firstWhere((c) => c.name == 'HostOn');
      await chat!.setActiveCharacter(card);
      await chat!.loadSession('1790314131886');
      await drain();
      expect(chat!.timeService.clock, DateTime.utc(2026, 9, 25, 10, 30));
      final oldStart = chat!.timeService.startDate;
      final sid = chat!.currentSessionId!;
      const pagedAfter = '2026-09-25T09:00:00.000Z';
      await db!.insertMessage(
        MessagesCompanion.insert(
          id: 'hold-paged',
          sessionId: sid,
          position: 80,
          sender: 'HostOn',
          isUser: false,
          swipes: Value(jsonEncode(['Paged.'])),
          metadata: Value(
            jsonEncode({
              'story_clock_before': pagedAfter,
              'story_clock_after': pagedAfter,
            }),
          ),
        ),
      );
      final aliasIdx = chat!.messages.indexWhere(
        (m) => !m.isUser && m.swipeMetadata.every((s) => s == null),
      );
      await chat!.setStoryStartDate(oldStart.add(const Duration(days: 10)));
      expect(
        chat!.timeService.startDate,
        oldStart.add(const Duration(days: 10)),
      );
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 10, 5, 10, 30),
        reason: 're-anchor slides the live clock once, not twice',
      );
      final paged = await db!.getMessagesForSession(sid);
      final pagedRow = paged.firstWhere((r) => r.id == 'hold-paged');
      final pagedMeta = jsonDecode(pagedRow.metadata!) as Map<String, dynamic>;
      expect(
        pagedMeta['story_clock_after'],
        '2026-10-05T09:00:00.000Z',
        reason: 'DB-only / paged rows must shift with the session',
      );
      if (aliasIdx >= 0) {
        final raw =
            chat!.messages[aliasIdx].activeMetadata?['story_clock_after'];
        if (raw is String) {
          final after = DateTime.parse(raw);
          expect(
            after.difference(DateTime.parse(pagedAfter)).inDays.abs(),
            anyOf(0, 10),
          );
        }
      }
      await chat!.selectSwipe(6, 1);
      await chat!.selectSwipe(6, 0);
      expect(chat!.timeService.clock, DateTime.utc(2026, 10, 5, 10, 30));
      await chat!.forkFromMessage(6);
      await drain();
      expect(chat!.timeService.clock, DateTime.utc(2026, 10, 5, 10, 30));
      expect(
        chat!.timeService.startDate,
        oldStart.add(const Duration(days: 10)),
      );
      dir.deleteSync(recursive: true);
    });

    test(
      'nudge writes through sync; user tail does not snapshot a guest',
      () async {
        await boot();
        await plant(
          rows: [
            {
              'sender': 'Gita',
              'user': false,
              'cid': 'guest-gita',
              'text': 'Passing through.',
              'meta': <String, dynamic>{},
            },
            {'sender': 'You', 'user': true, 'text': 'Later.'},
          ],
          clock: _livedIso,
          start: _startIso,
        );
        final guest = chat!.messages.firstWhere((m) => m.sender == 'Gita');
        final user = chat!.messages.last;
        expect(guest.activeMetadata?['realism_state'], isNull);
        await chat!.nudgeTimePeriod(1);
        expect(user.metadata?['realism_state'], isNull);
        expect(user.activeMetadata?['realism_state'], isNull);
        expect(
          guest.activeMetadata?['realism_state'],
          isNull,
          reason: 'nudge must not insert a snapshot on a stamp-less guest',
        );
        expect(guest.activeMetadata?['time_nudged'], isTrue);
        expect(guest.activeMetadata?['story_clock_after'], isNotNull);
      },
    );

    test('Next morning chip survives the commit stamp', () async {
      await boot();
      await chat!.setStoryClock(DateTime.utc(2026, 6, 29, 16, 37));
      llm.nextMinutes = 30;
      llm.nextDay = true;
      await chat!.sendMessage('See you in the morning.');
      await drain();
      final last = chat!.messages.lastWhere((m) => !m.isUser);
      expect(
        last.activeMetadata?['time_passed'],
        'Next morning',
        reason: 'commit must keep the beat label, not clock-minus-before hours',
      );
    });

    test('Continue after a nudge keeps the chip', () async {
      await boot();
      llm.nextMinutes = 30;
      await chat!.sendMessage('Hey.');
      await drain();
      final last = chat!.messages.lastWhere((m) => !m.isUser);
      expect(last.activeMetadata?['time_passed'], '30 min');
      await chat!.nudgeTimePeriod(1);
      llm.nextReply = ' And she stays on the rail.';
      await chat!.continueGeneration();
      await drain();
      expect(
        last.activeMetadata?['time_passed'],
        '30 min',
        reason: 'Continue must not recompute the chip as same moment',
      );
    });

    test(
      'abort during regen post-gen: clock == before, after == before, no chip',
      () async {
        await boot();
        llm.nextMinutes = 30;
        await chat!.sendMessage('Hey.');
        await drain();
        final last = chat!.messages.lastWhere((m) => !m.isUser);
        final beforeIso = last.activeMetadata?['story_clock_before'] as String;
        llm.cancelOnMinutes = true;
        await chat!.regenerateLastMessage();
        await drain();
        expect(chat!.timeService.clock, DateTime.parse(beforeIso));
        expect(last.activeMetadata?['story_clock_after'], beforeIso);
        expect(last.activeMetadata?['time_passed'], isNull);
        expect(
          chat!.guestActivityStatus,
          contains('Reply kept. Scene time and needs weren\'t updated.'),
        );
      },
    );

    test(
      'guest-below swipe from an unresolvable slot keeps the guest tick',
      () async {
        await boot();
        const gAfter = '2026-06-29T10:40:00.000Z';
        await plant(
          rows: [
            {
              'sender': 'Nia',
              'user': false,
              'text': 'Hi.',
              'swipes': ['Bare', 'Stamped'],
              'idx': 0,
              'meta': {
                'realism_state': {'dayCount': 2, 'timeOfDay': 'morning'},
              },
              'swipeMeta': [
                {
                  'realism_state': {'dayCount': 2, 'timeOfDay': 'morning'},
                },
                {
                  'story_clock_before': '2026-06-29T10:00:00.000Z',
                  'story_clock_after': '2026-06-29T10:30:00.000Z',
                },
              ],
            },
            {
              'sender': 'Gita',
              'user': false,
              'cid': 'guest-gita',
              'text': 'Ten minutes later.',
              'meta': {
                'story_clock_before': '2026-06-29T10:30:00.000Z',
                'story_clock_after': gAfter,
              },
            },
          ],
          clock: gAfter,
          start: _startIso,
        );
        await chat!.selectSwipe(0, 1);
        expect(
          chat!.timeService.clock,
          DateTime.utc(2026, 6, 29, 10, 40),
          reason: 'unresolvable previous slot must not absolute-apply 10:30',
        );
      },
    );

    test(
      'lite regen with Porch Life off stamps no after and no chip',
      () async {
        await boot(porchLife: false);
        await chat!.setPassageOfTimeEnabled(false);
        final guest = CharacterCard(
          name: 'Riley',
          firstMessage: 'Hi.',
          imagePath: '/tmp/riley-hold-guest.png',
          frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
        );
        await repo!.addCharacter(guest);
        await chat!.joinSceneGuest(guest);
        await drain();
        await chat!.speakGuestNow(
          chat!.sceneGuestCards.firstWhere((c) => c.name == 'Riley'),
        );
        await drain();
        final last = chat!.messages.lastWhere((m) => m.sender == 'Riley');
        expect(last.activeMetadata?['story_clock_after'], isNull);
        expect(last.activeMetadata?['time_passed'], isNull);
      },
    );

    test('K5 throw path restores the clock and start date', () async {
      await boot();
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Greeting.',
            'meta': {'realism_state': 'broken'},
          },
          {'sender': 'You', 'user': true, 'text': 'Hi.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Night.',
            'meta': {
              'story_clock_before': '2026-06-29T16:07:00.000Z',
              'story_clock_after': _livedIso,
              'realism_state': {
                'storyClock': _livedIso,
                'storyStartDate': _startIso,
              },
            },
          },
        ],
        clock: _livedIso,
        start: _startIso,
      );
      expect(chat!.timeService.clock, DateTime.utc(2026, 6, 29, 16, 37));
      try {
        await chat!.regenerateLastMessage();
      } catch (_) {}
      await drain();
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 29, 16, 37),
        reason: 'throw between capture and merge must restore the live clock',
      );
      expect(chat!.timeService.startDate, DateTime.utc(2026, 6, 28));
    });

    test('nudge then tail delete follows the new tip after', () async {
      await boot();
      llm.nextMinutes = 30;
      await chat!.sendMessage('Hey.');
      await drain();
      await chat!.nudgeTimePeriod(1);
      final greeting = chat!.messages.firstWhere((m) => !m.isUser);
      chat!.deleteMessage(chat!.messages.lastIndexWhere((m) => !m.isUser));
      await drain();
      final greetingAfter = greeting.activeMetadata?['story_clock_after'];
      expect(
        chat!.timeService.clock,
        DateTime.parse(greetingAfter as String),
        reason: 'tail delete reads the new visible tip after, not the nudge',
      );
    });

    test(
      'throw across Day-1 midnight restores 00:10, day 1, start 6/28',
      () async {
        await boot();
        await plant(
          rows: [
            {
              'sender': 'Nia',
              'user': false,
              'text': 'Greeting.',
              'meta': {'realism_state': 'broken'},
            },
            {'sender': 'You', 'user': true, 'text': 'Hi.'},
            {
              'sender': 'Nia',
              'user': false,
              'text': 'Late.',
              'meta': {
                'story_clock_before': _preMidnightIso,
                'story_clock_after': _midnightIso,
                'realism_state': {
                  'storyClock': _midnightIso,
                  'storyStartDate': _startIso,
                },
              },
            },
          ],
          clock: _midnightIso,
          start: _startIso,
          day: 1,
          tod: 'night',
        );
        expect(chat!.timeService.clock, DateTime.utc(2026, 6, 28, 0, 10));
        expect(chat!.timeService.dayCount, 1);
        try {
          await chat!.regenerateLastMessage();
        } catch (_) {}
        await drain();
        expect(chat!.timeService.clock, DateTime.utc(2026, 6, 28, 0, 10));
        expect(chat!.timeService.dayCount, 1);
        expect(chat!.timeService.startDate, DateTime.utc(2026, 6, 28));
      },
    );

    test('new swipes pin per-slot after and shared before', () async {
      await boot();
      llm.nextMinutes = 30;
      await chat!.sendMessage('Hey.');
      await drain();
      final last = chat!.messages.lastWhere((m) => !m.isUser);
      final beforeIso = last.activeMetadata?['story_clock_before'] as String;
      final before = DateTime.parse(beforeIso);
      llm.nextMinutes = 5;
      await chat!.regenerateLastMessage();
      await drain();
      expect(
        DateTime.parse(last.swipeMetadata[0]?['story_clock_after'] as String),
        before.add(const Duration(minutes: 30)),
      );
      expect(
        DateTime.parse(last.swipeMetadata[1]?['story_clock_after'] as String),
        before.add(const Duration(minutes: 5)),
      );
      for (final slot in last.swipeMetadata) {
        expect(slot?['story_clock_before'], beforeIso);
      }
      expect(last.metadata?['story_clock_before'], beforeIso);
    });

    test('mid-chat bot delete leaves the clock unchanged', () async {
      await boot();
      const snap = {
        'storyClock': _day1NineIso,
        'storyStartDate': _startIso,
        'timeOfDay': 'morning',
        'dayCount': 1,
      };
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'G.',
            'meta': {'realism_state': snap},
          },
          {'sender': 'You', 'user': true, 'text': '1'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Mid.',
            'meta': {'realism_state': snap},
          },
          {'sender': 'You', 'user': true, 'text': '2'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Tip.',
            'meta': {
              'story_clock_before': _day3Iso,
              'story_clock_after': _day3Iso,
              'realism_state': {
                'storyClock': _day3Iso,
                'storyStartDate': _startIso,
              },
            },
          },
        ],
        clock: _day3Iso,
        start: _startIso,
        day: 3,
      );
      expect(chat!.messages, hasLength(5));
      chat!.deleteMessage(2);
      await drain();
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 30, 16, 0),
        reason: 'mid-chat delete must not apply a frozen greeting snap',
      );
    });

    test('group non-tail delete leaves the clock unchanged', () async {
      await boot();
      await enterGroup(
        groupId: 'grp-del',
        members: [(id: 'mem-nia', name: 'Nia'), (id: 'mem-bea', name: 'Bea')],
        avatarFilename: '',
      );
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'cid': 'mem-nia',
            'text': 'First.',
            'meta': {
              'realism_state': {
                'storyClock': _livedIso,
                'storyStartDate': _startIso,
                'affectionScore': 40,
              },
            },
          },
          {
            'sender': 'Bea',
            'user': false,
            'cid': 'mem-bea',
            'text': 'Second.',
            'meta': {
              'realism_state': {
                'storyClock': _day3Iso,
                'storyStartDate': _startIso,
                'affectionScore': 50,
              },
            },
          },
          {
            'sender': 'Nia',
            'user': false,
            'cid': 'mem-nia',
            'text': 'Tip.',
            'meta': {
              'story_clock_after': _day3Iso,
              'realism_state': {
                'storyClock': _day3Iso,
                'storyStartDate': _startIso,
                'affectionScore': 55,
              },
            },
          },
        ],
        clock: _day3Iso,
        start: _startIso,
        day: 3,
      );
      chat!.deleteMessage(1);
      await drain();
      expect(
        chat!.timeService.clock,
        DateTime.utc(2026, 6, 30, 16, 0),
        reason: 'group speaker rollback must not move the chat clock',
      );
    });

    test('K7 mid-history fork keeps the exact lived-in clock', () async {
      await boot();
      const snap = {
        'timeOfDay': 'morning',
        'dayCount': 1,
        'storyClock': _day1NineIso,
        'storyStartDate': _startIso,
      };
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Morning.',
            'meta': {'realism_state': snap},
          },
          {'sender': 'You', 'user': true, 'text': 'Hi.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Later.',
            'meta': {'realism_state': snap},
          },
          {'sender': 'You', 'user': true, 'text': 'And.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Tip.',
            'meta': {'realism_state': snap},
          },
        ],
        clock: _day3Iso,
        start: _startIso,
        day: 3,
      );
      await chat!.forkFromMessage(2);
      await drain();
      expect(chat!.timeService.clock, DateTime.utc(2026, 6, 30, 16, 0));
    });

    test('real guest swipe round trip follows each slot after', () async {
      await boot();
      await chat!.setStoryClock(DateTime.utc(2026, 6, 29, 16, 37));
      final guest = CharacterCard(
        name: 'Riley',
        firstMessage: 'Hi.',
        imagePath: '/tmp/riley-hold-swipe.png',
        frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
      );
      await repo!.addCharacter(guest);
      await chat!.joinSceneGuest(guest);
      await drain();
      llm.nextMinutes = 30;
      await chat!.speakGuestNow(
        chat!.sceneGuestCards.firstWhere((c) => c.name == 'Riley'),
      );
      await drain();
      final idx = chat!.messages.lastIndexWhere((m) => m.sender == 'Riley');
      final first = chat!.timeService.clock;
      llm.nextMinutes = 5;
      await chat!.regenerateLastMessage();
      await drain();
      final second = chat!.timeService.clock;
      expect(second, isNot(first));
      await chat!.selectSwipe(idx, 0);
      expect(chat!.timeService.clock, first);
      await chat!.selectSwipe(idx, 1);
      expect(chat!.timeService.clock, second);
    });

    test('null-avatarFilename group member still has a Needs vector', () async {
      await boot();
      await enterGroup(
        groupId: 'grp-null-av',
        members: [(id: 'mem-ana', name: 'Ana')],
      );
      final ana = chat!.groupCharacters.firstWhere((c) => c.name == 'Ana');
      expect(ana.imagePath, anyOf(isNull, isEmpty));
      final needs = chat!.getNeedsForGroupCharacter(ana);
      expect(
        needs,
        isNotEmpty,
        reason: '#302 fallback: dbId when avatarFilename is null',
      );
      expect(needs['hunger'], isNotNull);
    });

    test('fpchat dayCount-only group fork uses that day at live TOD', () async {
      await boot();
      await enterGroup(
        groupId: 'grp-fpchat',
        members: [(id: 'mem-ana', name: 'Ana'), (id: 'mem-bea', name: 'Bea')],
        avatarFilename: '',
      );
      await plant(
        rows: [
          {
            'sender': 'Ana',
            'user': false,
            'cid': 'mem-ana',
            'text': 'Day nine.',
            'meta': {
              'realism_state': {'dayCount': 9, 'timeOfDay': 'afternoon'},
            },
          },
          {'sender': 'You', 'user': true, 'text': 'Fork.'},
        ],
        clock: _day12Iso,
        start: _startIso,
        day: 12,
      );
      final tod = chat!.timeService.timeOfDay;
      await chat!.forkFromMessage(1);
      await drain();
      expect(
        chat!.timeService.dayCount,
        9,
        reason: 'dayCount-only .fpchat stamp when no storyClock exists',
      );
      expect(chat!.timeService.timeOfDay, tod);
    });

    test('aliased null swipe_metadata shifts once on re-anchor', () async {
      await boot();
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Aliased.',
            'meta': {
              'story_clock_before': _livedIso,
              'story_clock_after': _livedIso,
            },
          },
        ],
        clock: _livedIso,
        start: _startIso,
      );
      final before = DateTime.parse(
        chat!.messages.last.activeMetadata!['story_clock_after'] as String,
      );
      await chat!.setStoryStartDate(
        chat!.timeService.startDate.add(const Duration(days: 10)),
      );
      final after = DateTime.parse(
        chat!.messages.last.activeMetadata!['story_clock_after'] as String,
      );
      expect(after.difference(before).inDays, 10);
    });
  });
}
