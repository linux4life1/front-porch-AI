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
}
