// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Adding an item queues a just-noticed / just-handed one-shot for the next
// reply. Erasing that item before they speak used to leave the intro queued,
// so they still reacted to keys that were already gone.
//
// Proven red: skip the queue.removeWhere in removePocketItem and the
// surprise/gift assertions fail (the prompt still carries the intro).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show PocketSection;
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_peraser_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  final List<String> chatPrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      chatPrompts.add(params.prompt);
      yield '*She looks around the porch.*';
      return;
    }
    yield '{"inventory_ops": []}';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': true,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 300 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  CharacterCard card() => CharacterCard(
    name: 'Mara',
    description: 'Exists only inside the pocket-eraser intro test.',
    firstMessage: 'The porch light hums.',
  )..dbId = 'char-peraser';

  test('erasing a just-added item drops the surprise intro', () async {
    await chat.setActiveCharacter(card());
    final id = chat.characterIdFor(chat.activeCharacter!);

    await chat.addPocketItem(
      id,
      section: PocketSection.carrying,
      name: 'brass key (scuffed)',
    );
    expect(chat.pocketsFor(id)!.carrying, isNotEmpty);

    await chat.removePocketItem(id, section: PocketSection.carrying, index: 0);
    expect(chat.pocketsFor(id)!.carrying, isEmpty);

    await chat.sendMessage('Anything new?');
    await drainTurn();
    expect(llm.chatPrompts, isNotEmpty);
    expect(
      llm.chatPrompts.last,
      isNot(contains('NO memory of how it got there')),
      reason: 'THE BUG: eraser left the just-noticed intro queued',
    );
    expect(llm.chatPrompts.last, isNot(contains('brass key')));
  });

  test('erasing a just-handed gift drops the handed intro', () async {
    await chat.setActiveCharacter(card()..dbId = 'char-peraser-gift');
    final id = chat.characterIdFor(chat.activeCharacter!);

    await chat.addPocketItem(
      id,
      section: PocketSection.carrying,
      name: 'pocket watch',
      gift: true,
    );
    await chat.removePocketItem(id, section: PocketSection.carrying, index: 0);

    await chat.sendMessage('Never mind.');
    await drainTurn();
    expect(
      llm.chatPrompts.last,
      isNot(contains('has just handed Mara')),
      reason: 'THE BUG: eraser left the just-handed intro queued',
    );
  });

  test('removePocketItem drops pending intros for the erased name', () {
    final src = File(
      'lib/services/chat/chat_service_pockets.dart',
    ).readAsStringSync();
    final start = src.indexOf('Future<void> removePocketItem');
    expect(start, greaterThanOrEqualTo(0));
    final body = src.substring(start, start + 1800);
    expect(body, contains('_pendingItemIntros[characterId]'));
    expect(body, contains('queue.removeWhere'));
  });
}
