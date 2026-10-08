// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Needs require the Realism engine (the Porch Life tab's own words) and
// answer to the global Needs switch live. A user on v1.5.0 with Realism off
// saw "Bladder −1" under a reply: the Needs v2 clock wear ran from the
// post-gen path that the clock keeps alive without the engine, gated on
// the per-chat Needs flag alone. Before v2 the only way a need moved was
// the needs judge, behind the engine. The same gate reads the global
// switch live, the way objectivesActive does, so turning it off mid-chat
// takes effect on the next turn rather than the next reopen.
import 'dart:io';

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
          return Directory.systemTemp.createTempSync('fpai_needs_eng_').path;
        }
        return null;
      });
}

const _bars = {
  'hunger': 80,
  'bladder': 80,
  'energy': 80,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

/// Thirty story minutes a reply, zeros from every judge: only the clock's
/// own wear can move a bar (hunger 3, bladder 7, energy 2 at Normal pace).
class _ThirtyMinuteLlm extends LLMService {
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
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
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
  String get backendName => 'ThirtyMinutes';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
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
    final repo = CharacterRepository(db!, storage!);
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _ThirtyMinuteLlm();
    await storage!.initialized;
    final carmen = CharacterCard(
      name: 'Carmen',
      firstMessage: 'Evening.',
      imagePath: '/tmp/carmen-needs-engine.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: realism,
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
    await repo.addCharacter(carmen);
    await chat!.setActiveCharacter(carmen);
    await chat!.setRealismEnabled(realism);
    await chat!.setNeedsSimEnabled(true);
    await chat!.setPassageOfTimeEnabled(true);
    chat!.needsSimulation.restoreFromSnapshot({'vector': _bars});
    await drainTurn();
  }

  Map<String, int> bars() =>
      Map<String, int>.from(chat!.needsSimulation.vector);

  ChatMessage lastBot() => chat!.messages.lastWhere((m) => !m.isUser);

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'Realism off, Needs on, clock on: the clock stamps time and wears nothing',
    () async {
      await boot(realism: false);
      expect(chat!.realismEnabled, isFalse);
      expect(chat!.needsSimEnabled, isTrue);

      await chat!.sendMessage('How are you?');
      await drainTurn();
      final meta = lastBot().activeMetadata ?? const {};
      expect(meta['time_passed'], '30 min', reason: 'the clock still runs');
      expect(bars(), _bars, reason: 'no engine, no wear');
      expect(meta.containsKey('needs_time_wear'), isFalse);
      expect(meta.containsKey('needs_pre_turn_vector'), isFalse);
      expect(meta.containsKey('bond_delta'), isFalse);
    },
  );

  test(
    'Realism on: the global Needs switch is read live, turn by turn',
    () async {
      await boot(realism: true);
      await chat!.sendMessage('How are you?');
      await drainTurn();
      expect(bars()['bladder'], 73, reason: 'the clock wears with the engine');

      await storage!.realismSettings.setNeedsSimDefault(false);
      await chat!.sendMessage('And now?');
      await drainTurn();
      expect(
        bars()['bladder'],
        73,
        reason: 'the global switch off takes effect on the next turn',
      );
      expect(lastBot().activeMetadata?.containsKey('needs_time_wear'), isFalse);

      await storage!.realismSettings.setNeedsSimDefault(true);
      await chat!.sendMessage('Back on.');
      await drainTurn();
      // 7.5 a beat: the first wore 7 and carried the half, so this one
      // wears 8. The carry survived the turn that wore nothing.
      expect(bars()['bladder'], 65, reason: 'and on again the same way');
    },
  );
}
