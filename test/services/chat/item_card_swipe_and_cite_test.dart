// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Item-memory receipts must cite the persist (full-transcript) index, and
// swiping a pockets tip must not leave the diary missing the live
// placement card (full-codebase audit P0).
//
// Proven red:
//   * persistTipCite unit: base 9976 + index 23 is 9999, not 23.
//   * call-site pin: writers that still use `_messages.length - 1` fail.
//   * swipe-back: disable thenReplantPlanted and the diary stays empty.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show JournalPhysics, persistTipCite;

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_itemswipe_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  String inventoryJson = '{"inventory_ops": []}';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*She hums on the porch, unhurried.*';
      return;
    }
    if (params.prompt.contains('You are keeping track of what')) {
      yield inventoryJson;
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('persistTipCite uses the full-transcript index, not 0..23', () {
    expect(persistTipCite(base: 9976, length: 24), [
      9999,
    ], reason: 'last of a 24-row tail on a 10000-line chat is 9999');
    expect(persistTipCite(base: 0, length: 5), [4]);
    expect(persistTipCite(base: 10, length: 0), isEmpty);
  });

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
      'journal_enabled': true,
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

  Future<List<String>> itemContents() async {
    final sid = chat.currentSessionId;
    if (sid == null) return const [];
    return [
      for (final c in await db.getJournalCardsForSession(sid))
        if (JournalPhysics.isItemCard(c)) c.content,
    ];
  }

  Future<void> drainUntil(bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('swipe-back of a setdown replants the live item card', () async {
    final card = CharacterCard(
      name: 'Mara',
      description: 'Exists only inside the item-swipe test.',
      firstMessage: 'The porch light hums.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
        inventory: {
          'carrying': ['car keys'],
        },
      ),
    )..dbId = 'char-itemswipe-1';
    await chat.setActiveCharacter(card);

    llm.inventoryJson =
        '{"inventory_ops": [{"op": "setdown", "item": "keys", '
        '"where": "on the hallway table"}]}';
    await chat.sendMessage('Make yourself at home.');
    for (var i = 0; i < 400; i++) {
      if ((await itemContents()).isNotEmpty) break;
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      await itemContents(),
      isNotEmpty,
      reason: 'setdown must plant an item card',
    );

    llm.inventoryJson = '{"inventory_ops": []}';
    await chat.regenerateLastMessage();
    await drainUntil(() => !chat.isGenerating && !chat.isSettlingTurn);

    final last = chat.messages.length - 1;
    await chat.swipeMessage(last, -1);
    for (var i = 0; i < 400; i++) {
      if ((await itemContents()).any((t) => t.contains('hallway table'))) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      await itemContents(),
      anyElement(contains('hallway table')),
      reason: 'swipe-back to the setdown must restore the diary with the kit',
    );
  });
}
