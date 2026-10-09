// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Planner's today line in a group chat. The line belongs to the chat
// (one per chat, stored on the session); its side-quest row belongs to the
// member whose reply wrote it. Before the fix a group ran its objective
// reload through the 1:1 loader, which reads "no active character" as "no
// chat" and dropped the held line: a Director turn's line never showed, a
// sidebar edit between turns wiped it, and after reopening the chat the
// line only came back if its owner happened to speak next (and a new line
// from someone else left the old row open beside it).
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_group_today_').path;
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

  /// Open the group the way the app does on launch: a fresh ChatService
  /// on the same library.
  Future<ChatService> open() async {
    chat?.dispose();
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
    await c.setActiveGroup(
      GroupChat(id: 'grp', name: 'Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );
    await c.setRealismEnabled(true);
    return c;
  }

  Future<List<Objective>> activeTodayRows(ChatService c) async {
    final rows = await (db.select(
      db.objectives,
    )..where((o) => o.chatId.equals(c.currentSessionId!))).get();
    return rows
        .where(
          (o) => o.active && (o.objective == _swing || o.objective == _mailbox),
        )
        .toList();
  }

  String memberId(ChatService c, String name) =>
      c.characterIdFor(c.groupCharacters.firstWhere((m) => m.name == name));

  test(
    'a Director turn holds its today line on the speaker, and the next turn keeps it',
    () async {
      final c = await open();
      c.setObserverMode(true);
      llm.todayLine = _swing;
      await c.triggerNextCharacter();
      final speaker = c.messages.last.sender;

      expect(c.todaySentence, _swing, reason: 'the line is held');
      final heldId = c.todayObjectiveId;
      expect(heldId, isNotNull);
      final rows = await activeTodayRows(c);
      expect(rows.single.id, heldId);
      expect(
        rows.single.characterId,
        memberId(c, speaker),
        reason: 'the row is the speaker\'s, not the next member\'s',
      );

      llm.todayLine = null;
      await c.triggerNextCharacter();
      expect(c.messages.last.sender, isNot(speaker));
      expect(c.todaySentence, _swing, reason: 'the next turn keeps it');
      expect(c.todayObjectiveId, heldId);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a side quest added between turns keeps the today line', () async {
    final c = await open();
    llm.todayLine = _swing;
    await c.sendMessage('Evening, both of you.');
    expect(c.todaySentence, _swing);
    final heldId = c.todayObjectiveId;

    // Reopen, then add a side quest from the sidebar before anyone speaks.
    final again = await open();
    final rue = again.groupCharacters.firstWhere((m) => m.name == 'Rue');
    await again.setObjective(
      'Find the lost cat.',
      isPrimary: false,
      targetCharacter: rue,
    );
    expect(again.todaySentence, _swing);
    expect(again.todayObjectiveId, heldId);

    llm.todayLine = null;
    await again.sendMessage('Anyone hungry?');
    expect(again.todaySentence, _swing, reason: 'and the turn after it');
    expect(again.todayObjectiveId, heldId);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'reopened, the line shows whoever speaks next, and a new line replaces it',
    () async {
      var c = await open();
      await c.sendMessage('Evening.'); // Nia
      llm.todayLine = _swing;
      await c.triggerNextCharacter(); // Rue writes the line
      expect(c.messages.last.sender, 'Rue');
      final swingId = c.todayObjectiveId;
      expect(swingId, isNotNull);

      c = await open();
      expect(c.nextCharacter?.name, 'Nia', reason: 'not the line\'s owner');
      expect(c.todaySentence, _swing, reason: 'the chat\'s line shows');
      expect(c.todayObjectiveId, swingId);

      llm.todayLine = _mailbox;
      await c.sendMessage('What is the plan for today?'); // Nia
      expect(c.todaySentence, _mailbox);
      final rows = await activeTodayRows(c);
      expect(rows.map((o) => o.objective), [
        _mailbox,
      ], reason: 'one today row: the old one is retired, the new one written');
      expect(rows.single.id, c.todayObjectiveId);
      expect(rows.single.characterId, memberId(c, 'Nia'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
