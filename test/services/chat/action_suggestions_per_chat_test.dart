// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// #329: "Suggest actions" pills belong to the message they were generated
// on. Opening another chat must not show them (or the "Thinking…" state)
// on that chat's latest bubble. Real ChatService + in-memory drift DB; the
// scripted model is the only fake and nothing asserts on its wording.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import '../../helpers/chat_db_teardown.dart';

class _SuggestLlm extends LLMService {
  /// When set, the suggestion reply waits on it (in-flight chat switch).
  Completer<void>? gate;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains('Suggest 4 short actions')) {
      if (gate != null) await gate!.future;
      yield '1. Kiss them and pull them closer\n'
          '2. Ask about their day\n'
          '3. Tease them by pulling away\n'
          '4. Suggest a walk';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedSuggest';
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_suggest_').path;
        }
        return null;
      });
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
  late ChatService chat;
  late _SuggestLlm llm;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
    final storage = StorageService();
    final personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    llm = _SuggestLlm();
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db)
      ..testLlmServiceOverride = llm;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<CharacterCard> seedChat(String id, String name) async {
    await db.insertCharacter(
      CharactersCompanion.insert(
        id: id,
        name: name,
        imagePath: Value('/tmp/${name}_1.png'),
      ),
    );
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'sess-$id',
        characterId: Value(id),
        name: Value('$name chat'),
      ),
    );
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm-$id',
        sessionId: 'sess-$id',
        position: 0,
        sender: name,
        isUser: false,
        swipes: const Value('["Evening."]'),
      ),
    );
    return CharacterCard(name: name, imagePath: '/tmp/${name}_1.png')
      ..dbId = id;
  }

  Future<void> open(CharacterCard card) async {
    await chat.setActiveCharacter(card);
    await chat.loadSession('sess-${card.dbId}');
    expect(chat.currentSessionId, 'sess-${card.dbId}');
  }

  test('suggestions generated in one chat do not show in another', () async {
    final misty = await seedChat('char-a', 'Misty');
    final nina = await seedChat('char-b', 'Nina');

    await open(misty);
    await chat.generateActions();
    expect(chat.suggestedActions, hasLength(4));
    expect(chat.isGeneratingActions, isFalse);

    await open(nina);
    expect(chat.messages, isNotEmpty);
    expect(
      chat.suggestedActions,
      isEmpty,
      reason: "Misty's pills must not sit under Nina's last message",
    );
    expect(chat.isGeneratingActions, isFalse);
  });

  test('a run still thinking when the chat changes lands nowhere', () async {
    final misty = await seedChat('char-a', 'Misty');
    final nina = await seedChat('char-b', 'Nina');

    await open(misty);
    llm.gate = Completer<void>();
    final inFlight = chat.generateActions();
    await _drain();
    expect(chat.isGeneratingActions, isTrue);

    await open(nina);
    expect(
      chat.isGeneratingActions,
      isFalse,
      reason: "Nina's bubble must not show Misty's Thinking… spinner",
    );

    // Nina's chat is settled; the stale run landing must not touch it.
    await _drain();
    var pokes = 0;
    chat.addListener(() => pokes++);
    llm.gate!.complete();
    await inFlight;
    await _drain();
    expect(chat.suggestedActions, isEmpty);
    expect(chat.isGeneratingActions, isFalse);
    expect(
      pokes,
      0,
      reason: "Misty's late result must not rebuild Nina's chat",
    );

    // The new chat can still ask for its own; the stale run did not wedge it.
    llm.gate = null;
    await chat.generateActions();
    expect(chat.suggestedActions, hasLength(4));
  });
}
