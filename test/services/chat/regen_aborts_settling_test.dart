// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// REGEN DURING POST-GEN EVALS MUST KILL THE EVAL AND START THE NEW SWIPE.
//
// After the reply streams, needs/climax/pockets still hold the turn busy
// (`isSettlingTurn`). The regen button stays visible (`isGenerating` is
// already false) but used to return immediately on `_isTurnBusy`, so a tap
// while oMLX was prefilling a needs eval was a silent no-op.
//
// The user is rejecting that reply — scoring it is wasted work. Regen must
// abort the in-flight eval and generate on the spot.

import 'dart:async';
import 'dart:io';

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
          return Directory.systemTemp.createTempSync('fpai_rgsettle_').path;
        }
        return null;
      });
}

class _HangNeedsLlm extends LLMService {
  Completer<void>? _hang;
  int chatCalls = 0;
  int hungPostGen = 0;

  @override
  void abortGeneration() {
    final hang = _hang;
    if (hang != null && !hang.isCompleted) hang.complete();
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      chatCalls++;
      yield '*She shrugs, already bored.*';
      return;
    }
    // Pre-gen judges run before the reply. After the reply, every remaining
    // eval is post-gen bookkeeping — hang the first of those until abort.
    if (chatCalls >= 1) {
      hungPostGen++;
      if (hungPostGen == 1) {
        _hang = Completer<void>();
        await _hang!.future;
        return;
      }
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"none","trust_reason":"none"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('hunger_delta')) {
      yield '{"hunger_delta":0,"energy_delta":0,"hygiene_delta":0,'
          '"fun_delta":0,"social_delta":0,"bladder_delta":0,'
          '"comfort_delta":0,"reason":"none"}';
      return;
    }
    yield '{}';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'HangNeedsLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _HangNeedsLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _HangNeedsLlm();
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

  tearDown(() async {
    llm.abortGeneration();
    chat.dispose();
    await db.close();
  });

  Future<void> waitUntil(bool Function() pred) async {
    for (var i = 0; i < 250 && !pred(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test(
    'regenerate during a hung needs eval aborts it and writes a new swipe',
    () async {
      final card = CharacterCard(
        name: 'Nia',
        description: 'Exists only inside the regen-settle test.',
        firstMessage: 'The screen door bangs shut behind you.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-rgsettle-1';
      await chat.setActiveCharacter(card);

      final sent = chat.sendMessage('I missed you.');
      await waitUntil(() => llm.hungPostGen >= 1);
      expect(
        llm.hungPostGen,
        1,
        reason: 'post-gen eval must still be in flight',
      );
      expect(chat.isSettlingTurn, isTrue);
      expect(llm.chatCalls, 1);

      await chat.regenerateLastMessage();
      expect(
        llm.chatCalls,
        2,
        reason:
            'THE BUG. Regen used to return on _isTurnBusy while a '
            'post-gen eval was prefilling, so the rejected reply was '
            'never replaced',
      );
      await sent;
      await waitUntil(() => !chat.isGenerating && !chat.isSettlingTurn);
      expect(chat.messages.last.swipes.length, greaterThan(1));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'send during a hung post-gen eval raises the waiting-on-settle flag',
    () async {
      final card = CharacterCard(
        name: 'Nia',
        description: 'Exists only inside the send-settle test.',
        firstMessage: 'The screen door bangs shut behind you.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-sendsettle-1';
      await chat.setActiveCharacter(card);

      final first = chat.sendMessage('I missed you.');
      await waitUntil(() => llm.hungPostGen >= 1);
      expect(chat.isSendWaitingOnSettle, isFalse);

      final queued = chat.sendMessage('Still here.');
      await waitUntil(() => chat.isSendWaitingOnSettle);
      expect(
        chat.isSendWaitingOnSettle,
        isTrue,
        reason: 'typed send must advertise that it is held behind post-gen',
      );
      expect(
        chat.messages.where((m) => m.isUser && m.text.contains('Still here.')),
        isEmpty,
        reason: 'the bubble is not in the list until settle finishes',
      );

      llm.abortGeneration();
      await first;
      await queued;
      expect(
        chat.messages.any((m) => m.isUser && m.text.contains('Still here.')),
        isTrue,
        reason: 'the held line must land, not vanish',
      );
      expect(chat.isSendWaitingOnSettle, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
