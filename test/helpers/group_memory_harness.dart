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

// A real group chat (Ada, backed by library id Ada_lib, and Bea, with none)
// over the in-process backend and a real MemoryService with constant fake
// vectors: every stored window scores the same, so what a test sees is which
// WINDOWS the code files and reads, never how a model ranks text.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../integration_test/support/fake_backend.dart';
import 'chat_db_teardown.dart';

class FakeVectors extends EmbeddingService {
  FakeVectors(super.storage);

  @override
  bool get isAvailable => true;

  @override
  Future<void> checkAvailability() async {}

  @override
  Future<List<double>?> embed(String text) async => List<double>.filled(4, 0.1);
}

/// The four constant floats [FakeVectors] embeds every text to, as stored.
class FakeVectorsBytes {
  static final bytes = Uint8List.view(
    Float32List.fromList(const [0.1, 0.1, 0.1, 0.1]).buffer,
  );
}

/// A MemoryService that records what each retrieval was asked, then answers
/// for real from the database.
class RecordingMemory extends MemoryService {
  RecordingMemory(super.embedding, super.storage, super.db);

  final List<
    ({
      List<String> sources,
      Set<String> scoped,
      Map<String, double>? priorities,
    })
  >
  asked = [];

  @override
  Future<List<RetrievedMemory>> retrieve({
    required String queryText,
    required List<String> sourceCharacterIds,
    required String currentSessionId,
    int inContextStart = 0,
    int limit = 5,
    double minScore = MemoryService.kRagMinScore,
    Map<String, double>? characterPriorities,
    Set<String> sessionScopedCharacterIds = const {},
  }) {
    asked.add((
      sources: List.of(sourceCharacterIds),
      scoped: Set.of(sessionScopedCharacterIds),
      priorities: characterPriorities,
    ));
    return super.retrieve(
      queryText: queryText,
      sourceCharacterIds: sourceCharacterIds,
      currentSessionId: currentSessionId,
      inContextStart: inContextStart,
      limit: limit,
      minScore: minScore,
      characterPriorities: characterPriorities,
      sessionScopedCharacterIds: sessionScopedCharacterIds,
    );
  }
}

void mockPathProvider(String tag) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_$tag').path;
        }
        return null;
      });
}

class GroupMemoryHarness {
  GroupMemoryHarness._();

  static const groupId = 'grp-mem';
  static const adaKey = 'Ada_lib';

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late FakeBackendServer backend;
  late RecordingMemory memory;

  static Future<GroupMemoryHarness> open({int windowSize = 3}) async {
    final h = GroupMemoryHarness._();
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': false,
      'rag_enabled': true,
      'rag_window_size': windowSize,
      'context_size': 3072,
    });
    h.backend = await FakeBackendServer.start(
      replyPieces: const ['She leans on the porch rail.'],
    );
    h.db = AppDatabase.forTesting();
    h.storage = StorageService();
    h.chat =
        ChatService(
            KoboldService(h.storage),
            UserPersonaService(h.db),
            h.storage,
            WorldRepository(h.storage, h.db),
          )
          ..setDatabase(h.db)
          ..setCharacterRepository(CharacterRepository(h.db, h.storage))
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${h.backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await h.storage.initialized;
    h.memory = RecordingMemory(FakeVectors(h.storage), h.storage, h.db);
    h.chat.setMemoryService(h.memory);
    await h.db.insertGroup(GroupsCompanion.insert(id: groupId, name: 'Cast'));
    for (final (id, name, memberState) in [
      ('mem-ada', 'Ada', '{"originStableId":"$adaKey"}'),
      ('mem-bea', 'Bea', '{}'),
    ]) {
      await h.db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: groupId,
          name: name,
          personality: Value('$name keeps the porch.'),
          avatarFilename: Value('${name.toLowerCase()}.png'),
          frontPorchExtensions: const Value(
            '{"realism_engine":{"realism_enabled":true}}',
          ),
          memberState: Value(memberState),
        ),
      );
    }
    return h;
  }

  /// Opens the group fresh (a new chat).
  Future<void> openGroup() => chat.setActiveGroup(
    GroupChat(id: groupId, name: 'Cast'),
    groupRepo: GroupChatRepository(storage, db),
  );

  CharacterCard member(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);
  String idOf(String name) => groupMemberStoreId(member(name));

  /// Waits for the fire-and-forget embeds a reply starts.
  Future<void> settle() async {
    var quiet = 0;
    for (var i = 0; i < 400 && quiet < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      quiet = (memory.isEmbedding || chat.isGenerating) ? 0 : quiet + 1;
    }
  }

  Future<void> say(String as, String text) async {
    chat.setNextCharacter(member(as));
    await chat.sendMessage(text);
    await settle();
  }

  Future<List<MessageEmbedding>> rows(String characterId) async =>
      (await db.getEmbeddingsForCharacters([characterId]))
        ..sort((a, b) => a.positionStart.compareTo(b.positionStart));

  static const sessionId = 'sess-mem';

  /// A 70-line group transcript, long enough to overflow the 3072-token
  /// context so a turn on it goes looking for memories. Seeded, not played.
  Future<void> seedLongChat() async {
    await db.insertSession(
      SessionsCompanion.insert(id: sessionId, groupId: const Value(groupId)),
    );
    const filler =
        'The porch boards creak while the evening settles over the street '
        'and the neighbours talk about the garden, the fence, the dog, the '
        'light through the screen door, and the long unhurried afternoon.';
    for (var i = 0; i < 70; i++) {
      final user = i.isOdd;
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'seed-$i',
          sessionId: sessionId,
          position: i,
          sender: user ? 'You' : (i % 4 == 0 ? 'Ada' : 'Bea'),
          isUser: user,
          swipes: Value('["$filler $i"]'),
        ),
      );
    }
  }

  /// Stores one three-line window by hand. [matches] false gives it a vector
  /// a search scores low against the fake query.
  Future<void> window(String key, String text, int at, {bool matches = true}) =>
      db.insertEmbedding(
        MessageEmbeddingsCompanion(
          sessionId: const Value(sessionId),
          characterId: Value(key),
          positionStart: Value(at),
          positionEnd: Value(at + 2),
          content: Value(text),
          embedding: Value(
            matches
                ? FakeVectorsBytes.bytes
                : Uint8List.view(
                    Float32List.fromList(const [1, -1, 1, -1]).buffer,
                  ),
          ),
          dimensions: const Value(4),
        ),
      );

  Future<void> close() async {
    memory.dispose();
    await disposeChatThenCloseDb(chat, db);
    await backend.close();
  }
}
