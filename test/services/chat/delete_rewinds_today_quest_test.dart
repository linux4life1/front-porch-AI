// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A reply's turn finished the held today quest (its Journal card written,
// mood nudged to content) and the post-reply clock pass held a new today
// line. Deleting or regenerating that reply must take all of it back: the
// finished quest open and held again, the new quest gone, the card gone,
// and (delete) the mood back where the last accepted reply left it. Before
// the fix only the finished quest's status came back.
//
// Real ChatService and database. The model is scripted per prompt only to
// stage the scene (a YES verdict, a new today line); every assertion reads
// what the app did when the reply was taken away.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/chat_db_teardown.dart';

const _oldLine =
    'Carmen and the user are enjoying tea and peaches on the porch.';
const _newLine =
    'They are enjoying tea and peaches on the porch, savoring the evening.';

class _PorchScene extends LLMService {
  bool questDone = false;
  String? nextTodayLine;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('Objective to evaluate')) {
      yield questDone ? '1: YES' : '1: NO';
      return;
    }
    if (p.contains('"minutes_elapsed"')) {
      final today = nextTodayLine == null
          ? ''
          : ', "today_sentence": "$nextTodayLine"';
      yield '{"minutes_elapsed": 5, "continuous_instant": false, '
          '"new_day": false$today}';
      return;
    }
    yield 'Carmen pours the tea and hands you a peach on the porch.';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'porch-scene';
}

class _SceneProvider extends FakeLLMProvider {
  _SceneProvider(this._service) : super(activeBackend: BackendType.openRouter);

  final LLMService _service;
  final OpenRouterService _remote = OpenRouterService();

  @override
  LLMService get activeService => _service;

  @override
  OpenRouterService get openRouterService => _remote;

  @override
  void dispose() {
    _remote.dispose();
    super.dispose();
  }
}

Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _untilAsync(Future<bool> Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!await done()) {
    if (DateTime.now().isAfter(deadline)) return; // the expects name it
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_today_rewind_').path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _PorchScene llm;
  late _SceneProvider provider;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'pockets_enabled': false,
      'journal_enabled': true,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    llm = _PorchScene();
    provider = _SceneProvider(llm);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..setLLMProvider(provider)
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    await storage.backendSettings.setAutostartOnChatOpen(false);
    await storage.realismSettings.setPlannerEnabled(true);
    await storage.realismSettings.setPassageOfTimeDefault(true);
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Carmen',
        description: 'Exists only inside the today-quest rewind test.',
        firstMessage: 'Carmen sets two glasses of tea on the porch rail.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          characterEmotion: 'wistful',
        ),
      )..dbId = 'char-carmen-rewind',
    );
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    provider.dispose();
  });

  Future<Objective?> row(String id) => (db.select(
    db.objectives,
  )..where((o) => o.id.equals(id))).getSingleOrNull();

  Future<List<JournalMemoryData>> todayCards() async {
    final cards = await db.getJournalCardsForSession(chat.currentSessionId!);
    return cards.where((c) => c.content == _oldLine).toList();
  }

  /// Hold the old line (outside any turn, as an earlier turn left it), take
  /// one ordinary turn, then the turn that finishes the quest and holds a
  /// new line. Returns the two quest ids and the mood before that turn.
  Future<(String, String, String)> playFinishingTurn() async {
    await chat.timeService.evaluateTimeProgressAndPostureIfNeeded(
      charName: 'Carmen',
      recent: 'User: Tea?\nCarmen: Peaches too.',
      shortTermTierName: 'Warm',
      onChunk: null,
      fireLLMEval: (p, {onChunk}) async => null,
      stripThinkBlocks: (s) => s,
      extractJsonBool: (raw, key) => null,
      setSpatialStance: (_) {},
      getCurrentSpatialStance: () => '',
      getCharacterEmotion: () => '',
      getEmotionIntensity: () => '',
      oneShotMode: true,
      oneShotText: '{"minutes_elapsed": 5, "today_sentence": "$_oldLine"}',
    );
    await _until(() => chat.todayObjectiveId != null, 'the held today quest');
    final oldId = chat.todayObjectiveId!;

    await chat.sendMessage('I bring the tea and peaches out to the porch.');
    await _until(() => !chat.isSettlingTurn, 'turn 1 to settle');
    final moodBefore = chat.characterEmotion;
    expect(moodBefore, 'wistful', reason: "baseline: the card's mood");
    expect(chat.todayObjectiveId, oldId, reason: 'turn 1 changes nothing');

    llm
      ..questDone = true
      ..nextTodayLine = _newLine;
    await chat.sendMessage('We sit with our tea and peaches on the porch.');
    await _until(() => !chat.isSettlingTurn, 'turn 2 to settle');
    await _until(
      () => chat.todayObjectiveId != null && chat.todayObjectiveId != oldId,
      'the new today quest',
    );
    final newId = chat.todayObjectiveId!;
    expect((await row(oldId))!.active, isFalse, reason: 'baseline: finished');
    expect((await row(newId))!.objective, _newLine);
    await _untilAsync(() async => (await todayCards()).isNotEmpty);
    expect(await todayCards(), hasLength(1), reason: 'baseline: card written');
    expect(chat.characterEmotion, 'content', reason: 'baseline: mood nudged');
    llm
      ..questDone = false
      ..nextTodayLine = null;
    return (oldId, newId, moodBefore);
  }

  Future<void> expectTurnUndone(String oldId, String newId) async {
    await _untilAsync(
      () async =>
          await row(newId) == null &&
          (await todayCards()).isEmpty &&
          chat.todayObjectiveId == oldId,
    );
    expect((await row(oldId))?.active, isTrue, reason: 'finished quest open');
    expect(await row(newId), isNull, reason: 'quest created that turn gone');
    expect(await todayCards(), isEmpty, reason: 'completion card gone');
    expect(chat.todayObjectiveId, oldId, reason: 'old line held again');
    expect(chat.todaySentence, _oldLine);
  }

  test(
    'deleting the reply undoes its finished quest, new quest, card and mood',
    () async {
      final (oldId, newId, moodBefore) = await playFinishingTurn();

      chat.deleteMessage(chat.messages.length - 1);
      await expectTurnUndone(oldId, newId);
      expect(chat.characterEmotion, moodBefore, reason: 'mood rewinds');
    },
  );

  test('regenerating the reply undoes the same', () async {
    final (oldId, newId, _) = await playFinishingTurn();

    await chat.regenerateLastMessage();
    await _until(() => !chat.isSettlingTurn, 'the regen to settle');
    await expectTurnUndone(oldId, newId);
  });
}
