// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Today is one secondary objective on the existing tracker. Match by
// held id. Never primary, never tasks, never an ambition.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/chat/today_line_tag.dart';
import 'package:front_porch_ai/services/services.dart';

final Directory _root = Directory.systemTemp.createTempSync(
  'fpai_today_quest_',
);

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return _root.path;
        }
        return null;
      });
}

class _YesLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '1: YES';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'YesLlm';
}

Future<void> _drain([int n = 40]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = _YesLlm();
    await storage.initialized;
    await storage.realismSettings.setPlannerEnabled(true);
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  CharacterCard card() => CharacterCard(
    name: 'Ada',
    description: 'Exists only inside the today side-quest lock.',
    firstMessage: 'The screen door bangs shut behind you.',
  )..dbId = 'char-today-quest';

  Future<void> fireToday(ChatService c, String sentence) async {
    await c.timeService.evaluateTimeProgressAndPostureIfNeeded(
      charName: 'Ada',
      recent: 'User: What are you doing?\nAda: She stacks the books.',
      shortTermTierName: 'Warm',
      onChunk: null,
      fireLLMEval: (p, {onChunk}) async => null,
      stripThinkBlocks: (s) => s,
      extractJsonBool: (raw, key) {
        final m = RegExp('"' + key + r'"\s*:\s*(true|false)').firstMatch(raw);
        return m == null ? null : m.group(1) == 'true';
      },
      setSpatialStance: (_) {},
      getCurrentSpatialStance: () => '',
      getCharacterEmotion: () => '',
      getEmotionIntensity: () => '',
      oneShotMode: true,
      oneShotText:
          '{"minutes_elapsed": 5, "new_day": false, "today_sentence": "$sentence"}',
    );
    for (var i = 0; i < 400; i++) {
      await Future<void>.delayed(Duration.zero);
      if (c.todayObjectiveId != null &&
          c.activeObjectives.any(
            (o) => o.id == c.todayObjectiveId && o.objective == sentence,
          )) {
        break;
      }
    }
    await _drain();
  }

  Future<List<Objective>> allRows(ChatService c, CharacterCard who) {
    return db.getObjectivesForCharacter(
      c.characterIdFor(who),
      chatId: c.currentSessionId,
    );
  }

  Objective todayRow(ChatService c) {
    final id = c.todayObjectiveId;
    expect(id, isNotNull);
    return c.activeObjectives.singleWhere((o) => o.id == id);
  }

  test('spawn writes one secondary with empty tasks and no ambition', () async {
    final who = card();
    await chat.setActiveCharacter(who);
    await fireToday(chat, 'Sweep the stoop before dusk.');

    expect(chat.todaySentence, 'Sweep the stoop before dusk.');
    expect(chat.todayObjectiveId, isNotNull);
    final row = todayRow(chat);
    expect(row.isPrimary, isFalse);
    expect(row.servedAmbition, isNull);
    expect(row.tasks, '[]');
    expect(row.active, isTrue);
    expect(row.objective, 'Sweep the stoop before dusk.');
    expect(chat.primaryObjective, isNull);
    expect(chat.secondaryObjectives, hasLength(1));
  });

  test('same sentence does not spawn a duplicate', () async {
    final who = card();
    await chat.setActiveCharacter(who);
    await fireToday(chat, 'Sweep the stoop before dusk.');
    final id = chat.todayObjectiveId;
    await fireToday(chat, 'Sweep the stoop before dusk.');

    expect(chat.todayObjectiveId, id);
    expect(chat.activeObjectives, hasLength(1));
    expect(chat.activeObjectives.single.id, id);
  });

  test('new sentence retires the old today-row and inserts the new one', () async {
    final who = card();
    await chat.setActiveCharacter(who);
    await fireToday(chat, 'Sweep the stoop before dusk.');
    final oldId = chat.todayObjectiveId!;
    await fireToday(chat, 'Hold the porch light.');

    expect(chat.todaySentence, 'Hold the porch light.');
    expect(chat.todayObjectiveId, isNotNull);
    expect(chat.todayObjectiveId, isNot(oldId));
    final live = todayRow(chat);
    expect(live.objective, 'Hold the porch light.');
    expect(live.isPrimary, isFalse);
    expect(live.servedAmbition, isNull);
    expect(live.tasks, '[]');

    final rows = await allRows(chat, who);
    final retired = rows.singleWhere((o) => o.id == oldId);
    expect(retired.active, isFalse);
    expect(retired.isPrimary, isFalse);
  });

  test('abandonToday deactivates the today-row and does not complete it', () async {
    final who = card();
    await chat.setActiveCharacter(who);
    await fireToday(chat, 'Sweep the stoop before dusk.');
    final id = chat.todayObjectiveId!;
    chat.abandonToday();
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(Duration.zero);
      if (chat.todayObjectiveId == null &&
          chat.activeObjectives.every((o) => o.id != id)) {
        break;
      }
    }
    await _drain();

    expect(chat.todaySentence, isNull);
    expect(chat.todayObjectiveId, isNull);
    expect(chat.characterEmotion, 'annoyed');
    expect(chat.activeObjectives, isEmpty);
    final retired = (await allRows(chat, who)).singleWhere((o) => o.id == id);
    expect(retired.active, isFalse);
    expect(retired.isPrimary, isFalse);
    expect(retired.servedAmbition, isNull);
    expect(retired.tasks, '[]');
    final cards = await chat.journalStore.cardsFor(
      chat.currentSessionId!,
      chat.characterIdFor(who),
    );
    expect(cards, isEmpty);
  });

  test('day-roll miss deactivates and does not mark complete', () async {
    final who = card();
    await chat.setActiveCharacter(who);
    await fireToday(chat, 'Hold the porch light.');
    final id = chat.todayObjectiveId!;
    await chat.timeService.setClockDirect(
      chat.timeService.clock.add(const Duration(days: 1)),
    );
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(Duration.zero);
      if (chat.todayObjectiveId == null &&
          chat.activeObjectives.every((o) => o.id != id)) {
        break;
      }
    }
    await _drain();

    expect(chat.todaySentence, isNull);
    expect(chat.todayObjectiveId, isNull);
    expect(chat.characterEmotion, 'annoyed');
    final retired = (await allRows(chat, who)).singleWhere((o) => o.id == id);
    expect(retired.active, isFalse);
    expect(retired.isPrimary, isFalse);
  });

  test('complete keeps secondary shape and does not serve an ambition', () async {
    final wiring = File(
      'lib/services/chat/chat_service_wiring_evals.dart',
    ).readAsStringSync();
    expect(wiring, contains('if (_isHeldTodayObjective(obj))'));
    expect(wiring, contains('unawaited(_onTodayObjectiveCompleted(obj));'));
    expect(
      wiring.indexOf('if (_isHeldTodayObjective(obj))'),
      lessThan(wiring.indexOf('_ambitionService.onQuestAchieved')),
    );

    final who = card();
    await chat.setActiveCharacter(who);
    await fireToday(chat, 'Sweep the stoop before dusk.');
    final todayId = chat.todayObjectiveId!;
    expect(chat.primaryObjective, isNull);
    expect(todayRow(chat).isPrimary, isFalse);

    chat.forceCheckCompletion();
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(Duration.zero);
      if (chat.todayObjectiveId == null && chat.todaySentence == null) {
        break;
      }
    }
    await _drain(20);

    expect(chat.todaySentence, isNull);
    expect(chat.todayObjectiveId, isNull);
    expect(chat.characterEmotion, 'content');
    expect(chat.primaryObjective, isNull);

    final done = (await allRows(chat, who)).singleWhere((o) => o.id == todayId);
    expect(done.active, isFalse);
    expect(done.isPrimary, isFalse);
    expect(done.servedAmbition, isNull);
    expect(done.tasks, '[]');

    final cards = await chat.journalStore.cardsFor(
      chat.currentSessionId!,
      chat.characterIdFor(who),
    );
    expect(cards.any((c) => c.content == 'Sweep the stoop before dusk.'), isTrue);
  });

  test('today insert does not evict other secondaries or steal primary', () async {
    final who = card();
    await chat.setActiveCharacter(who);
    await chat.setObjective('Main quest', isPrimary: true);
    await chat.setObjective('Side one', isPrimary: false);
    await chat.setObjective('Side two', isPrimary: false);
    final before = chat.activeObjectives.map((o) => o.id).toSet();
    expect(chat.primaryObjective?.objective, 'Main quest');
    expect(chat.secondaryObjectives, hasLength(2));

    await fireToday(chat, 'Sweep the stoop before dusk.');
    expect(chat.primaryObjective?.objective, 'Main quest');
    expect(chat.todayObjectiveId, isNotNull);
    expect(chat.secondaryObjectives.length, greaterThanOrEqualTo(3));
    for (final id in before) {
      expect(chat.activeObjectives.any((o) => o.id == id), isTrue);
    }
    final row = todayRow(chat);
    expect(row.isPrimary, isFalse);
    expect(row.servedAmbition, isNull);
    expect(row.tasks, '[]');
  });

  test('1:1 Away and At work never skip still holds', () {
    final skipSrc = File(
      'lib/services/chat/chat_service_turn_flow.dart',
    ).readAsStringSync();
    final skipFn = RegExp(
      r'bool _groupSpeakerSkips\(CharacterCard card\) \{([\s\S]*?)\n  \}',
    ).firstMatch(skipSrc);
    expect(skipFn, isNotNull);
    expect(skipFn!.group(1)!, contains('if (_activeGroup == null) return false;'));
    expect(skipFn.group(1)!, contains('return groupTurnSkips(where);'));
  });

  test('proposed_objective matching today_sentence is a collision', () {
    const payload =
        '{"today_sentence": "Sweep the stoop before dusk.", "proposed_objective": "Sweep the stoop before dusk."}';
    expect(
      TodayLineTag.proposedCollidesWithToday(
        'Sweep the stoop before dusk.',
        payload,
      ),
      isTrue,
    );
    expect(
      TodayLineTag.proposedCollidesWithToday('Climb the mountain', payload),
      isFalse,
    );
  });

  test('new chat + same sentence inserts in the new session', () async {
    final who = card();
    await chat.setActiveCharacter(who);
    await fireToday(chat, 'Sweep the stoop before dusk.');
    final oldSid = chat.currentSessionId;
    final oldId = chat.todayObjectiveId;
    expect(oldSid, isNotNull);
    expect(oldId, isNotNull);

    await chat.startNewChat();
    await _drain();
    expect(chat.currentSessionId, isNot(oldSid));
    expect(chat.todayObjectiveId, isNull);

    await fireToday(chat, 'Sweep the stoop before dusk.');
    expect(chat.todayObjectiveId, isNotNull);
    expect(chat.todayObjectiveId, isNot(oldId));
    expect(chat.currentSessionId, isNot(oldSid));

    final oldRows = await db.getObjectivesForCharacter(
      chat.characterIdFor(who),
      chatId: oldSid,
    );
    expect(oldRows.where((o) => o.id == oldId && o.active).length, 1);
    final newRows = await allRows(chat, who);
    expect(newRows.where((o) => o.id == chat.todayObjectiveId && o.active).length, 1);
  });

  test('new chat + new sentence leaves the previous session row active', () async {
    final who = card();
    await chat.setActiveCharacter(who);
    await fireToday(chat, 'Sweep the stoop before dusk.');
    final oldSid = chat.currentSessionId;
    final oldId = chat.todayObjectiveId;

    await chat.startNewChat();
    await _drain();
    await fireToday(chat, 'Water the geraniums.');
    expect(chat.todayObjectiveId, isNot(oldId));
    expect(todayRow(chat).objective, 'Water the geraniums.');

    final oldRows = await db.getObjectivesForCharacter(
      chat.characterIdFor(who),
      chatId: oldSid,
    );
    expect(oldRows.where((o) => o.id == oldId && o.active).length, 1);
  });

  test('today plus a user side quest rebinds on loadSession', () async {
    final who = card();
    await chat.setActiveCharacter(who);
    await chat.setObjective('Buy milk on the way home', isPrimary: false);
    await fireToday(chat, 'Sweep the stoop before dusk.');
    final sid = chat.currentSessionId!;
    final held = chat.todayObjectiveId!;
    final sideId = chat.secondaryObjectives
        .firstWhere((o) => o.id != held)
        .id;
    expect(chat.secondaryObjectives, hasLength(2));

    await chat.startNewChat();
    await _drain();
    expect(chat.todayObjectiveId, isNull);
    expect(chat.todaySentence, isNull);

    await chat.loadSession(sid);
    await _drain();
    expect(chat.currentSessionId, sid);
    expect(chat.todayObjectiveId, held);
    expect(chat.todaySentence, 'Sweep the stoop before dusk.');
    expect(chat.activeObjectives.any((o) => o.id == sideId && o.active), isTrue);

    await fireToday(chat, 'Water the geraniums.');
    expect(chat.todayObjectiveId, isNot(held));
    expect(chat.todaySentence, 'Water the geraniums.');
    final rows = await allRows(chat, who);
    expect(rows.where((o) => o.id == held).single.active, isFalse);
    expect(rows.where((o) => o.id == sideId).single.active, isTrue);
    expect(
      rows.where((o) => o.active && !o.isPrimary).map((o) => o.id).toSet(),
      {sideId, chat.todayObjectiveId},
    );
  });

  test('held today is the persisted id, never every taskless secondary', () {
    final evals = File(
      'lib/services/chat/chat_service_wiring_evals.dart',
    ).readAsStringSync();
    expect(evals, contains('if (_isHeldTodayObjective(obj))'));
    final accessors = File(
      'lib/services/chat/chat_service_accessors.dart',
    ).readAsStringSync();
    expect(accessors, contains('bool _isHeldTodayObjective(Objective obj)'));
    expect(
      accessors,
      contains('return _todayObjectiveId != null && obj.id == _todayObjectiveId;'),
    );
    expect(accessors, contains('_persistTodayObjectiveId'));
    expect(accessors, isNot(contains('claimIfUnique')));
  });

  test('session change clears the today pointer then rebinds', () {
    final start = File(
      'lib/services/chat/chat_service_session_manage.dart',
    ).readAsStringSync();
    expect(start, contains('_clearTodayPointer();'));
    final load = File(
      'lib/services/chat/chat_service_session_load.dart',
    ).readAsStringSync();
    expect(load, contains('_clearTodayPointer();'));
    expect(load, contains('_todayObjectiveId = s.todayObjectiveId;'));
    final objs = File(
      'lib/services/chat/chat_service_objectives.dart',
    ).readAsStringSync();
    expect(objs, contains('_rebindTodayObjectiveFromDb();'));
    expect(objs, contains('_clearTodayPointer();'));
  });

}
