// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regenerating a Scene Guest's bubble after that guest has left the scene
// is refused and the bubble goes back on screen. The refusal must come
// BEFORE journal invalidation, or the diary lines citing that bubble die
// while it is still showing, with nothing to replant them.
//
// Proven red: calling _invalidateJournalFrom ahead of the departed-guest
// check in _regenerateLastMessageHeld drops the card below.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';
import '../../helpers/refractory_judges.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? Directory.systemTemp.createTempSync('fpai_guest_left_').path
            : null,
      );

  late AppDatabase db;
  late ChatService chat;
  DebugPrintCallback? previousPrint;

  Future<void> settle() async {
    for (
      var i = 0;
      i < 500 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'needs_sim_default': false,
      'pockets_enabled': false,
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
          ..testLlmServiceOverride = RefractoryJudges();
    await storage.initialized;
    final host = CharacterCard(
      name: 'Flora',
      firstMessage: 'Evening.',
      imagePath: 'gl-flora.png',
    );
    final guest = CharacterCard(
      name: 'Riley',
      firstMessage: 'Hi.',
      imagePath: 'gl-riley.png',
      frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
    );
    await repo.addCharacter(host);
    await repo.addCharacter(guest);
    await chat.setActiveCharacter(host);
    await chat.joinSceneGuest(guest);
    await settle();
  });

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    await disposeChatThenCloseDb(chat, db);
  });

  test(
    'regen of a departed guest\'s bubble keeps the cards citing it',
    () async {
      await chat.sendMessage('Riley, tell her about the fair.');
      await settle();
      await chat.speakGuestNow(
        chat.sceneGuestCards.firstWhere((c) => c.name == 'Riley'),
      );
      await settle();
      final rileyIndex = chat.messages.length - 1;
      expect(chat.messages[rileyIndex].sender, 'Riley');

      // Riley leaves (Flora narrates it); the user deletes the narration, so
      // the departed guest's bubble is the tip again.
      await chat.sendMessage('/exit Riley');
      await settle();
      expect(chat.sceneGuestCards.where((c) => c.name == 'Riley'), isEmpty);
      while (chat.messages.length - 1 > rileyIndex) {
        chat.deleteMessage(chat.messages.length - 1);
        await settle();
      }
      final riley = chat.messages.last;
      expect(riley.sender, 'Riley');

      final sid = chat.currentSessionId!;
      await db
          .into(db.journalMemories)
          .insert(
            JournalMemoriesCompanion.insert(
              id: 'jrnl-riley',
              sessionId: sid,
              characterId: 'Flora',
              content: 'Riley told me about the county fair.',
              sourceMessageIds: Value(jsonEncode([rileyIndex])),
            ),
          );

      await chat.regenerateLastMessage();
      await settle();

      expect(chat.messages.length, rileyIndex + 1);
      expect(chat.messages.last.sender, 'Riley');
      expect(chat.messages.last.text, riley.text);
      expect((await db.getJournalCardsForSession(sid)).map((c) => c.content), [
        'Riley told me about the county fair.',
      ], reason: 'the refused bubble is still on screen; its cites must stay');
    },
  );
}
