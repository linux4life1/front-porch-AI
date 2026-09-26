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

// DREAMS NO LONGER BLOCK THE SEND (eval review item 6, 2026-08-10).
//
// The old design generated the dream INSIDE sendMessage, holding the user's
// morning message hostage to a model call. The clock crosses a night during a
// turn's PRE-generation advance, so the rollover is already visible by that
// turn's POST-generation phase — the dream can be generated there in the
// background and merely inserted at the next send. Split into a producer
// (_maybeKickDreamPrefetch, post-gen, parks a future in DreamService) and a
// consumer (sendMessage entry, takePrefetch + insert). checkRollover/pending/
// clear are UNTOUCHED — dream_service_test.dart still pins them.
//
// Part 1 drives the new park/take API directly (session guard, single-take,
// mismatch discard). Part 2 drives the REAL ChatService through a scripted
// LLM, so what is proven is the wiring: the dream call fires during the turn
// that crossed the night (not at the next send), and the next send inserts
// the finished text in the same position, with the same journal card, as the
// blocking design did.
//
// Every guard here was proven to fail before it was allowed to pass:
//   * make takePrefetch ignore its session guard → the mismatch test goes red
//   * make takePrefetch keep the park after a take → the single-take test
//     goes red
//   * delete the _maybeKickDreamPrefetch() call from the post-generation
//     phase → the wiring test goes red (no dream call ever fires, no dream
//     message ever appears)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show DreamService;
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_dream_').path;
        }
        return null;
      });
}

const _dreamText =
    'I was back on the porch steps, but the boards kept stretching away from '
    'me. Someone was laughing softly behind the screen door.';

/// Scripted backend: answers each eval by the keys its prompt asks for, and
/// records every DREAM prompt so the tests can pin WHEN the call fired.
class _ScriptedLlm extends LLMService {
  _ScriptedLlm(this.chatReplies, this.timeVerdicts);

  /// One per conversational turn, consumed in order; the last repeats.
  final List<String> chatReplies;
  int _chatIndex = 0;

  /// One per scene-time eval, consumed in order; the last repeats.
  final List<String> timeVerdicts;
  int _timeIndex = 0;

  /// Every dream prompt, in order.
  final List<String> dreamPrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;

    // The conversational turn is the only call that carries a system prompt.
    if (params.systemPrompt != null) {
      final reply =
          chatReplies[_chatIndex < chatReplies.length
              ? _chatIndex
              : chatReplies.length - 1];
      _chatIndex++;
      yield reply;
      return;
    }

    // The dream call — no other prompt in the app opens with these words.
    if (p.contains('Write the dream')) {
      dreamPrompts.add(p);
      yield _dreamText;
      return;
    }
    if (p.contains('minutes_elapsed')) {
      final verdict =
          timeVerdicts[_timeIndex < timeVerdicts.length
              ? _timeIndex
              : timeVerdicts.length - 1];
      _timeIndex++;
      yield verdict;
      return;
    }
    if (p.contains('current physical position and stance')) {
      yield '{"posture": "none"}';
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
    if (p.contains('fixation_topic')) {
      yield '{"fixation_topic":"none","proposed_objective":"none"}';
      return;
    }
    // Background passes (journal, growth, cast detection, …) get nothing to
    // parse, which is a clean no-op for all of them.
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

  // ── Part 1: the park/take contract, driven directly ───────────────────────

  group('DreamService.parkPrefetch/takePrefetch', () {
    DreamService svc() =>
        DreamService(fireEval: (_) async => null, isEnabled: () => true);

    test('take returns the parked dream for the matching session', () async {
      final s = svc();
      s.parkPrefetch(
        sessionId: 'a',
        ownerName: 'Nia',
        ownerId: 'nia-stable',
        ownerCharacterId: 'char-1',
        dream: Future.value('the dream'),
      );
      final taken = s.takePrefetch('a');
      expect(taken, isNotNull);
      expect(taken!.ownerName, 'Nia');
      expect(taken.ownerId, 'nia-stable');
      expect(taken.ownerCharacterId, 'char-1');
      expect(await taken.dream, 'the dream');
    });

    test('single-take: a second take returns null', () {
      final s = svc();
      s.parkPrefetch(
        sessionId: 'a',
        ownerName: 'Nia',
        ownerId: 'nia-stable',
        ownerCharacterId: null,
        dream: Future.value(null),
      );
      expect(s.takePrefetch('a'), isNotNull);
      expect(s.takePrefetch('a'), isNull);
    });

    test('session mismatch discards the park — a dream generated for one chat '
        'must never surface in another, not even later in the right one', () {
      final s = svc();
      s.parkPrefetch(
        sessionId: 'a',
        ownerName: 'Nia',
        ownerId: 'nia-stable',
        ownerCharacterId: null,
        dream: Future.value('the dream'),
      );
      expect(s.takePrefetch('b'), isNull);
      // The mismatch CLEARED the park (discard, not hold): coming back to
      // session 'a' later must not resurface a stale dream.
      expect(s.takePrefetch('a'), isNull);
    });

    test('null session takes nothing and clears', () {
      final s = svc();
      s.parkPrefetch(
        sessionId: 'a',
        ownerName: 'Nia',
        ownerId: 'nia-stable',
        ownerCharacterId: null,
        dream: Future.value('the dream'),
      );
      expect(s.takePrefetch(null), isNull);
      expect(s.takePrefetch('a'), isNull);
    });

    test('take with nothing parked is null', () {
      expect(svc().takePrefetch('a'), isNull);
    });
  });

  // ── Part 2: the wiring, through the real ChatService ──────────────────────

  group('dream prefetch wiring (real ChatService, scripted LLM)', () {
    late AppDatabase db;
    late StorageService storage;
    late ChatService chat;
    late _ScriptedLlm llm;

    Future<void> boot(List<String> replies, List<String> timeVerdicts) async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
      });
      db = AppDatabase.forTesting();
      storage = StorageService();
      llm = _ScriptedLlm(replies, timeVerdicts);
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
    }

    tearDown(() => disposeChatThenCloseDb(chat, db));

    /// The park is synchronous, but the recorded dream PROMPT rides the
    /// parked future's first await — drain event-loop turns (no wall-clock
    /// settle) until it lands.
    Future<void> drainUntil(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('a crossed night fires the dream call during THAT turn, and the next '
        'send inserts the finished dream before the morning message', () async {
      await boot(
        [
          '*She yawns, whispers goodnight, and falls asleep.*',
          '*She stretches in the pale light, remembering.*',
        ],
        [
          // Turn 1 crosses the night ("Goodnight" in the exchange is the
          // corroboration the new_day hallucination guard demands)…
          '{"minutes_elapsed": 60, "new_day": true}',
          // …turn 2 is an ordinary morning minute.
          '{"minutes_elapsed": 5, "new_day": false}',
        ],
      );
      final card = CharacterCard(
        name: 'Nia',
        description: 'Exists only inside the dream-prefetch test.',
        firstMessage: 'The porch light hums in the dusk.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-dream-1';
      await chat.setActiveCharacter(card);
      // Park the story on a known evening so ONE new_day deterministically
      // crosses a calendar day (nextMorning from 18:30 is tomorrow 08:00),
      // independent of the wall clock the test happens to run at.
      await chat.setStoryClock(DateTime.utc(2026, 3, 3, 18, 30));

      await chat.sendMessage('Goodnight — see you in the morning.');
      await drainUntil(() => llm.dreamPrompts.isNotEmpty);

      expect(
        llm.dreamPrompts,
        hasLength(1),
        reason:
            'THE DE-BLOCK. The dream call must fire from the turn whose '
            'clock crossed the night (post-generation prefetch), not from '
            'the next sendMessage — this assertion runs before any second '
            'send exists.',
      );
      expect(llm.dreamPrompts.single, contains('Write the dream Nia'));
      expect(
        chat.messages.any((m) => m.activeMetadata?['is_dream'] == true),
        isFalse,
        reason:
            'the dream is PARKED, not shown — it surfaces before the next '
            'morning message, exactly where the blocking design put it',
      );

      await chat.sendMessage('Good morning. Sleep well?');

      final msgs = chat.messages;
      final dreams = msgs
          .where((m) => m.activeMetadata?['is_dream'] == true)
          .toList();
      expect(dreams, hasLength(1));
      expect(dreams.single.text, _dreamText);
      expect(dreams.single.sender, 'Nia');
      final dreamIdx = msgs.indexOf(dreams.single);
      final morningIdx = msgs.indexWhere(
        (m) => m.isUser && m.text.startsWith('Good morning'),
      );
      expect(
        dreamIdx,
        morningIdx - 1,
        reason:
            'insertion position unchanged from the blocking design: the '
            'dream sits immediately before the morning message that '
            'surfaced it',
      );
      expect(
        llm.dreamPrompts,
        hasLength(1),
        reason: 'the consumer inserts the parked text — it never re-fires',
      );

      // The journal card the blocking design wrote still gets written —
      // kind rides the metadata JSON column.
      final rows = await db.select(db.journalMemories).get();
      final dreamCards = rows.where((r) {
        final md = r.metadata;
        if (md == null) return false;
        return (jsonDecode(md) as Map)['kind'] == 'dream';
      }).toList();
      expect(dreamCards, hasLength(1));
      expect(dreamCards.single.content, _dreamText);
    });

    test('an ordinary turn parks nothing and fires no dream call', () async {
      await boot(
        ['*She waves from the steps.*'],
        ['{"minutes_elapsed": 5, "new_day": false}'],
      );
      final card = CharacterCard(
        name: 'Nia',
        description: 'Exists only inside the dream-prefetch test.',
        firstMessage: 'The porch light hums in the dusk.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-dream-2';
      await chat.setActiveCharacter(card);
      await chat.setStoryClock(DateTime.utc(2026, 3, 3, 18, 30));

      await chat.sendMessage('Evening. Mind if I sit?');
      await drainUntil(() => llm.dreamPrompts.isNotEmpty);

      expect(llm.dreamPrompts, isEmpty);
      expect(
        chat.messages.any((m) => m.activeMetadata?['is_dream'] == true),
        isFalse,
      );
    });
  });
}
