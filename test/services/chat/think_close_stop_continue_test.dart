// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A reply cut inside `<think>` is salvaged, never promoted: Stop mid-thought
// stores the closer. Continue on a reply whose thought is still open closes
// it BEFORE gluing, so the new words land in the bubble, not in the thought
// — on finalize and when Stop lands mid-Continue.
//
// The stream is a scripted token feed that keeps going after Stop (the way
// a local engine's stream ends on abort), so the turn takes the clean
// cancel path. The assertions read where the app put the tokens.
//
// Proven red:
//  * drop the closeOpenThink on the cancel path → test 1 fails (no closer);
//  * drop it on the Continue prefix capture → test 3 fails (new words in
//    the thought); drop it on BOTH the prefix capture and the postgen merge
//    → test 2 fails. Either one alone keeps test 2 green (they are
//    redundant for finalize; the capture is what the Stop path reads).

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../helpers/chat_db_teardown.dart';

const _openThought = '<think>\nShould she wave again? Maybe';

class _TokenFeed extends LLMService {
  List<String> pieces = ['She waves.'];
  Duration delay = Duration.zero;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt == null) {
      yield '';
      return;
    }
    for (final p in List.of(pieces)) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      yield p;
    }
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'TokenFeed';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_thinkclose_').path;
        }
        return null;
      });

  late _TokenFeed llm;
  late AppDatabase db;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    llm = _TokenFeed();
    db = AppDatabase.forTesting();
    final storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    await storage.backendSettings.setReasoningEnabled(true);
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        description: 'Exists only inside the think-close test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-think-close',
    );
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue, reason: 'timed out waiting for $what');
  }

  Future<void> settled() =>
      until(() => !chat.isGenerating && !chat.isSettlingTurn, 'turn to end');

  /// A stored reply whose thought never closed (a cut-off from before the
  /// salvage, or an import).
  Future<void> arrangeOpenThoughtReply() async {
    await chat.sendMessage('Evening.');
    await settled();
    chat.messages.last.text = _openThought;
  }

  void slowFeed(List<String> pieces) {
    llm
      ..pieces = pieces
      ..delay = const Duration(milliseconds: 30);
  }

  test('Stop inside a thought stores the closer', () async {
    slowFeed([
      '<think>\nWeighing it ',
      'over ',
      for (var i = 0; i < 60; i++) 'slowly ',
    ]);
    final send = chat.sendMessage('Evening.');
    await until(
      () =>
          !chat.messages.last.isUser &&
          chat.messages.last.text.contains('Weighing'),
      'the thought to stream',
    );
    chat.stopGeneration();
    await send;
    await settled();

    final text = chat.messages.last.text;
    expect(text, contains('Weighing'));
    expect(
      text.trimRight(),
      endsWith('</think>'),
      reason: 'a cut-off thought is salvaged with its closer',
    );
    expect(splitMessageForEdit(text).body.trim(), isEmpty);
  });

  test(
    'Continue on an open thought puts the new words in the bubble',
    () async {
      await arrangeOpenThoughtReply();

      llm.pieces = [' She smiles and waves back.'];
      await chat.continueGeneration();
      await settled();

      final parts = splitMessageForEdit(chat.messages.last.text);
      expect(parts.thinking, contains('Should she wave again'));
      expect(
        parts.body,
        contains('She smiles and waves back.'),
        reason: 'closing after the glue swallows the continuation',
      );
      expect(parts.thinking, isNot(contains('smiles')));
    },
  );

  test('Stop mid-Continue keeps the new words out of the thought', () async {
    await arrangeOpenThoughtReply();

    slowFeed([' She smiles', ' and', for (var i = 0; i < 60; i++) ' waits']);
    final cont = chat.continueGeneration();
    await until(
      () => chat.messages.last.text.contains('She smiles'),
      'the continuation to stream',
    );
    chat.stopGeneration();
    await cont;
    await settled();

    final parts = splitMessageForEdit(chat.messages.last.text);
    expect(parts.thinking, contains('Should she wave again'));
    expect(parts.body, contains('She smiles'));
    expect(parts.thinking, isNot(contains('She smiles')));
  });
}
