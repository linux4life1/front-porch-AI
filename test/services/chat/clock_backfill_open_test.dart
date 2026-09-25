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
import 'package:front_porch_ai/services/services.dart';

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

  Map<String, Object?> snapshot() {
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

  Future<void> expectIdempotentSecondOpen() async {
    final first = snapshot();
    final sid = chat!.currentSessionId!;
    final rowBefore = await db!.getSessionById(sid);
    await chat!.reloadCurrentSession();
    await drain();
    final second = snapshot();
    expect(second, first, reason: 'second open must not move clock or stamps');
    final rowAfter = await db!.getSessionById(sid);
    expect(rowAfter!.storyClock, rowBefore!.storyClock);
    expect(rowAfter.dayCount, rowBefore.dayCount);
    expect(rowAfter.storyStartDate, rowBefore.storyStartDate);
  }

  tearDown(() async {
    chat?.dispose();
    await db?.close();
  });

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
    expect(chat!.timeService.dayCount, greaterThanOrEqualTo(3));
    expect(chat!.timeService.dayCount, isNot(1));
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 30, 16, 0));
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
      start: null,
      day: 12,
      tod: 'afternoon',
    );
    expect(
      chat!.timeService.dayCount,
      greaterThanOrEqualTo(12),
      reason: 'dayCount-only chat must not collapse to Day 1',
    );
    expect(chat!.timeService.dayCount, isNot(1));
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
    expect(chat!.timeService.dayCount, greaterThanOrEqualTo(3));
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 30, 16, 0));
    expect(
      chat!.timeService.clock,
      isNot(DateTime.utc(2026, 6, 28, 18, 0)),
      reason: 'frozen greeting 18:00 is not the live clock',
    );
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
    await expectIdempotentSecondOpen();
    dir.deleteSync(recursive: true);
  });
}
