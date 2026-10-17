// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Skip goal check" on the objective overlay stops only the goal check.
// A real ChatService sends a turn to a loopback OpenAI-compatible backend
// that holds the goal-check request open (and would answer YES, which would
// retire the quest). Skip must: let the reply land, leave the quest as it
// was, and hang up the held request instead of leaving it running. Once the
// check is applying its answer, Skip is too late and says so: the answer
// applies whole, never half while the status claims none.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show
        kObjectiveOriginCharacter,
        kObjectiveStatusDormant,
        lastObjectiveSyncStamp;

import '../../../integration_test/support/fake_backend.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_goal_skip_').path;
        }
        return null;
      });
}

/// No engine on disk and no download: this test never starts KoboldCpp.
class _QuietBackend extends BackendManager {
  _QuietBackend(super.storage);

  @override
  String? get backendPath => '/tmp/fake-koboldcpp';

  @override
  Future<void> checkBackendAvailability() async {}

  @override
  Future<void> ensureEngineInstalled() async {}
}

Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

const _skipped = 'Goal check skipped. Your goals stay as they were.';
const _tooLate = 'Too late to skip: the goal check already had its answer.';

typedef _Harness = ({
  ChatService chat,
  FakeBackendServer backend,
  Completer<void> hold,
  AppDatabase db,
});

/// A real ChatService on a loopback backend whose goal check answers
/// [verdict]; [held] keeps that request open until the test lets it go.
/// [realism], [journal] and the card's starting [mood] are off by default.
Future<_Harness> _harness({
  required String verdict,
  bool held = true,
  bool realism = false,
  bool journal = false,
  String? mood,
}) async {
  HttpOverrides.global = null;
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({
    'update_auto_check': false,
    'backend_type': 'openRouter',
    'realism_default': realism,
    'pockets_enabled': false,
    'journal_enabled': journal,
  });
  final backend = await FakeBackendServer.start(
    replyPieces: ['The lemonade is ', 'still cold.'],
  );
  final hold = Completer<void>();
  backend
    ..objectiveCheckVerdict = verdict
    ..holdObjectiveCheck = held ? hold : null;

  final db = AppDatabase.forTesting(sameIsolate: true);
  final storage = StorageService();
  await storage.initialized;
  final kobold = KoboldService(storage);
  final provider = LLMProvider(
    kobold,
    OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
    storage,
    _QuietBackend(storage),
  );
  final chat =
      ChatService(
          kobold,
          UserPersonaService(db),
          storage,
          WorldRepository(storage, db),
        )
        ..setDatabase(db)
        ..setCharacterRepository(CharacterRepository(db, storage))
        // The check only runs with a provider wired, as in the app.
        ..setLLMProvider(provider)
        ..testLlmServiceOverride = OpenRouterService(
          apiUrl: '${backend.baseUrl}/v1',
          modelName: 'smoke-model',
        );
  addTearDown(() async {
    if (!hold.isCompleted) hold.complete();
    await disposeChatThenCloseDb(chat, db);
    provider.dispose();
    await backend.close();
  });

  await chat.setActiveCharacter(
    CharacterCard(
      name: 'Jennifer',
      description: 'Exists only inside the goal-check skip test.',
      firstMessage: 'Welcome to the porch.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: realism,
        needsSimEnabled: false,
        chaosModeEnabled: false,
        characterEmotion: mood ?? '',
        emotionIntensity: mood == null ? 'mild' : 'strong',
      ),
    )..dbId = 'char-goal-skip',
  );
  await chat.setObjective('Share porch lemonade before sunset');
  await chat.updateCheckFrequency(chat.activeObjectives.single, 1);
  return (chat: chat, backend: backend, hold: hold, db: db);
}

void _expectReplyLanded(_Harness h) {
  expect(h.chat.isCheckingCompletion, isFalse);
  expect(h.backend.chatRequests, 1, reason: 'the reply was still asked for');
  final reply = h.chat.messages.last;
  expect(reply.isUser, isFalse);
  expect(reply.displayText, 'The lemonade is still cold.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('Skip goal check: the reply lands, the quest is untouched, the held '
      'check request is hung up, and nothing is left unhandled', () async {
    final h = await _harness(verdict: '1: YES');
    final quest = h.chat.activeObjectives.single;

    // The fake refuses tools, so this is the text floor: the abort makes the
    // abandoned request throw, and that must not escape as an uncaught error.
    final uncaught = <Object>[];
    final sent = Completer<void>();
    runZonedGuarded(() {
      h.chat.sendMessage('Want some lemonade?').then(sent.complete);
    }, (e, _) => uncaught.add(e));
    await h.backend.objectiveCheckHeld.future.timeout(
      const Duration(seconds: 10),
    );
    expect(h.chat.isCheckingCompletion, isTrue);

    h.chat.skipObjectiveCheck();
    expect(h.chat.guestActivityStatus, _skipped);
    await sent.future.timeout(const Duration(seconds: 10));

    _expectReplyLanded(h);
    expect(h.chat.activeObjectives.map((o) => o.id), [
      quest.id,
    ], reason: 'the held check would have answered YES and retired the quest');
    await _until(
      () => h.backend.objectiveChecksHungUp == 1,
      'the held goal-check request to be hung up',
    );
    expect(h.backend.objectiveCheckRequests, 1);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(uncaught, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('Skip after the answer arrived but before it is applied changes no '
      'quest', () async {
    final h = await _harness(verdict: '1: YES');
    h.backend.objectiveCheckAnswerFirst = true;
    final quest = h.chat.activeObjectives.single;

    final send = h.chat.sendMessage('Want some lemonade?');
    await h.backend.objectiveCheckHeld.future.timeout(
      const Duration(seconds: 10),
    );
    // The YES is on its way to the app; only the stream's end is held.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(h.chat.isCheckingCompletion, isTrue);

    h.chat.skipObjectiveCheck();
    await send.timeout(const Duration(seconds: 10));

    _expectReplyLanded(h);
    expect(h.chat.activeObjectives.map((o) => o.id), [quest.id]);
    expect(h.chat.guestActivityStatus, _skipped);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('Skip while the answer is being applied is too late, says so, and '
      'the answer applies whole', () async {
    final h = await _harness(verdict: '1: YES\n2: YES', held: false);
    await h.chat.setObjective('Fix the creaky porch board', isPrimary: false);
    expect(h.chat.activeObjectives, hasLength(2));

    // Tap Skip the moment the first quest retires, between the two applies.
    var tapped = false;
    void tapMidApply() {
      if (!tapped && h.chat.activeObjectives.length == 1) {
        tapped = true;
        h.chat.skipObjectiveCheck();
      }
    }

    h.chat.addListener(tapMidApply);
    await h.chat
        .sendMessage('Want some lemonade?')
        .timeout(const Duration(seconds: 10));
    h.chat.removeListener(tapMidApply);

    expect(tapped, isTrue, reason: 'Skip was tapped while applying');
    _expectReplyLanded(h);
    expect(
      h.chat.activeObjectives,
      isEmpty,
      reason: 'both YES verdicts apply: never half while claiming none',
    );
    expect(h.chat.guestActivityStatus, _tooLate);
  }, timeout: const Timeout(Duration(seconds: 60)));

  // 2026-10-16, objectives that keep up: the goal check became a goal sync.
  // It reads where the story is and moves every goal at once, and the
  // changes still ride the reply, so a regen undoes them.
  Future<void> settled(_Harness h) => _until(
    () => !h.chat.isGenerating && !h.chat.isSettlingTurn,
    'the turn to settle',
  );

  Future<_Harness> characterGoal(
    String verdict,
    List<String> steps, {
    bool realism = false,
    bool journal = false,
    String? mood,
  }) async {
    final h = await _harness(
      verdict: verdict,
      held: false,
      realism: realism,
      journal: journal,
      mood: mood,
    );
    await h.chat.clearObjective(h.chat.activeObjectives.single);
    await h.chat.setObjective(
      'Win back her trust',
      origin: kObjectiveOriginCharacter,
    );
    await h.chat.updateCheckFrequency(h.chat.activeObjectives.single, 1);
    for (final s in steps) {
      await h.chat.addManualTask(h.chat.activeObjectives.single, s);
    }
    return h;
  }

  List<(String, bool)> steps(_Harness h) => [
    for (final t in h.chat.tasksForObjective(h.chat.activeObjectives.single))
      (t['description'] as String, t['completed'] == true),
  ];

  test('the goal sync ticks steps out of order, rewrites the character\'s '
      'next step, and regen puts the steps back', () async {
    final h = await characterGoal(
      '1: on_track | 3,1 | Ask what she is reading',
      ['Pour two glasses', 'Pat the swing seat', 'Tell the porch board story'],
    );
    final before = steps(h);

    await h.chat
        .sendMessage('Want some lemonade?')
        .timeout(const Duration(seconds: 10));
    await settled(h);
    expect(steps(h), [
      ('Pour two glasses', true),
      ('Ask what she is reading', false),
      ('Tell the porch board story', true),
    ]);

    await h.chat.regenerateLastMessage().timeout(const Duration(seconds: 10));
    await settled(h);
    expect(steps(h), before, reason: 'the sync rode the rejected reply');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a goal the sync sets aside is marked so, and regen wakes it', () async {
    final h = await characterGoal('1: dormant | none | none', ['Pour two']);

    await h.chat
        .sendMessage('Want some lemonade?')
        .timeout(const Duration(seconds: 10));
    await settled(h);
    expect(h.chat.activeObjectives.single.status, kObjectiveStatusDormant);

    await h.chat.regenerateLastMessage().timeout(const Duration(seconds: 10));
    await settled(h);
    expect(h.chat.activeObjectives.single.status, isNull);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('two weeks skipped re-plans the goals past the cadence, says how long '
      'it has been, and the last sync survives a reload', () async {
    // No word of this goal is in the chat, so only the cadence or the skip
    // can start a sync (the canned reply mentions lemonade).
    final h = await characterGoal('1: on_track | none | none', ['Oil a hinge']);
    final charId = h.chat.activeObjectives.single.characterId;

    await h.chat
        .sendMessage('Want some lemonade?')
        .timeout(const Duration(seconds: 10));
    await settled(h);
    expect(h.backend.objectiveCheckRequests, 1);
    expect(lastObjectiveSyncStamp(h.chat.messages, charId), isNotNull);

    await h.chat.updateCheckFrequency(h.chat.activeObjectives.single, 50);
    await h.chat
        .sendMessage('The crickets are loud tonight.')
        .timeout(const Duration(seconds: 10));
    await settled(h);
    expect(h.backend.objectiveCheckRequests, 1, reason: 'off the cadence');

    await h.chat
        .sendMessage('*Two weeks later, I knock on the door again.*')
        .timeout(const Duration(seconds: 10));
    await settled(h);
    expect(h.backend.objectiveCheckRequests, 2, reason: 'the skip re-plans');
    expect(
      h.backend.objectiveCheckPrompts.last,
      contains('About 2 weeks have passed since these goals were last'),
    );

    final stamp = lastObjectiveSyncStamp(h.chat.messages, charId)!;
    expect(stamp.day, h.chat.timeService.dayCount);
    await h.chat.loadSession(h.chat.currentSessionId!);
    expect(
      lastObjectiveSyncStamp(h.chat.messages, charId)?.clockIso,
      stamp.clockIso,
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  // 2026-10-16, objectives that keep up part 6: a character feels and
  // remembers how a goal of their own ended. "Check now" runs the sync with
  // no mood judge after it, so the feeling it leaves is the goal's.
  Future<List<String>> goalCards(_Harness h) async => [
    for (final c in await h.db.getJournalCardsForSession(
      h.chat.currentSessionId!,
    ))
      if (c.content.startsWith('I pulled it off') ||
          c.content.startsWith('I had to give up'))
        c.content,
  ];

  Future<void> checkNow(_Harness h) async {
    h.chat.forceCheckCompletion();
    await _until(
      () =>
          h.backend.objectiveCheckRequests == 1 && !h.chat.isCheckingCompletion,
      'the goal sync to finish',
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  test('winning a goal of their own makes them proud, writes a diary card '
      'and counts on the tally', () async {
    final h = await characterGoal(
      '1: done | 1 | none',
      ['Pour two glasses'],
      realism: true,
      journal: true,
    );
    await checkNow(h);
    expect(h.chat.activeObjectives, isEmpty);
    expect(h.chat.characterEmotion, 'proud');
    expect(h.chat.emotionIntensity, 'strong', reason: 'it was the main goal');
    expect(h.chat.emotionCause, 'pulled off: Win back her trust');
    expect(await goalCards(h), ['I pulled it off: Win back her trust.']);
    expect(h.chat.objectiveTally.label, '1 landed');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a stronger feeling already standing stays; the win is still '
      'remembered and counted', () async {
    final h = await characterGoal(
      '1: done | 1 | none',
      ['Pour two glasses'],
      realism: true,
      journal: true,
      mood: 'furious',
    );
    expect(h.chat.characterEmotion, 'furious');
    await checkNow(h);
    expect(h.chat.characterEmotion, 'furious');
    expect(await goalCards(h), hasLength(1));
    expect(h.chat.objectiveTally.label, '1 landed');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a goal the user set earns the character nothing', () async {
    final h = await _harness(
      verdict: '1: done | none | none',
      held: false,
      realism: true,
      journal: true,
    );
    final before = h.chat.characterEmotion;
    await checkNow(h);
    expect(h.chat.activeObjectives, isEmpty, reason: 'the goal still ends');
    expect(h.chat.characterEmotion, before);
    expect(await goalCards(h), isEmpty);
    expect(h.chat.objectiveTally.isEmpty, isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('regenerating the reply takes back the diary card and the tally with '
      'the goal', () async {
    final h = await characterGoal('1: done | 1 | none', [
      'Pour two glasses',
    ], journal: true);
    await h.chat
        .sendMessage('Want some lemonade?')
        .timeout(const Duration(seconds: 10));
    await settled(h);
    expect(h.chat.activeObjectives, isEmpty);
    expect(await goalCards(h), hasLength(1));
    expect(h.chat.objectiveTally.label, '1 landed');

    h.backend.objectiveCheckVerdict = '1: on_track | none | none';
    await h.chat.regenerateLastMessage().timeout(const Duration(seconds: 10));
    await settled(h);
    expect(h.chat.activeObjectives.single.objective, 'Win back her trust');
    expect(await goalCards(h), isEmpty);
    expect(h.chat.objectiveTally.isEmpty, isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('deleting the reply takes back the diary card and the tally with the '
      'goal', () async {
    final h = await characterGoal('1: done | 1 | none', [
      'Pour two glasses',
    ], journal: true);
    await h.chat
        .sendMessage('Want some lemonade?')
        .timeout(const Duration(seconds: 10));
    await settled(h);
    expect(await goalCards(h), hasLength(1));

    await h.chat.deleteMessage(h.chat.messages.length - 1);
    await settled(h);
    expect(h.chat.activeObjectives.single.objective, 'Win back her trust');
    expect(await goalCards(h), isEmpty);
    expect(h.chat.objectiveTally.isEmpty, isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
