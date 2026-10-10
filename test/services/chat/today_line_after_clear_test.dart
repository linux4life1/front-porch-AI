// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Planner's today line after the user clears it, and whose Journal it
// lands in when it finishes.
//
// Real ChatService and database. The model is scripted per prompt only to
// stage the scene (a reply, a clock answer carrying today_sentence).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

const _swing = 'Fix the porch swing before supper.';
const _mailbox = 'Paint the mailbox green.';

class _PorchScene extends LLMService {
  String? todayLine;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield 'She sets the tea down on the porch rail.';
      return;
    }
    if (params.prompt.contains('minutes_elapsed')) {
      final today = todayLine == null ? '' : ', "today_sentence": "$todayLine"';
      yield '{"minutes_elapsed": 5, "new_day": false$today}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'porch-scene';
}

Future<void> _until(Future<bool> Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!await done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_today_clear_').path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late _PorchScene llm;
  ChatService? chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    llm = _PorchScene();
    chat = null;
    await storage.initialized;
    await storage.backendSettings.setAutostartOnChatOpen(false);
    await storage.realismSettings.setPlannerEnabled(true);
    await storage.realismSettings.setPassageOfTimeDefault(true);
    await db.insertGroup(GroupsCompanion.insert(id: 'grp', name: 'Porch'));
    for (final name in ['Nia', 'Rue']) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-$name',
          groupId: 'grp',
          name: name,
          frontPorchExtensions: const Value(
            '{"realism_engine":{"realism_enabled":true}}',
          ),
        ),
      );
    }
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  ChatService service() {
    final c =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    chat = c;
    return c;
  }

  Future<ChatService> openOneToOne() async {
    final c = service();
    await c.setActiveCharacter(
      CharacterCard(
        name: 'Ada',
        description: 'Exists only inside the today-line clear test.',
        firstMessage: 'The screen door bangs shut behind you.',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      )..dbId = 'char-today-clear',
    );
    await c.setRealismEnabled(true);
    return c;
  }

  Future<ChatService> openGroup() async {
    final c = service();
    await c.setActiveGroup(
      GroupChat(id: 'grp', name: 'Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );
    await c.setRealismEnabled(true);
    return c;
  }

  Future<Objective?> activeRow(ChatService c, String? id) async {
    if (id == null) return null;
    final row = await (db.select(
      db.objectives,
    )..where((o) => o.id.equals(id))).getSingleOrNull();
    return row != null && row.active && row.chatId == c.currentSessionId
        ? row
        : null;
  }

  Future<Objective?> heldRow(ChatService c) => activeRow(c, c.todayObjectiveId);

  /// The quest the line wrote is cleared from the quest list (its X), and a
  /// later turn writes the same line again: it must be a quest again.
  Future<void> clearQuestThenRepeat(ChatService c) async {
    llm.todayLine = _swing;
    await c.sendMessage('Evening.');
    final firstId = c.todayObjectiveId;
    expect((await heldRow(c))?.objective, _swing, reason: 'baseline: held');

    await c.clearObjective((await heldRow(c))!);
    expect(await heldRow(c), isNull, reason: 'baseline: the quest is cleared');

    await c.sendMessage('Still on for the swing?');
    expect(c.todaySentence, _swing);
    final again = await heldRow(c);
    expect(again, isNotNull, reason: 'the same line is a quest again');
    expect(again!.objective, _swing);
    expect(
      again.id,
      isNot(firstId),
      reason: 'a fresh row, not the cleared one',
    );
  }

  test(
    '1:1: a cleared today quest comes back when the line is said again',
    () async => clearQuestThenRepeat(await openOneToOne()),
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'group: a cleared today quest comes back when the line is said again',
    () async => clearQuestThenRepeat(await openGroup()),
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the X on the today line, then a regenerate that says it again, holds a quest',
    () async {
      final c = await openOneToOne();
      llm.todayLine = _swing;
      await c.sendMessage('Evening.');
      await c.sendMessage('Still on for the swing?'); // repeats the line
      final firstId = c.todayObjectiveId;
      expect((await heldRow(c))?.objective, _swing, reason: 'baseline');

      c.abandonToday();
      await _until(
        () async => await activeRow(c, firstId) == null,
        'the X to retire the quest',
      );
      expect(c.todaySentence, isNull, reason: 'baseline: line cleared');

      // The regenerate rewinds the line to where that reply found it (held),
      // and the new reply says it again.
      await c.regenerateLastMessage();
      await _until(() async => !c.isSettlingTurn, 'the regen to settle');
      expect(c.todaySentence, _swing);
      final again = await heldRow(c);
      expect(again, isNotNull, reason: 'the line holds a live quest');
      expect(again!.objective, _swing);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'group: a line finished on another member\'s turn files its card under the line\'s owner',
    () async {
      final c = await openGroup();
      llm.todayLine = _swing;
      await c.sendMessage('Evening.'); // Nia writes the line
      expect(c.messages.last.sender, 'Nia');
      final nia = c.characterIdFor(
        c.groupCharacters.firstWhere((m) => m.name == 'Nia'),
      );
      final rue = c.characterIdFor(
        c.groupCharacters.firstWhere((m) => m.name == 'Rue'),
      );
      expect((await heldRow(c))?.characterId, nia, reason: 'baseline: Nia');

      // Rue's reply moves the day on to a new line: Nia's line is done.
      llm.todayLine = _mailbox;
      await c.triggerNextCharacter();
      expect(c.messages.last.sender, 'Rue');
      expect(c.todaySentence, _mailbox);

      Future<List<JournalMemoryData>> swingCards() async =>
          (await db.getJournalCardsForSession(
            c.currentSessionId!,
          )).where((j) => j.content == _swing).toList();
      await _until(
        () async => (await swingCards()).isNotEmpty,
        'the done card for the swing line',
      );
      final cards = await swingCards();
      expect(cards, hasLength(1));
      expect(
        cards.single.characterId,
        nia,
        reason: 'the card is Nia\'s, whose reply wrote the line',
      );
      expect(cards.single.characterId, isNot(rue));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
