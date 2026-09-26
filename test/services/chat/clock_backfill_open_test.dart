// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ChatService open-path backfill. Four lived-in shapes must land on a
// sane clock (Day >= the chat's real day, never Day 1 unless the chat
// genuinely is Day 1). A second open is idempotent: same clock, same
// stamps, no rewrite.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show kSessionOpenWindow;
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_backfill_open_')
              .path;
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
const _day1SixIso = '2026-06-28T18:00:00.000Z';
const _day3Iso = '2026-06-30T16:00:00.000Z';
const _day1NineIso = '2026-06-28T09:00:00.000Z';

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SilentBackfillOpen';
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

  Future<void> boot() async {
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
    final carmen = CharacterCard(
      name: 'Carmen',
      firstMessage: 'Evening.',
      imagePath: '/tmp/carmen-backfill.png',
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
    await repo!.addCharacter(carmen);
    await chat!.setActiveCharacter(carmen);
    chat!.needsSimulation.restoreFromSnapshot({'vector': _needs});
    await drain();
  }

  Future<void> plant({
    required List<Map<String, Object?>> rows,
    String? clock,
    String? start,
    int day = 2,
    String tod = 'afternoon',
  }) async {
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    await db!.deleteMessagesForSession(sid);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final meta = r['meta'] as Map<String, dynamic>?;
      await db!.insertMessage(
        MessagesCompanion.insert(
          id: 'bf$i',
          sessionId: sid,
          position: i,
          sender: r['sender'] as String,
          isUser: r['user'] as bool,
          swipes: Value(jsonEncode([r['text'] as String])),
          metadata: Value(meta == null ? null : jsonEncode(meta)),
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

  ChatMessage tipBot() =>
      chat!.messages.lastWhere((m) => !m.isUser && m.sender != 'System');

  Map<String, Object?> memorySnapshot() {
    return {
      'clock': chat!.timeService.storyClockIso,
      'day': chat!.timeService.dayCount,
      'start': chat!.timeService.storyStartDateIso,
      'stamps': [
        for (final m in chat!.messages)
          {
            'before': m.activeMetadata?['story_clock_before'],
            'after': m.activeMetadata?['story_clock_after'],
          },
      ],
    };
  }

  Object? _stampField(String? raw, String key, {int? swipeIndex}) {
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded[key];
    if (decoded is List) {
      if (swipeIndex != null &&
          swipeIndex >= 0 &&
          swipeIndex < decoded.length &&
          decoded[swipeIndex] is Map) {
        return (decoded[swipeIndex] as Map)[key];
      }
      for (final slot in decoded.reversed) {
        if (slot is Map && slot[key] != null) return slot[key];
      }
    }
    return null;
  }

  Future<Map<String, Object?>> persistedSnapshot(String sid) async {
    final row = await db!.getSessionById(sid);
    final rows = await db!.getMessagesForSession(sid);
    return {
      'clock': row?.storyClock,
      'day': row?.dayCount,
      'start': row?.storyStartDate,
      'stamps': [
        for (final r in rows)
          {
            'before':
                _stampField(
                  r.swipeMetadata,
                  'story_clock_before',
                  swipeIndex: r.swipeIndex,
                ) ??
                _stampField(r.metadata, 'story_clock_before'),
            'after':
                _stampField(
                  r.swipeMetadata,
                  'story_clock_after',
                  swipeIndex: r.swipeIndex,
                ) ??
                _stampField(r.metadata, 'story_clock_after'),
          },
      ],
    };
  }

  Future<void> expectPersistedMatchesMemory(String sid) async {
    final mem = memorySnapshot();
    final saved = await persistedSnapshot(sid);
    expect(
      saved['clock'],
      mem['clock'],
      reason: 'session-row storyClock must equal the in-memory clock',
    );
    expect(saved['day'], mem['day']);
    expect(saved['start'], mem['start']);
    expect(
      saved['stamps'],
      mem['stamps'],
      reason: 'saved per-message stamps must equal in-memory stamps',
    );
  }

  Future<ChatService> coldOpen(String sid) async {
    final name =
        chat?.activeCharacter?.name ??
        repo!.characters.firstWhere((c) => c.name == 'Carmen').name;
    chat?.dispose();
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
    final card = repo!.characters.firstWhere((c) => c.name == name);
    await chat!.setActiveCharacter(card);
    await chat!.loadSession(sid);
    await drain();
    return chat!;
  }

  Future<void> expectIdempotentSecondOpen() async {
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    final firstMem = memorySnapshot();
    await expectPersistedMatchesMemory(sid);
    final firstSaved = await persistedSnapshot(sid);
    await coldOpen(sid);
    final secondMem = memorySnapshot();
    expect(
      secondMem,
      firstMem,
      reason: 'cold second open must not rewrite clock or stamps',
    );
    await expectPersistedMatchesMemory(sid);
    final secondSaved = await persistedSnapshot(sid);
    expect(
      secondSaved,
      firstSaved,
      reason: 'persisted stamps must be identical across the two opens',
    );
  }

  void expectTipSlotStamps() {
    final tip = tipBot();
    expect(
      tip.activeMetadata?['story_clock_before'],
      isNotNull,
      reason: 'tip slot must carry story_clock_before after open',
    );
    expect(
      tip.activeMetadata?['story_clock_after'],
      isNotNull,
      reason: 'tip slot must carry story_clock_after after open',
    );
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('Carmen-class lived-in open never snaps Day 1', () async {
    await boot();
    const frozen = {
      'storyClock': _day1NineIso,
      'storyStartDate': _startIso,
      'timeOfDay': 'morning',
      'dayCount': 1,
    };
    await plant(
      rows: [
        for (var i = 0; i < 5; i++) ...[
          {
            'sender': 'Carmen',
            'user': false,
            'text': 'Line $i.',
            'meta': {'realism_state': frozen},
          },
          {'sender': 'You', 'user': true, 'text': 'And $i.'},
        ],
        {
          'sender': 'Carmen',
          'user': false,
          'text': 'Still here.',
          'meta': {'realism_state': frozen},
        },
      ],
      clock: _day3Iso,
      start: _startIso,
      day: 3,
    );
    expect(chat!.timeService.dayCount, 3);
    expect(chat!.timeService.dayCount, isNot(1));
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 30, 16, 0));
    expectTipSlotStamps();
    expect(tipBot().activeMetadata?['story_clock_after'], _day3Iso);
    await expectIdempotentSecondOpen();
  });

  test('Day-12 dayCount-only open stays on Day 12', () async {
    await boot();
    await plant(
      rows: [
        {
          'sender': 'Carmen',
          'user': false,
          'text': 'Day twelve.',
          'meta': {
            'realism_state': {'dayCount': 12, 'timeOfDay': 'afternoon'},
          },
        },
        {'sender': 'You', 'user': true, 'text': 'Still?'},
        {
          'sender': 'Carmen',
          'user': false,
          'text': 'Still.',
          'meta': {
            'realism_state': {'dayCount': 12, 'timeOfDay': 'afternoon'},
          },
        },
      ],
      clock: null,
      start: _startIso,
      day: 12,
      tod: 'afternoon',
    );
    expect(
      chat!.timeService.dayCount,
      12,
      reason: 'dayCount-only chat must land on Day 12, not >=12',
    );
    expect(
      chat!.timeService.clock,
      DateTime.utc(2026, 7, 9, 14, 30),
      reason: 'Day 12 afternoon is 2026-07-09 14:30',
    );
    expectTipSlotStamps();
    await expectIdempotentSecondOpen();
  });

  test('frozen Day 1 18:00 greeting open keeps the lived-in clock', () async {
    await boot();
    const evening = {
      'storyClock': _day1SixIso,
      'storyStartDate': _startIso,
      'timeOfDay': 'evening',
      'dayCount': 1,
    };
    await plant(
      rows: [
        {
          'sender': 'Carmen',
          'user': false,
          'text': 'Evening.',
          'meta': {'realism_state': evening},
        },
        {'sender': 'You', 'user': true, 'text': 'Hi.'},
        {
          'sender': 'Carmen',
          'user': false,
          'text': 'Still here.',
          'meta': {'realism_state': evening},
        },
      ],
      clock: _day3Iso,
      start: _startIso,
      day: 3,
    );
    expect(chat!.timeService.dayCount, 3);
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 30, 16, 0));
    expect(
      chat!.timeService.clock,
      isNot(DateTime.utc(2026, 6, 28, 18, 0)),
      reason: 'frozen greeting 18:00 is not the live clock',
    );
    expectTipSlotStamps();
    expect(tipBot().activeMetadata?['story_clock_after'], _day3Iso);
    await expectIdempotentSecondOpen();
  });

  test('v1.4 fixture open is sane and a second open is idempotent', () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    final dir = Directory.systemTemp.createTempSync('fpai_backfill_v14_');
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
    final card = repo!.characters.firstWhere((c) => c.name == 'Clocked');
    await chat!.setActiveCharacter(card);
    await chat!.loadSession('1790314133694');
    await drain();
    expect(chat!.timeService.dayCount, greaterThanOrEqualTo(4));
    expect(chat!.timeService.clock, DateTime.utc(2026, 9, 28, 19, 0));
    expectTipSlotStamps();
    expect(
      tipBot().activeMetadata?['story_clock_after'],
      chat!.timeService.storyClockIso,
    );
    await expectIdempotentSecondOpen();
    dir.deleteSync(recursive: true);
  });

  test(
    'windowed open (more than $kSessionOpenWindow rows) keeps the tip clock',
    () async {
      await boot();
      final n = kSessionOpenWindow + 6;
      await plant(
        rows: [
          {
            'sender': 'Carmen',
            'user': false,
            'text': 'Greeting.',
            'meta': {
              'story_clock_before': _day1NineIso,
              'story_clock_after': _day1NineIso,
            },
          },
          for (var i = 0; i < n - 3; i++)
            {
              'sender': i.isEven ? 'You' : 'Carmen',
              'user': i.isEven,
              'text': 'Fill $i.',
              if (!i.isEven)
                'meta': {
                  'story_clock_before': _day1NineIso,
                  'story_clock_after': _day1NineIso,
                },
            },
          {'sender': 'You', 'user': true, 'text': 'Still here?'},
          {
            'sender': 'Carmen',
            'user': false,
            'text': 'Tip.',
            'meta': {
              'story_clock_before': _day3Iso,
              'story_clock_after': _day3Iso,
            },
          },
        ],
        clock: _day3Iso,
        start: _startIso,
        day: 3,
      );
      await chat!.flushPendingSaves();
      final sid = chat!.currentSessionId!;
      expect(chat!.messages.length, greaterThan(kSessionOpenWindow));
      await coldOpen(sid);
      expect(
        chat!.messages.length,
        greaterThan(kSessionOpenWindow),
        reason: 'fixture is larger than the open window after hydrate',
      );
      expect(chat!.timeService.clock, DateTime.utc(2026, 6, 30, 16, 0));
      expect(chat!.timeService.dayCount, 3);
      expectTipSlotStamps();
      expect(tipBot().text, 'Tip.');
      expect(tipBot().activeMetadata?['story_clock_after'], _day3Iso);
      await expectIdempotentSecondOpen();
    },
  );

  test('null session storyClock recovers Day 3 from message stamps', () async {
    await boot();
    await plant(
      rows: [
        {
          'sender': 'Carmen',
          'user': false,
          'text': 'Greeting.',
          'meta': {
            'story_clock_before': _day1NineIso,
            'story_clock_after': _day1NineIso,
          },
        },
        {'sender': 'You', 'user': true, 'text': 'Hi.'},
        {
          'sender': 'Carmen',
          'user': false,
          'text': 'Lived in.',
          'meta': {
            'story_clock_before': _day3Iso,
            'story_clock_after': _day3Iso,
          },
        },
      ],
      clock: null,
      start: _startIso,
      day: 1,
      tod: 'morning',
    );
    expect(
      chat!.timeService.clock,
      DateTime.utc(2026, 6, 30, 16, 0),
      reason: 'missing session storyClock must recover the tip after',
    );
    expect(chat!.timeService.dayCount, 3);
    expect(chat!.timeService.dayCount, isNot(1));
    expectTipSlotStamps();
    expect(tipBot().activeMetadata?['story_clock_after'], _day3Iso);
    await expectIdempotentSecondOpen();
  });
}
