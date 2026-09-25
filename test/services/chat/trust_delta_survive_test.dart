// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Realism ON: a user send whose relationship eval returns a trust
// delta must move trust off the card default of 12, and that exact
// value must survive the clock stamp, dispose+rehydrate, regen, and
// swipe back to the original slot. Users saw trust stuck at 12 on
// 35acecc6.

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
          return Directory.systemTemp.createTempSync('fpai_trust_clk_').path;
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

const _defaultTrust = 12;
const _trustDelta = 5;
const _expectedTrust = _defaultTrust + _trustDelta;

class _ScriptedLlm extends LLMService {
  /// Greeting / opening relationship evals stay at 0. Arm only for the
  /// user send (and regen after rehydrate) so the first call is not
  /// assumed to be a greeting that never ran.
  bool armed = false;
  int nextMinutes = 30;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*Nia leans on the rail.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      final delta = armed ? _trustDelta : 0;
      yield '{"relationship_delta":0,"trust_delta":$delta,'
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
  String get backendName => 'ScriptedTrustClock';
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
      imagePath: '/tmp/nia-trust-clock.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        passageOfTimeEnabled: true,
        trustLevel: _defaultTrust,
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

  Future<ChatService> rehydrate(String sessionId) async {
    chat?.dispose();
    llm = _ScriptedLlm()..armed = true;
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
    return chat!;
  }

  ChatMessage lastBot() => chat!.messages.lastWhere((m) => !m.isUser);

  int lastBotIndex() => chat!.messages.lastIndexWhere((m) => !m.isUser);

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'trust delta survives clock stamp, reload, regen, and swipe back',
    () async {
      await boot();
      expect(
        chat!.relationshipService.trustLevel,
        _defaultTrust,
        reason: 'card default is 12 before the user send',
      );
      expect(chat!.realismEnabled, isTrue);
      final beforeClock = chat!.timeService.clock;

      llm.armed = true;
      await chat!.sendMessage('I kept my word.');
      await drain();

      expect(
        chat!.relationshipService.trustLevel,
        _expectedTrust,
        reason: 'trust_delta $_trustDelta must move trust off 12',
      );
      expect(
        chat!.timeService.clock,
        beforeClock.add(const Duration(minutes: 30)),
        reason: 'clock stamp must not rewind or wipe trust',
      );
      expect(
        chat!.relationshipService.trustLevel,
        _expectedTrust,
        reason: '(a) trust after the clock stamp is still $_expectedTrust',
      );

      await chat!.flushPendingSaves();
      final sid = chat!.currentSessionId!;
      await rehydrate(sid);
      expect(
        chat!.relationshipService.trustLevel,
        _expectedTrust,
        reason: '(b) dispose + rehydrate must keep $_expectedTrust, not 12',
      );

      await chat!.regenerateLastMessage();
      await drain();
      expect(
        chat!.relationshipService.trustLevel,
        _expectedTrust,
        reason: '(c) regen of that reply must restore then re-apply to 17',
      );

      final idx = lastBotIndex();
      expect(lastBot().swipes.length, greaterThanOrEqualTo(2));
      await chat!.selectSwipe(idx, 0);
      expect(
        chat!.relationshipService.trustLevel,
        _expectedTrust,
        reason: '(d) swipe back to slot A keeps $_expectedTrust, not 12',
      );
    },
  );

  test(
    'trust delta after greeting opening seed survives stamp (real boot)',
    () async {
      await boot();
      final personas = UserPersonaService(db!);
      final card = CharacterCard(
        name: 'NiaOpen',
        firstMessage: '',
        alternateGreetings: const ['Evening.'],
        imagePath: '/tmp/nia-trust-open.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          passageOfTimeEnabled: true,
          trustLevel: _defaultTrust,
          needsBaselineHunger: 80,
          needsBaselineBladder: 80,
          needsBaselineEnergy: 80,
          needsBaselineSocial: 80,
          needsBaselineFun: 80,
          needsBaselineHygiene: 80,
          needsBaselineComfort: 80,
          // Authored `{}` skips Read-the-Room so startFreshChatWith
          // hits _applyGreetingOpeningSeed's else at ~197
          // (_runOpeningRelationshipBaseline / _evaluateRelationshipCall).
          greetingSeeds: const [GreetingRealismSeed()],
        ),
      );
      await repo!.addCharacter(card);
      await chat!.startFreshChatWith(
        character: card,
        personaId: personas.persona.id,
      );
      await drain();
      // Opening seed schedules an unawaited relationship eval. Let it
      // finish while still unarmed so the user send is the only +5.
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(chat!.realismEnabled, isTrue);
      expect(chat!.timeService.passageOfTimeEnabled, isTrue);
      expect(
        chat!.relationshipService.trustLevel,
        _defaultTrust,
        reason: 'opening seed + unarmed greeting eval must leave card 12',
      );

      llm.armed = true;
      await chat!.sendMessage('I kept my word.');
      await drain();
      expect(
        chat!.relationshipService.trustLevel,
        _expectedTrust,
        reason:
            'user send after _applyGreetingOpeningSeed / '
            '_evaluateRelationshipCall must land trust at 17, not 12',
      );
    },
  );
}
