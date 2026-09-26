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

// AN .fpchat RESTORED ONTO A DIFFERENT CARD MUST RE-KEY ITS OWNER-STAMPED
// ROWS. Journal cards, growth rings and objectives are all stored under the
// owner's stableGroupId, and every reader asks for the LIVE card's id. The
// importer used to write the EXPORTING card's id verbatim, so AI Enhance's
// "bring your chats along" (which duplicates the card — a new portrait
// basename, therefore a new stableGroupId — and answers the mismatch prompt
// "continue" by design) delivered copies with an empty diary, zero rings and
// no quests while the rows sat unreachable in the very same session.
//
// Red-proved: with the remap removed, every "under the enhanced card"
// expectation below goes to zero and the "not left under the base id"
// expectations find the orphans.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_remap_').path;
        }
        return null;
      });
}

class _InertLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'InertLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _InertLlm();
    await storage.initialized;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<CharacterCard> seedCard(String name) async {
    final card = CharacterCard(
      name: name,
      description: 'Exists only inside the fpchat owner-remap test.',
      firstMessage: 'The screen door bangs.',
    );
    final tmpDir = Directory.systemTemp.createTempSync('remap_card_');
    final pngPath = '${tmpDir.path}/$name.png';
    await V2CardService().saveCardAsPng(card, pngPath, null);
    card.imagePath = pngPath;
    await repo.addCharacter(card);
    return card;
  }

  test(
    'copying chats onto an enhanced duplicate re-keys journal cards, growth '
    'rings and objectives to the NEW card so they are actually readable',
    () async {
      final base = await seedCard('Odile');
      const sid = '1700000000101';
      await db.insertSession(
        SessionsCompanion.insert(id: sid, characterId: Value(base.dbId)),
      );
      for (final (i, line) in ['Hello there.', 'CHAT-MARKER'].indexed) {
        await db.insertMessage(
          MessagesCompanion.insert(
            id: '$sid-m$i',
            sessionId: sid,
            position: i,
            sender: i.isEven ? 'You' : base.name,
            isUser: i.isEven,
            swipes: Value('["$line"]'),
          ),
        );
      }

      // Owner-stamped state, all keyed by the BASE card's stableGroupId.
      await chat.journalStore.addCard(
        sessionId: sid,
        characterId: base.stableGroupId,
        content: 'She left her keys on the hallway table.',
        category: 'moment',
        maxCards: 40,
      );
      await db.insertGrowthRing(
        GrowthRingsCompanion(
          sessionId: Value(sid),
          characterId: Value(base.stableGroupId),
          content: Value('Trusts {{user}} with the porch light.'),
        ),
      );
      await db.insertObjective(
        ObjectivesCompanion(
          characterId: Value(base.stableGroupId),
          chatId: Value(sid),
          objective: Value('Fix the porch swing.'),
        ),
      );

      final enhanced = await repo.duplicateCharacter(
        base,
        newNameOverride: 'Odile (Enhanced)',
      );
      expect(enhanced, isNotNull);
      expect(
        enhanced!.stableGroupId,
        isNot(base.stableGroupId),
        reason:
            'the duplicate gets a fresh portrait basename — that new id is '
            'exactly what makes the remap necessary',
      );

      expect(await chat.copyChatsForEnhance(from: base, to: enhanced), 1);

      final newSid = chat.currentSessionId;
      expect(newSid, isNotNull);
      expect(newSid, isNot(sid));

      // Journal: readable under the enhanced card, nothing orphaned.
      final movedCards = await chat.journalStore.cardsFor(
        newSid!,
        enhanced.stableGroupId,
      );
      expect(movedCards, hasLength(1));
      expect(movedCards.first.content, contains('hallway table'));
      expect(
        await chat.journalStore.cardsFor(newSid, base.stableGroupId),
        isEmpty,
        reason: 'a card left under the exporting id is unreachable forever',
      );

      // Growth rings.
      final rings = await db.getGrowthRingsForSession(newSid);
      expect(rings, hasLength(1));
      expect(rings.first.characterId, enhanced.stableGroupId);

      // Objectives.
      expect(
        await db.getObjectivesForCharacter(
          enhanced.stableGroupId,
          chatId: newSid,
        ),
        hasLength(1),
      );
      expect(
        await db.getObjectivesForCharacter(base.stableGroupId, chatId: newSid),
        isEmpty,
      );

      // The base character's own rows are untouched in her own session.
      expect(
        await chat.journalStore.cardsFor(sid, base.stableGroupId),
        hasLength(1),
      );
    },
  );

  test(
    'restoring a package onto its OWN card leaves every owner id alone',
    () async {
      final card = await seedCard('Perpetua');
      const sid = '1700000000202';
      await db.insertSession(
        SessionsCompanion.insert(id: sid, characterId: Value(card.dbId)),
      );
      await db.insertMessage(
        MessagesCompanion.insert(
          id: '$sid-m0',
          sessionId: sid,
          position: 0,
          sender: 'You',
          isUser: true,
          swipes: const Value('["Evening."]'),
        ),
      );
      await chat.setActiveCharacter(card);
      await chat.loadSession(sid);
      await chat.journalStore.addCard(
        sessionId: sid,
        characterId: card.stableGroupId,
        content: 'The porch swing still squeaks.',
        category: 'moment',
        maxCards: 40,
      );

      final bytes = await chat.exportToFpchat();
      expect(bytes, isNotNull);
      final result = await chat.importChatPackage(
        bytes!,
        onCharacterMismatch: (_, _) async => true,
      );
      expect(result.fullRestore, isTrue);

      final newSid = chat.currentSessionId!;
      expect(
        await chat.journalStore.cardsFor(newSid, card.stableGroupId),
        hasLength(1),
        reason: 'same card in, same card out — the remap must be a no-op here',
      );
    },
  );
}
