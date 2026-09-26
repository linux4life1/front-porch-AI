// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// K-1: cancelled Continue must not rewind the tip clock or clear its chip.

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
          return Directory.systemTemp.createTempSync('fpai_cont_abort_').path;
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
const _beforeIso = '2026-06-29T16:37:00.000Z';
const _afterIso = '2026-06-29T17:07:00.000Z';

class _ScriptedLlm extends LLMService {
  Future<void> Function()? cancel;
  bool cancelOnNeeds = true;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield ' and stays on the rail.';
      return;
    }
    final p = params.prompt;
    if (p.contains('hunger_delta') && cancelOnNeeds) {
      cancelOnNeeds = false;
      await cancel?.call();
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
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
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedContinueAbort';
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

  Future<void> boot({required bool porchLife}) async {
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
      imagePath: '/tmp/nia-cont-abort.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        passageOfTimeEnabled: porchLife,
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

  Future<void> plantTip() async {
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    await db!.deleteMessagesForSession(sid);
    final rows = [
      {
        'sender': 'Nia',
        'user': false,
        'text': 'Evening.',
        'meta': {
          'story_clock_before': _beforeIso,
          'story_clock_after': _beforeIso,
        },
      },
      {'sender': 'You', 'user': true, 'text': 'Hey.', 'meta': null},
      {
        'sender': 'Nia',
        'user': false,
        'text': 'On the rail.',
        'meta': {
          'story_clock_before': _beforeIso,
          'story_clock_after': _afterIso,
          'time_passed': '30 min',
        },
      },
    ];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final meta = r['meta'] as Map<String, dynamic>?;
      await db!.insertMessage(
        MessagesCompanion.insert(
          id: 'c$i',
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
        storyClock: const Value(_afterIso),
        storyStartDate: const Value(_startIso),
        timeOfDay: const Value('afternoon'),
        dayCount: const Value(2),
      ),
    );
    await chat!.reloadCurrentSession();
    await drain();
  }

  ChatMessage tip() => chat!.messages.lastWhere((m) => !m.isUser);

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('cancelled Continue keeps tip after and chip', () async {
    await boot(porchLife: true);
    await plantTip();
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 29, 17, 7));
    expect(tip().activeMetadata?['story_clock_after'], _afterIso);
    expect(tip().activeMetadata?['time_passed'], '30 min');

    await chat!.continueGeneration();
    await drain();

    expect(tip().activeMetadata?['story_clock_after'], _afterIso);
    expect(tip().activeMetadata?['story_clock_before'], _beforeIso);
    expect(tip().activeMetadata?['time_passed'], '30 min');
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 29, 17, 7));
  });

  test('cancelled Continue with Porch Life OFF leaves the clock', () async {
    await boot(porchLife: false);
    await plantTip();
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 29, 17, 7));

    await chat!.continueGeneration();
    await drain();

    expect(tip().activeMetadata?['story_clock_after'], _afterIso);
    expect(tip().activeMetadata?['time_passed'], '30 min');
    expect(chat!.timeService.clock, DateTime.utc(2026, 6, 29, 17, 7));
  });
}
