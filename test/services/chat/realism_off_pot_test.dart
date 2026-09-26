// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// T1: Realism OFF + Passage of Time ON. The clock runs, the time chip
// stamps, Realism evals do not fire, exactly one time-only LLM call
// lands per turn, Needs bars stay put, and needs_unaffected is written.
// Restores the case that realism_off_test weakened by turning PoT off.

import 'dart:io';

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
          return Directory.systemTemp.createTempSync('fpai_t1_off_').path;
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

class _CountingLlm extends LLMService {
  final calls = <String>[];

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    final names = [
      for (final tool in tools) (tool['function'] as Map?)?['name'] as String?,
    ];
    calls.add('tools:${names.join(',')}');
    return null;
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      calls.add('chat');
      yield '*Carmen leans on the rail.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      calls.add('relationship');
      yield '{"relationship_delta":0,"trust_delta":5,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      calls.add('with_user');
      yield '{"with_user": true}';
      return;
    }
    if (p.contains('hunger_delta')) {
      calls.add('needs');
      yield '{"hunger_delta": -3, "bladder_delta": 0, "energy_delta": 0, '
          '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "none"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      calls.add('emotion');
      yield '{"emotion":"joy","emotion_intensity":"strong"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      calls.add('time');
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    calls.add('other');
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'CountingT1';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;
  late _CountingLlm llm;

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
      'realism_default': false,
      'needs_sim_default': true,
      'passage_of_time_default': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db!, storage!);
    llm = _CountingLlm();
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
    final carmen = CharacterCard(
      name: 'Carmen',
      firstMessage: 'Evening.',
      imagePath: '/tmp/carmen-t1.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
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
    await chat!.setRealismEnabled(false);
    await chat!.setNeedsSimEnabled(true);
    await chat!.setPassageOfTimeEnabled(true);
    chat!.needsSimulation.restoreFromSnapshot({'vector': _needs});
    await drain();
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'T1 Realism OFF + PoT ON: one time call, no Realism evals, static Needs',
    () async {
      await boot();
      expect(chat!.realismEnabled, isFalse);
      expect(chat!.needsSimEnabled, isTrue);
      expect(chat!.timeService.passageOfTimeEnabled, isTrue);
      final beforeClock = chat!.timeService.clock;
      final beforeNeeds = Map<String, int>.from(chat!.needsSimulation.vector);
      llm.calls.clear();

      await chat!.sendMessage('Just talking, the porch clock still ticks.');
      await drain();

      expect(
        llm.calls.where((c) => c == 'relationship' || c == 'emotion'),
        isEmpty,
        reason: 'ZERO Realism eval calls when the master switch is off',
      );
      expect(
        llm.calls.where((c) => c == 'needs'),
        isEmpty,
        reason: 'Needs impact is gated on Realism — no hunger_delta call',
      );
      expect(
        llm.calls.where(
          (c) => c != 'chat' && c != 'time' && c != 'tools:report_scene_time',
        ),
        isEmpty,
        reason:
            'no eval/relationship/needs/tool call at the LLM boundary — '
            'every non-character, non-time call must be zero',
      );
      expect(
        llm.calls.where((c) => c == 'time'),
        hasLength(1),
        reason: 'exactly one time-only LLM call per turn',
      );
      expect(
        chat!.timeService.clock,
        beforeClock.add(const Duration(minutes: 30)),
        reason: 'the clock runs when PoT is on',
      );
      final last = chat!.messages.lastWhere((m) => !m.isUser);
      expect(
        last.activeMetadata?['time_passed'],
        '30 min',
        reason: 'the time chip must stamp',
      );
      expect(
        chat!.needsSimulation.vector,
        beforeNeeds,
        reason: 'Needs bars stay static',
      );
      expect(
        last.activeMetadata?[kNeedsUnaffectedMeta],
        isTrue,
        reason: 'no needs affected chip / needs_unaffected key is stamped',
      );
    },
  );
}
