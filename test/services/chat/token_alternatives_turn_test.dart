// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Token alternatives through the real ChatService turn pipeline. The scripted
// backend stands in for KoboldCpp's transport: it answers each request the
// way streamOpenAiChat would (text, then the logprobs callback), and records
// what was asked of it. The subject is the pipeline: who asks for odds, what
// the reply keeps, and how a rewrite from a word runs.
//
// Guards proven to fail before passing:
//   * drop `onLogprobs:` in paramsOf → the reply keeps no places
//   * drop the `_mouthIsLocal` gate in _logprobsSink → a remote backend asks
//   * drop `_applyRegenSeed` in the plan → the rewrite sends no prefill and
//     the new swipe does not start with the seed
//   * drop the seed in the postgen finalize → the saved swipe loses the seed

import 'dart:io';
import 'dart:math' as math;

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
          return Directory.systemTemp.createTempSync('fpai_tokalts_').path;
        }
        return null;
      });
}

Map<String, Object> _tok(
  String t,
  double p, [
  Map<String, double> alts = const {},
]) => {
  'token': t,
  'logprob': math.log(p),
  'top_logprobs': [
    {'token': t, 'logprob': math.log(p)},
    for (final e in alts.entries)
      {'token': e.key, 'logprob': math.log(e.value)},
  ],
};

class _KoboldLikeLlm extends LLMService {
  final List<GenerationParams> replies = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt == null) {
      yield '';
      return;
    }
    replies.add(params);
    final prefill = params.chatMessages?.last;
    if (prefill != null && prefill['role'] == 'assistant') {
      yield ' to fix the gate.';
      params.onLogprobs?.call([
        _tok(' to', 0.9),
        _tok(' fix', 0.35, {' paint': 0.3}),
        _tok(' the gate.', 0.9),
      ]);
      return;
    }
    yield 'She sat on the porch.';
    params.onLogprobs?.call([
      _tok('She', 0.9),
      _tok(' sat', 0.4, {' knelt': 0.3}),
      _tok(' on the', 0.9),
      _tok(' porch', 0.3, {' steps': 0.3}),
      _tok('.', 0.9),
    ]);
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'KoboldLike';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _KoboldLikeLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _KoboldLikeLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 400 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> start() async {
    final card = CharacterCard(
      name: 'Nia',
      description: 'Exists only inside the token alternatives test.',
      firstMessage: 'The porch light hums.',
    )..dbId = 'char-tokalts-1';
    await chat.setActiveCharacter(card);
    await chat.sendMessage('Where did you sit?');
    await drainTurn();
  }

  test('a remote backend never asks for word odds', () async {
    chat.testIsLocalOverride = false;
    await start();
    expect(llm.replies.single.onLogprobs, isNull);
    expect(chat.tokenAlternativesAt(chat.messages.length - 1), isEmpty);
  });

  test('a KoboldCpp reply keeps its unsure words, and picking one rewrites the '
      'reply from there as a new swipe', () async {
    chat.testIsLocalOverride = true;
    await start();

    final index = chat.messages.length - 1;
    final places = chat.tokenAlternativesAt(index);
    expect(places.map((a) => a.token), [' sat', ' porch']);
    expect(chat.tokenAltsPickRefusal(index), isNull);
    expect(
      chat.tokenAltsPickRefusal(index - 1),
      isNotNull,
      reason: 'only the last reply can be rewritten',
    );

    final ok = await chat.rewriteFromAlternative(index, places[1], ' steps');
    await drainTurn();
    expect(ok, isTrue);

    final rewrite = llm.replies.last;
    expect(rewrite.chatMessages?.last, {
      'role': 'assistant',
      'content': 'She sat on the steps',
    });
    expect(rewrite.reasoningEnabled, isFalse);

    final reply = chat.messages.last;
    expect(reply.swipes, hasLength(2));
    expect(reply.text, 'She sat on the steps to fix the gate.');
    expect(reply.swipes.first, 'She sat on the porch.');
    expect(chat.tokenAlternativesAt(index).map((a) => a.token), [
      ' sat',
      ' fix',
    ], reason: 'the earlier place carries over; the new words add theirs');

    await chat.loadSession(chat.currentSessionId!);
    expect(chat.messages.last.text, 'She sat on the steps to fix the gate.');
    expect(chat.tokenAlternativesAt(index), hasLength(2));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
