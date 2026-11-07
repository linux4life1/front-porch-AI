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

// The Chat Distiller against a REAL StoryPipelineService and in-memory DB:
// a chat's Journal cards and Growth Rings must reach the distiller in the
// stretch of messages they were recorded against, and close the stored
// timeline. The model here only records what it is asked; every assertion
// is on what the product sent or stored.

// ignore_for_file: must_call_super

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide StoryProject;
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/services/story_pipeline/story_pipeline.dart';

class _RecordingLlm extends LLMService {
  final List<String> prompts = [];

  @override
  bool get isReady => true;

  @override
  String get backendName => 'recording';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    prompts.add(params.prompt);
    yield '[EVENT 1] They met on the porch.';
  }

  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  bool get hasListeners => false;
  @override
  void notifyListeners() {}
  @override
  void dispose() {}
}

const _chat = 's-porch';
const _otherChat = 's-other';
const _owner = 'Mira_1'; // stableGroupId: the image basename

Future<void> _seedChat(AppDatabase db, String sessionId, int count) async {
  await db.insertSession(
    SessionsCompanion.insert(id: sessionId, characterId: const Value('c1')),
  );
  for (var i = 0; i < count; i++) {
    await db.insertMessage(
      MessagesCompanion.insert(
        id: '$sessionId-m$i',
        sessionId: sessionId,
        position: i,
        sender: i.isEven ? 'Sam' : 'Mira',
        isUser: i.isEven,
        swipes: Value('["line $i of $sessionId"]'),
      ),
    );
  }
}

Future<void> _card(
  AppDatabase db,
  String id,
  String content, {
  String session = _chat,
  String? sources,
  bool pinned = false,
}) => db.insertJournalCard(
  JournalMemoriesCompanion.insert(
    id: id,
    sessionId: session,
    characterId: _owner,
    content: content,
    sourceMessageIds: Value(sources),
    pinned: Value(pinned),
  ),
);

Future<void> _ring(
  AppDatabase db,
  String id,
  String content, {
  String? sources,
  bool retired = false,
}) => db.insertGrowthRing(
  GrowthRingsCompanion.insert(
    id: id,
    sessionId: _chat,
    characterId: _owner,
    content: content,
    sourceMessageIds: Value(sources),
    retired: Value(retired),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_distill_').path;
        }
        return null;
      });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('journal cards and growth rings reach the distiller where they '
      'happened and close the timeline', () async {
    final db = AppDatabase.forTesting(sameIsolate: true);
    addTearDown(db.close);
    final repo = StoryRepository(db);
    final storage = StorageService();
    final llm = _RecordingLlm();
    final pipeline = StoryPipelineService(
      repo,
      llm,
      MemoryService(EmbeddingService(storage), storage, db),
      db,
    );

    await db.insertCharacter(
      CharactersCompanion.insert(
        id: 'c1',
        name: 'Mira',
        imagePath: Value(p.join('characters', '$_owner.png')),
      ),
    );
    await _seedChat(db, _chat, 60); // two distiller chunks: 0-49, 50-59
    await _seedChat(db, _otherChat, 4);

    await _card(db, 'j-late', 'I told Sam about the fire.', sources: '[55]');
    await _card(db, 'j-loose', 'Sam takes his coffee black.');
    // A receipt that round-tripped as a double, pinned by the user.
    await _card(
      db,
      'j-pinned',
      'Sam gave me the key.',
      sources: '[12.0]',
      pinned: true,
    );
    await _card(
      db,
      'j-leak',
      'A memory from a different chat.',
      session: _otherChat,
      sources: '[1]',
    );
    await _ring(
      db,
      'r-early',
      '{{char}} lets {{user}} see her afraid.',
      sources: '[10, 52]',
    );
    await _ring(
      db,
      'r-faded',
      'Mira flinches at raised voices.',
      sources: '[20]',
      retired: true,
    );

    final project = await repo.createProject(title: 'Porch');
    project
      ..useChatHistory = true
      ..chatHistoryCharacterIds = ['c1']
      ..chatHistorySessionIds = [_chat];

    await pipeline.runChatDistiller(project);

    final chunks = llm.prompts
        .where((s) => s.contains('CONVERSATION CHUNK'))
        .toList();
    expect(chunks, hasLength(2));

    // Each lands once, in the chunk holding its FIRST receipt.
    expect(chunks[0], isNot(contains('I told Sam about the fire.')));
    expect(chunks[1], contains("Mira's journal: I told Sam about the fire."));
    expect(chunks[0], contains('- Mira lets Sam see her afraid.'));
    expect(chunks[1], isNot(contains('lets Sam see her afraid')));
    expect(chunks[0], contains('Mira flinches at raised voices.'));

    expect(chunks[0], contains("Mira's journal: Sam gave me the key."));

    // A card with no receipt is not guessed into a chunk.
    expect(llm.prompts.join(), isNot(contains('coffee black')));

    final timeline = project.distilledTimeline;
    expect(timeline, startsWith('[EVENT 1]'));
    expect(timeline, contains("Mira's journal: Sam takes his coffee black."));
    // Pinned cards are restated so the merge pass cannot lose them; an
    // unpinned placed card rides on the events alone.
    final closing = timeline.substring(timeline.indexOf('PINNED IN'));
    expect(closing, contains("Mira's journal: Sam gave me the key."));
    expect(closing, isNot(contains('about the fire')));
    final end = timeline.indexOf('Mira, by the end:');
    final faded = timeline.indexOf('Mira, earlier growth that has since faded');
    expect(end, greaterThan(0));
    expect(faded, greaterThan(end), reason: 'retired rings are kept, after');
    expect(
      timeline.substring(end, faded),
      contains('Mira lets Sam see her afraid.'),
    );
    expect(
      timeline.substring(faded),
      contains('Mira flinches at raised voices.'),
    );

    // Journal and rings never cross chats.
    expect(llm.prompts.join() + timeline, isNot(contains('different chat')));
  });

  test('a chat with no journal or rings distills to events only', () async {
    final db = AppDatabase.forTesting(sameIsolate: true);
    addTearDown(db.close);
    final repo = StoryRepository(db);
    final storage = StorageService();
    final llm = _RecordingLlm();
    final pipeline = StoryPipelineService(
      repo,
      llm,
      MemoryService(EmbeddingService(storage), storage, db),
      db,
    );
    await db.insertCharacter(
      CharactersCompanion.insert(id: 'c1', name: 'Mira'),
    );
    await _seedChat(db, _chat, 4);
    final project = await repo.createProject(title: 'Porch');
    project
      ..useChatHistory = true
      ..chatHistoryCharacterIds = ['c1']
      ..chatHistorySessionIds = [_chat];

    await pipeline.runChatDistiller(project);

    expect(llm.prompts.single, isNot(contains('CONFIRMED BY')));
    expect(project.distilledTimeline, '[EVENT 1] They met on the porch.');
  });

  // Stories from group chats (docs/design/stories-from-group-chats.md §2):
  // a group chat's lines name their speaker from the message's speaker id
  // through the roster, never from the stored sender name, and the
  // distiller is told who the speakers are.
  test(
    'a group chat distills with speakers named by their member id',
    () async {
      final db = AppDatabase.forTesting(sameIsolate: true);
      addTearDown(db.close);
      final repo = StoryRepository(db);
      final storage = StorageService();
      final llm = _RecordingLlm();
      final pipeline = StoryPipelineService(
        repo,
        llm,
        MemoryService(EmbeddingService(storage), storage, db),
        db,
      );
      await db.insertGroup(GroupsCompanion.insert(id: 'g-crew', name: 'Crew'));
      for (final (id, name) in [
        ('m-mira', 'Mira'),
        ('m-dov', 'Dov'),
        ('m-ash', 'Ash'),
      ]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(id: id, groupId: 'g-crew', name: name),
        );
      }
      await db.insertSession(
        SessionsCompanion.insert(id: 's-crew', groupId: const Value('g-crew')),
      );
      // Dov was renamed after this line was sent: the stored sender is stale
      // and the speaker id is the truth. Ash never spoke; a guest who is on no
      // roster keeps the stored name. A director's note, a /narrate beat, a
      // time-skip bridge and the app's banners are stored the way the chat
      // writes them: none of them is a character or the user.
      const narration = '{"is_director_narration":true}';
      const bridge =
          '{"is_director_narration":true,"is_time_skip_bridge":true}';
      final lines = [
        ('Director', true, '__director__', null, 'Make Mira nervous.'),
        ('Sam', true, null, null, 'Who left the lamp out?'),
        ('Mira', false, 'm-mira', null, 'Not me.'),
        ('Narrator', true, '__director__', narration, 'Rain hits the glass.'),
        ('Dovid', false, 'm-dov', null, 'It was the wind.'),
        ('System', false, null, null, 'Ash is away and skips a turn.'),
        ('System', false, null, '{"is_status_banner":true}', 'Backend down.'),
        ('Narrator', true, '__director__', bridge, 'Two days pass.'),
        ('Wren', false, 'guest-1', null, 'I saw nothing.'),
      ];
      for (var i = 0; i < lines.length; i++) {
        final (sender, isUser, speaker, meta, text) = lines[i];
        await db.insertMessage(
          MessagesCompanion.insert(
            id: 's-crew-m$i',
            sessionId: 's-crew',
            position: i,
            sender: sender,
            isUser: isUser,
            characterId: Value(speaker),
            swipes: Value('["$text"]'),
            metadata: Value(meta),
          ),
        );
      }
      final project = await repo.createProject(title: 'Crew');
      project
        ..useChatHistory = true
        ..chatGroupId = 'g-crew'
        ..chatHistoryCharacterIds = ['m-mira', 'm-dov', 'm-ash']
        ..chatHistorySessionIds = ['s-crew'];

      await pipeline.runChatDistiller(project);

      final prompt = llm.prompts.single;
      expect(prompt, contains('Sam: Who left the lamp out?'));
      expect(prompt, contains('Mira: Not me.'));
      expect(prompt, contains('Dov: It was the wind.'));
      expect(prompt, isNot(contains('Dovid')));
      expect(prompt, contains('Wren: I saw nothing.'));
      expect(prompt, contains('group scene'));
      expect(prompt, contains('the characters are Mira, Dov, Ash & Wren'));
      expect(prompt, contains('the user plays Sam'));
      expect(prompt, contains('Name the speaker in every event'));
      expect(prompt, isNot(contains('between a user and an AI character')));
      expect(prompt, contains('Narration: Rain hits the glass.'));
      expect(prompt, contains('Narration: Two days pass.'));
      expect(prompt, isNot(contains('Make Mira nervous')));
      expect(prompt, isNot(contains('skips a turn')));
      expect(prompt, isNot(contains('Backend down')));
      expect(prompt, isNot(contains('plays Director')));

      // The canon block every stage reads carries the same cast sentence.
      final history = StoryChatHistory(
        StoryPipelineContext(
          repository: repo,
          llmService: llm,
          db: db,
          store: StoryStudioStore(),
          lanes: null,
          loreIndex: StoryLoreIndex(null),
          notify: () {},
        ),
      );
      final canon = await history.context(project);
      expect(canon, contains('CANON EVENT TIMELINE'));
      expect(canon, contains('the characters are Mira, Dov, Ash & Wren'));
      expect(canon, contains('do not fold two of them into one'));
    },
  );
}
