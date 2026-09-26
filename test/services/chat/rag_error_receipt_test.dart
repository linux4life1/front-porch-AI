// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A failed RAG search (query embed / thrown) used to stamp a normal empty
// receipt — the sidebar said "nothing relevant" after a lookup that never
// ran (audit P1.9). The receipt must say error.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show kRagReceiptError, kRagReceiptOk;
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_ragerr_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  static const _reply =
      '*She rocks slowly, the porch boards creaking under the runners, and '
      'talks about the garden, the neighbours, the way the light moves '
      'through the screen door in the late afternoon, unhurried. She lists '
      'the tomatoes that came in early, the fence post that needs setting, '
      'the dog two doors down that has learned to open the gate latch.*';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield _reply;
      return;
    }
    final p = params.prompt;
    if (p.contains('current physical position and stance')) {
      yield '{"posture": "none"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"happy","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('fixation_topic')) {
      yield '{"fixation_topic":"the garden","proposed_objective":"none"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

class _ErrorMemory extends MemoryService {
  _ErrorMemory(super.embedding, super.storage, super.db);

  int retrieveCalls = 0;

  @override
  bool get isOperational => true;

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
  }) async {
    retrieveCalls++;
    lastRetrieveError = 'query embed failed';
    return const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ErrorMemory memory;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'rag_enabled': true,
      'context_size': 3072,
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
          ..testLlmServiceOverride = _ScriptedLlm();
    await storage.initialized;
    memory = _ErrorMemory(EmbeddingService(storage), storage, db);
    chat.setMemoryService(memory);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'a failed search stamps an error receipt, not nothing relevant',
    () async {
      final card = CharacterCard(
        name: 'Nia',
        description: 'Exists only inside the RAG error-receipt test.',
        firstMessage: 'The porch light hums in the dusk.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-ragerr-1';
      await chat.setActiveCharacter(card);

      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-ragerr',
          characterId: const Value('char-ragerr-1'),
        ),
      );
      for (var i = 0; i < 24; i++) {
        final isUser = i.isOdd;
        await db.insertMessage(
          MessagesCompanion.insert(
            id: 'seed-$i',
            sessionId: 'sess-ragerr',
            position: i,
            sender: isUser ? 'You' : 'Nia',
            isUser: isUser,
            swipes: Value('["${_ScriptedLlm._reply.replaceAll('*', '')}"]'),
          ),
        );
      }
      await chat.loadSession('sess-ragerr');
      expect(chat.messages, hasLength(24));

      await chat.sendMessage('Remember what you said about the tomatoes?');

      expect(
        memory.retrieveCalls,
        greaterThan(0),
        reason: 'the retrieval gate never opened — nothing here was tested',
      );
      final receipt = chat.lastRagReceipt;
      expect(receipt, isNotNull);
      expect(
        receipt!['status'],
        kRagReceiptError,
        reason:
            'a failed lookup must not look like an empty search '
            '(status=$kRagReceiptOk would be "nothing relevant")',
      );
      final reply = chat.messages.lastWhere((m) => !m.isUser);
      expect(reply.activeMetadata?['rag_receipt'], isNotNull);
      expect(
        (reply.activeMetadata!['rag_receipt'] as Map)['status'],
        kRagReceiptError,
      );
    },
  );
}
