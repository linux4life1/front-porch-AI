// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// B1–B3 ChatService pins. B4 (.fpchat head clock) already lives in
// clock_import_fork_test.dart. Public ChatService API only.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_clk_ab_').path;
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
const _cardTrust = 45;
const _parentTrust = 200;
const _beforeIso = '2026-07-01T14:17:00.000Z';
const _afterIso = '2026-07-01T14:17:00.000Z';
const _slot0Before = '2026-07-01T10:00:00.000Z';
const _slot0After = '2026-07-01T10:10:00.000Z';

class _ScriptedLlm extends LLMService {
  int nextMinutes = 30;
  String nextReply = '*Nia leans on the rail.*';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield nextReply;
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
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
      yield '{"minutes_elapsed": $nextMinutes, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedHoldAb';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

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

  Future<void> boot({required bool realism}) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': realism,
      'needs_sim_default': true,
      'passage_of_time_default': true,
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
    await storage!.initialized;
    final nia = CharacterCard(
      name: 'Nia',
      firstMessage: 'Evening.',
      imagePath: '/tmp/nia-hold-ab.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: realism,
        needsSimEnabled: true,
        passageOfTimeEnabled: true,
        shortTermBond: _cardTrust,
        longTermBond: 10,
        trustLevel: _cardTrust,
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
    await chat!.setRealismEnabled(realism);
    chat!.needsSimulation.restoreFromSnapshot({'vector': _needs});
    await drain();
  }

  Future<void> plant({
    required List<Map<String, Object?>> rows,
    required String clock,
    required String start,
    int day = 4,
    String tod = 'afternoon',
    bool realism = true,
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
          id: 'ab$i',
          sessionId: sid,
          position: i,
          sender: r['sender'] as String,
          isUser: r['user'] as bool,
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
        realismEnabled: Value(realism),
        passageOfTimeEnabled: const Value(true),
        passageOfTimeGateMigrated: const Value(true),
        storyClock: Value(clock),
        storyStartDate: Value(start),
        timeOfDay: Value(tod),
        dayCount: Value(day),
        trustLevel: const Value(_parentTrust),
        affectionScore: const Value(_parentTrust),
      ),
    );
    await chat!.reloadCurrentSession();
    await drain();
  }

  Future<void> rehydrate(String sessionId) async {
    chat?.dispose();
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
    final card = repo!.characters.firstWhere((c) => c.name == 'Nia');
    await chat!.setActiveCharacter(card);
    await chat!.loadSession(sessionId);
    await drain();
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'B1: reload-then-fork keeps card seed trust, not parent current',
    () async {
      await boot(realism: true);
      expect(chat!.relationshipService.trustLevel, _cardTrust);
      chat!.relationshipService.loadScalars(
        affectionScore: _parentTrust,
        longTermScore: 10,
        trustLevel: _parentTrust,
      );
      await plant(
        rows: [
          {'sender': 'Nia', 'user': false, 'text': 'Greeting.'},
          {'sender': 'You', 'user': true, 'text': 'Hi.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Later.',
            'meta': {
              'realism_state': {
                'trustLevel': _parentTrust,
                'affectionScore': _parentTrust,
                'storyClock': _afterIso,
                'storyStartDate': _startIso,
              },
            },
          },
        ],
        clock: _afterIso,
        start: _startIso,
      );
      await chat!.flushPendingSaves();
      final sid = chat!.currentSessionId!;
      await rehydrate(sid);
      expect(
        chat!.relationshipService.trustLevel,
        _parentTrust,
        reason: 'parent after dispose+rehydrate must still hold moved trust',
      );
      await chat!.forkFromMessage(0);
      await drain();
      expect(
        chat!.relationshipService.trustLevel,
        _cardTrust,
        reason: 'fork from the stamp-less greeting must rewind to card seed',
      );
    },
  );

  test(
    'B2: null swipe slot s>0 keeps metadata after open; second open idempotent',
    () async {
      await boot(realism: true);
      await plant(
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Slot B.',
            'swipes': ['Slot A.', 'Slot B.'],
            'idx': 1,
            'meta': {
              'story_clock_before': _beforeIso,
              'story_clock_after': _afterIso,
              'is_dream': true,
              'time_passed': '47 min',
              'realism_state': {
                'trustLevel': _cardTrust,
                'storyClock': _afterIso,
                'storyStartDate': _startIso,
              },
            },
            'swipeMeta': [
              {
                'story_clock_before': _slot0Before,
                'story_clock_after': _slot0After,
              },
              null,
            ],
          },
        ],
        clock: _afterIso,
        start: _startIso,
      );
      final msg = chat!.messages.lastWhere((m) => !m.isUser);
      expect(msg.swipeIndex, 1);
      expect(
        msg.swipeMetadata[1],
        isNull,
        reason: 'null slot s>0 must stay null (alias metadata, no shadow map)',
      );
      expect(msg.activeMetadata?['story_clock_before'], _beforeIso);
      expect(msg.activeMetadata?['story_clock_after'], _afterIso);
      expect(msg.activeMetadata?['is_dream'], isTrue);
      expect(msg.activeMetadata?['time_passed'], '47 min');
      expect(chat!.timeService.clock, DateTime.utc(2026, 7, 1, 14, 17));

      final first = {
        'clock': chat!.timeService.storyClockIso,
        'before': msg.activeMetadata?['story_clock_before'],
        'after': msg.activeMetadata?['story_clock_after'],
        'dream': msg.activeMetadata?['is_dream'],
        'chip': msg.activeMetadata?['time_passed'],
        'slot1': msg.swipeMetadata[1],
      };
      final sid = chat!.currentSessionId!;
      final rowBefore = await db!.getSessionById(sid);
      await chat!.reloadCurrentSession();
      await drain();
      final again = chat!.messages.lastWhere((m) => !m.isUser);
      expect(again.swipeMetadata[1], isNull);
      expect({
        'clock': chat!.timeService.storyClockIso,
        'before': again.activeMetadata?['story_clock_before'],
        'after': again.activeMetadata?['story_clock_after'],
        'dream': again.activeMetadata?['is_dream'],
        'chip': again.activeMetadata?['time_passed'],
        'slot1': again.swipeMetadata[1],
      }, first);
      final rowAfter = await db!.getSessionById(sid);
      expect(rowAfter!.storyClock, rowBefore!.storyClock);
    },
  );

  test(
    'B3: Realism OFF user-set story_day before survives open, send, reload',
    () async {
      await boot(realism: false);
      expect(chat!.realismEnabled, isFalse);
      await plant(
        realism: false,
        rows: [
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Greeting.',
            'meta': {
              'story_clock_before': '2026-07-01T10:00:00.000Z',
              'story_clock_after': '2026-07-01T10:00:00.000Z',
              'story_day': 4,
            },
          },
          {'sender': 'You', 'user': true, 'text': 'Hi.'},
          {
            'sender': 'Nia',
            'user': false,
            'text': 'Afternoon.',
            'meta': {
              'story_clock_before': _beforeIso,
              'story_clock_after': _afterIso,
              'story_day': 4,
            },
          },
        ],
        clock: _afterIso,
        start: _startIso,
        day: 4,
      );
      expect(chat!.realismEnabled, isFalse);
      ChatMessage tip() => chat!.messages.lastWhere((m) => !m.isUser);
      expect(tip().activeMetadata?['story_day'], 4);
      expect(tip().activeMetadata?['story_clock_before'], _beforeIso);
      expect(chat!.timeService.clock, DateTime.utc(2026, 7, 1, 14, 17));

      await chat!.sendMessage('Still Realism off.');
      await drain();
      final planted = chat!.messages.firstWhere(
        (m) => !m.isUser && m.text == 'Afternoon.',
      );
      expect(planted.activeMetadata?['story_day'], 4);
      expect(planted.activeMetadata?['story_clock_before'], _beforeIso);

      await chat!.flushPendingSaves();
      await rehydrate(chat!.currentSessionId!);
      expect(chat!.realismEnabled, isFalse);
      final afterReload = chat!.messages.firstWhere(
        (m) => !m.isUser && m.text == 'Afternoon.',
      );
      expect(afterReload.activeMetadata?['story_day'], 4);
      expect(afterReload.activeMetadata?['story_clock_before'], _beforeIso);
      expect(
        DateTime.parse(
          afterReload.activeMetadata!['story_clock_before'] as String,
        ),
        DateTime.utc(2026, 7, 1, 14, 17),
      );
    },
  );
}
