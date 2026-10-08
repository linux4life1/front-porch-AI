// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The "Start from a chat" list against a real in-memory DB: which chats are
// offered, in what order, and how search narrows them.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide StoryProject;
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';

Future<void> _chat(
  AppDatabase db,
  String id,
  String characterId, {
  required int messages,
  required DateTime at,
  String? name,
  String? groupId,
  bool userSpeaks = true,
}) async {
  await db.insertSession(
    SessionsCompanion.insert(
      id: id,
      characterId: Value(characterId),
      groupId: Value(groupId),
      name: Value(name),
      createdAt: Value(at),
    ),
  );
  for (var i = 0; i < messages; i++) {
    await db.insertMessage(
      MessagesCompanion.insert(
        id: '$id-m$i',
        sessionId: id,
        position: i,
        sender: 'x',
        isUser: userSpeaks && i.isOdd,
        swipes: const Value('["hi"]'),
      ),
    );
  }
}

class _NoLlm extends LLMService {
  @override
  bool get isReady => false;

  @override
  String get backendName => 'none';

  @override
  Stream<String> generateStream(GenerationParams params) =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_sources_').path;
        }
        return null;
      });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('lists chats the user wrote in, newest first, with counts', () async {
    final db = AppDatabase.forTesting(sameIsolate: true);
    addTearDown(db.close);
    final storage = StorageService();
    final pipeline = StoryPipelineService(
      StoryRepository(db),
      _NoLlm(),
      MemoryService(EmbeddingService(storage), storage, db),
      db,
    );
    await db.insertCharacter(
      CharactersCompanion.insert(id: 'c1', name: 'Mira'),
    );
    await db.insertCharacter(CharactersCompanion.insert(id: 'c2', name: 'Dov'));

    await _chat(db, 'old', 'c1', messages: 40, at: DateTime(2026, 1, 1));
    await _chat(db, 'new', 'c2', messages: 6, at: DateTime(2026, 9, 1));
    // A greeting nobody answered, an empty chat, a group chat, and a chat
    // whose character is gone are not story material.
    await _chat(
      db,
      'greeting',
      'c1',
      messages: 1,
      at: DateTime(2026, 9, 2),
      userSpeaks: false,
    );
    await _chat(db, 'empty', 'c1', messages: 0, at: DateTime(2026, 9, 3));
    await _chat(
      db,
      'group',
      'c1',
      messages: 9,
      at: DateTime(2026, 9, 4),
      groupId: 'g1',
    );
    await _chat(db, 'orphan', 'gone', messages: 9, at: DateTime(2026, 9, 5));

    final rows = await pipeline.chatSources();

    expect(rows.map((r) => r.sessionId), ['new', 'old']);
    expect(rows.first.characterName, 'Dov');
    expect(rows.first.messageCount, 6);
    expect(rows.first.isShort, isTrue);
    expect(rows.last.isShort, isFalse);
  });

  test('a small chat starts on the shortest length and is warned about '
      'longer ones', () {
    expect(suggestedLengthForChat(13), 'Short');
    expect(suggestedLengthForChat(149), 'Short');
    expect(suggestedLengthForChat(150), 'Standard');

    expect(chatLengthWarning(13, 'Standard'), contains('13 messages'));
    expect(chatLengthWarning(13, 'Standard'), contains('mostly invented'));
    // Even the shortest length is a novella: a tiny chat is told so.
    expect(chatLengthWarning(13, 'Short'), contains('30,000-word'));
    expect(chatLengthWarning(1, 'Short'), contains('1 message.'));
    expect(chatLengthWarning(60, 'Short'), isNull);
    expect(chatLengthWarning(200, 'Standard'), isNull);
    expect(chatLengthWarning(200, 'Epic'), isNotNull);
    // Size unknown (a story reopened from the shelf): say nothing.
    expect(chatLengthWarning(0, 'Epic'), isNull);
  });

  test('search needs every word, across character and chat name', () {
    StoryChatSourceRow row(String character, String chat) => StoryChatSourceRow(
      characterId: character,
      characterName: character,
      sessionId: '$character-$chat',
      sessionName: chat,
      summary: '',
      createdAt: DateTime(2026),
      messageCount: 40,
    );
    final rows = [
      row('Mira Vale', 'The lighthouse'),
      row('Dov Marsh', 'Letters'),
      row('Mira Vale', 'Second winter'),
    ];
    expect(filterChatSources(rows, '  '), hasLength(3));
    expect(filterChatSources(rows, 'mira'), hasLength(2));
    expect(
      filterChatSources(rows, 'vale WINTER').single.sessionName,
      'Second winter',
    );
    expect(filterChatSources(rows, 'dov winter'), isEmpty);
  });
}
