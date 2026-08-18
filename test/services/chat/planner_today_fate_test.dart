// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Planner V2 locks: abandon sours with no card; done/dayAte write
// kind today / category moment; todaySentence getter does not
// day-clear; TimeService.onStoryDayChanged journals then clears.
// Real mixin + real PlannerTodayFate — not FakeChatService.abandonToday.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

final Directory _root = Directory.systemTemp.createTempSync(
  'fpai_planner_fate_',
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

class _TodayHarness extends ChangeNotifier with ChatServiceTodaySentence {}

String? _kindOf(JournalMemoryData card) {
  final raw = card.metadata;
  if (raw == null || raw.isEmpty) return null;
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return null;
  return decoded['kind'] as String?;
}

Future<void> _drain([int n = 30]) async {
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
          ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;
    await storage.realismSettings.setPlannerEnabled(true);
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  CharacterCard card() => CharacterCard(
    name: 'Ada',
    description: 'Exists only inside the planner fate lock.',
    firstMessage: 'The screen door bangs shut behind you.',
  )..dbId = 'char-planner-fate';

  Future<List<JournalMemoryData>> cardsFor(ChatService c, CharacterCard who) {
    return c.journalStore.cardsFor(c.currentSessionId!, c.characterIdFor(who));
  }

  test('abandonToday sours and writes no journal card', () async {
    final src = File(
      'lib/services/chat/chat_service_accessors.dart',
    ).readAsStringSync();
    expect(src, contains('enum PlannerTodayFate { done, abandoned, dayAte }'));
    expect(src, contains('if (fate == PlannerTodayFate.abandoned) return;'));
    expect(src, contains("category: 'moment'"));
    expect(src, contains("kind: 'today'"));
    expect(
      src,
      contains(
        'unawaited(_journalResolvedToday(held, fate: PlannerTodayFate.abandoned))',
      ),
    );

    final who = card();
    await chat.setActiveCharacter(who);
    expect(chat.currentSessionId, isNotNull);
    expect(storage.realismSettings.plannerEnabled, isTrue);

    chat.setTodaySentence('Hold the porch light.');
    expect(chat.todaySentence, 'Hold the porch light.');

    chat.abandonToday();
    await _drain();

    expect(chat.todaySentence, isNull);
    expect(chat.characterEmotion, 'annoyed');
    expect(await cardsFor(chat, who), isEmpty);
  });

  test('done and dayAte journal kind today category moment', () async {
    final accessors = File(
      'lib/services/chat/chat_service_accessors.dart',
    ).readAsStringSync();
    final start = accessors.indexOf('Future<void> _journalResolvedToday(');
    expect(start, greaterThanOrEqualTo(0));
    final body = accessors.substring(
      start,
      start + 900 > accessors.length ? accessors.length : start + 900,
    );
    expect(body, contains('if (fate == PlannerTodayFate.abandoned) return;'));
    expect(body, contains("category: 'moment'"));
    expect(body, contains("kind: 'today'"));

    final wiringDone = File(
      'lib/services/chat/chat_service_wiring_realism.dart',
    ).readAsStringSync();
    expect(
      wiringDone,
      contains('_journalResolvedToday(prev, fate: PlannerTodayFate.done)'),
    );

    final wiring = File(
      'lib/services/chat/chat_service_wiring_realism.dart',
    ).readAsStringSync();
    expect(
      wiring,
      contains('_journalResolvedToday(held, fate: PlannerTodayFate.dayAte)'),
    );

    final who = card();
    await chat.setActiveCharacter(who);
    chat.setTodaySentence('Finish the lighthouse log.');

    await chat.timeService.evaluateTimeProgressAndPostureIfNeeded(
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
          '{"minutes_elapsed": 5, "new_day": false, "today_sentence": "Sweep the stoop before dusk."}',
    );
    await _drain(40);

    expect(chat.todaySentence, 'Sweep the stoop before dusk.');
    expect(chat.characterEmotion, 'content');
    final doneCards = await cardsFor(chat, who);
    expect(doneCards, hasLength(1));
    expect(doneCards.single.content, 'Finish the lighthouse log.');
    expect(doneCards.single.category, 'moment');
    expect(_kindOf(doneCards.single), 'today');

    chat.setTodaySentence('Hold the porch light.');
    final before = chat.timeService.clock;
    chat.timeService.setClockDirect(before.add(const Duration(days: 1)));
    await _drain();

    expect(chat.todaySentence, isNull);
    final afterDay = await cardsFor(chat, who);
    expect(afterDay, hasLength(2));
    final dayAte = afterDay.firstWhere(
      (c) => c.content == 'Hold the porch light.',
    );
    expect(dayAte.category, 'moment');
    expect(_kindOf(dayAte), 'today');
  });

  test('todaySentence getter does not day-clear', () {
    final accessors = File(
      'lib/services/chat/chat_service_accessors.dart',
    ).readAsStringSync();
    expect(accessors, contains('String? get todaySentence => _todaySentence;'));
    final getter = RegExp(
      r'String\? get todaySentence =>[^;]+;',
    ).firstMatch(accessors);
    expect(getter, isNotNull);
    expect(getter!.group(0), isNot(contains('dayCount')));
    expect(getter.group(0), isNot(contains('setTodaySentence')));
    expect(getter.group(0), isNot(contains('_journalResolvedToday')));

    final held = _TodayHarness();
    addTearDown(held.dispose);
    held.setTodaySentence('Hold the porch light.');
    expect(held.todaySentence, 'Hold the porch light.');
    expect(held.todaySentence, 'Hold the porch light.');

    chat.setTodaySentence('Finish the lighthouse log.');
    expect(chat.todaySentence, 'Finish the lighthouse log.');
    expect(chat.todaySentence, 'Finish the lighthouse log.');
  });

  test('TimeService onStoryDayChanged journals dayAte then clears', () async {
    final wiring = File(
      'lib/services/chat/chat_service_wiring_realism.dart',
    ).readAsStringSync();
    final hook = RegExp(
      r'onStoryDayChanged: \(\) \{([\s\S]*?)\n      \},',
    ).firstMatch(wiring);
    expect(
      hook,
      isNotNull,
      reason: 'clock hook must stay on TimeService wiring',
    );
    final hookBody = hook!.group(1)!;
    expect(hookBody, contains('final held = todaySentence;'));
    expect(hookBody, contains('setTodaySentence(null);'));
    expect(
      hookBody,
      contains('_journalResolvedToday(held, fate: PlannerTodayFate.dayAte)'),
    );
    expect(
      hookBody.indexOf('final held = todaySentence;'),
      lessThan(hookBody.indexOf('setTodaySentence(null);')),
    );
    expect(
      hookBody.indexOf('setTodaySentence(null);'),
      lessThan(hookBody.indexOf('_journalResolvedToday(held')),
    );

    final who = card();
    await chat.setActiveCharacter(who);
    const line = 'Hold the porch light.';
    chat.setTodaySentence(line);
    expect(chat.todaySentence, line);
    expect(chat.todaySentence, line);

    final before = chat.timeService.clock;
    chat.timeService.setClockDirect(before.add(const Duration(days: 1)));
    expect(chat.todaySentence, isNull);
    await _drain();

    final cards = await cardsFor(chat, who);
    expect(cards, hasLength(1));
    expect(cards.single.content, line);
    expect(cards.single.category, 'moment');
    expect(_kindOf(cards.single), 'today');
    expect(chat.characterEmotion, 'annoyed');
  });
}
