// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Growth injection cache is rebuilt for the whole cast. A Scene Guest is
// a cast member with rings of its own: when a timeline rewrite (here a tail
// delete) purges a host ring, the rebuilt cache must still hold the guest's
// rings — a valid cache without them reads exactly like "never grew".
//
// Real ChatService, real Drift session, a real guest seated with
// joinSceneGuest. The assertions read the same cache the prompt reads.
//
// Proven red:
//  * rebuild the cache in _invalidateGrowthFrom from a local id list of the
//    active character only (the old copy) → the guest's ring count drops to 0;
//  * drop the rebuild there entirely → the purge leaves the cache empty and
//    the guest reads as never grown.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import '../../helpers/chat_db_teardown.dart';

class _PorchLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*She sets the lemonade down on the porch rail.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'PorchLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_growguest_').path;
        }
        return null;
      });

  late AppDatabase db;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    final storage = StorageService();
    final repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _PorchLlm();
    await storage.initialized;
    final host = CharacterCard(
      name: 'Flora',
      firstMessage: 'Evening.',
      imagePath: 'grow-flora.png',
      frontPorchExtensions: FrontPorchExtensions(realismEnabled: false),
    );
    final guest = CharacterCard(
      name: 'Riley',
      firstMessage: 'Hi.',
      imagePath: 'grow-riley.png',
    );
    await repo.addCharacter(host);
    await repo.addCharacter(guest);
    await chat.setActiveCharacter(host);
    await chat.joinSceneGuest(guest);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> settle() async {
    for (
      var i = 0;
      i < 600 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('a ring purge keeps the Scene Guest\'s rings in the cache', () async {
    final host = chat.activeCharacter!;
    final guest = chat.sceneGuestCards.singleWhere((c) => c.name == 'Riley');

    await chat.sendMessage('Lemonade on the porch?');
    await settle();
    final replyIndex = chat.messages.length - 1;
    expect(chat.messages[replyIndex].isUser, isFalse);
    await chat.flushPendingSaves();

    // The host grew from that reply (cites it); the guest's ring is planted
    // by hand, cites nothing, and must survive any rewrite.
    await GrowthStore(getDb: () => db).addRing(
      sessionId: chat.currentSessionId!,
      characterId: chat.characterIdFor(host),
      content: 'Flora has started making lemonade for guests.',
      category: 'habit',
      sourcePositions: [replyIndex],
    );
    await chat.plantGrowthRingFor(
      chat.characterIdFor(guest),
      'Riley has learned the old porch songs.',
    );
    expect(chat.growthRingCountFor(host), 1, reason: 'precondition');
    expect(chat.growthRingCountFor(guest), 1, reason: 'precondition');

    chat.deleteMessage(replyIndex);
    // The purge and rebuild run after the delete returns; wait for the cache
    // to settle on the outcome (or time out and let the expects name it).
    bool settled() =>
        chat.growthRingCountFor(host) == 0 &&
        chat.growthRingCountFor(guest) == 1;
    for (var i = 0; i < 400 && !settled(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(
      chat.growthRingCountFor(host),
      0,
      reason: 'the ring citing the deleted reply is purged and re-cached',
    );
    expect(
      chat.growthRingCountFor(guest),
      1,
      reason: 'the rebuilt cache must still count the Scene Guest',
    );
  });
}
