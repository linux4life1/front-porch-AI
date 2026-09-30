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

// CANCELLING A REGENERATE HAS TO PUT BACK THE STATE, NOT JUST THE TEXT.
//
// A regenerate un-applies the reply it is about to replace before it asks the
// model for a new one: bond and trust deltas reverted, needs restored from the
// message's own pre-turn vector, the baseline pulled from the PREVIOUS
// accepted message, the stance rewound, pockets rolled back — and then a fresh
// decay tick charged, because a regen replays the turn.
//
// Press Cancel on the realism overlay at that moment and the old code put the
// MESSAGE back and returned. The message came back displaying its chips while
// the sidebar and the session row held the pre-turn numbers minus one extra
// decay tick, and the `_saveChat()` on the way out persisted the disagreement.
// Every later turn then evaluated and decayed from the wrong baseline. The two
// success paths of the same method have always ended with
// `_restoreRealismStateForSpeaker(lastMsg)` for exactly this reason; the
// cancel path never learned it.
//
// Proven to fail first: removing the two restore calls from the cancel bails
// makes the bond assertion below read 0 instead of 8.

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
          return Directory.systemTemp.createTempSync('fpai_rgcancel_').path;
        }
        return null;
      });
}

/// Scores the first turn as a warm one (+8 bond), then — on the regenerate —
/// presses Cancel from inside the relationship eval, which is exactly where a
/// user pressing the overlay's Cancel button lands.
///
/// Once cancelled it yields NOTHING for the rest of the run, because that is
/// what really happens: `cancelRealismEval` calls `abortGeneration` on the
/// backend and the eval streams come back empty. (A fake that kept answering
/// would re-apply the same +8 the revert had just removed and mask the bug
/// entirely — which is exactly what the first draft of this guard did.)
class _ScriptedLlm extends LLMService {
  _ScriptedLlm();

  /// Set once the chat exists; called to cancel the regen's eval run.
  Future<void> Function()? cancel;

  /// Flipped by the test right before it presses Regenerate.
  bool cancelNextEval = false;

  /// Every conversational (reply) call — one per accepted turn.
  int chatCalls = 0;

  bool _aborted = false;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      chatCalls++;
      yield '*She leans in, warmer than before.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      if (cancelNextEval) {
        cancelNextEval = false;
        _aborted = true;
        await cancel?.call();
        return; // aborted mid-stream: nothing to parse
      }
      if (_aborted) return;
      yield '{"relationship_delta":8,"trust_delta":0,'
          '"bond_reason":"warm","trust_reason":"steady"}';
      return;
    }
    if (_aborted) return;
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"happy","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('fixation_topic')) {
      yield '{"fixation_topic":"none","proposed_objective":"none"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
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
    llm.cancel = () => chat.cancelRealismEval();
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

  test('cancelling a 1:1 regenerate leaves the restored reply and the live '
      'state telling the same story', () async {
    final card = CharacterCard(
      name: 'Nia',
      description: 'Exists only inside the regen-cancel test.',
      firstMessage: 'The screen door bangs shut behind you.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'char-rgcancel-1';
    await chat.setActiveCharacter(card);

    await chat.sendMessage('I missed you.');
    await drainTurn();

    final acceptedBond = chat.relationshipService.affectionScore;
    expect(acceptedBond, 8, reason: 'the turn was scored +8');
    final messageCount = chat.messages.length;
    final acceptedText = chat.messages.last.text;

    llm.cancelNextEval = true;
    await chat.regenerateLastMessage();
    await drainTurn();

    expect(
      chat.messages,
      hasLength(messageCount),
      reason: 'the popped reply must come back — nothing is destroyed',
    );
    expect(chat.messages.last.text, acceptedText);
    expect(
      llm.chatCalls,
      1,
      reason:
          'the cancel must bail BEFORE generation — if a second reply were '
          'written, this guard would be measuring the ordinary regen path '
          'instead of the cancel path',
    );
    expect(
      chat.relationshipService.affectionScore,
      acceptedBond,
      reason:
          'THE BUG. The regen reverted the accepted turn before asking; '
          'cancelling must put that back, or the chips on the restored reply '
          'describe a turn the engine no longer believes happened',
    );

    // And the disagreement must not be what got written to disk.
    final row = await db.getSessionById(chat.currentSessionId!);
    expect(row!.affectionScore, acceptedBond);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
