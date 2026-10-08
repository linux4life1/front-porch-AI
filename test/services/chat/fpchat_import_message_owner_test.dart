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

// A CHAT RESTORED ONTO A DIFFERENT CARD MUST HAND THE HOST'S MESSAGES TO THAT
// CARD. Every 1:1 reply is stamped with its speaker's stableGroupId, and that
// stamp is how the app tells the host from a scene guest: a reply whose id is
// not the open card's belongs to a guest. AI Enhance copies chats onto a
// duplicate with a new portrait basename (so a new stableGroupId), and Import
// Chat can restore a package onto any card. The importer re-keyed the diary,
// rings and quests to the new card but kept every message's id, so each
// copied reply read as a guest who had left: Regenerate and Continue on the
// last one refused with "they have left the scene". The turn's own stamps
// (pockets, Journal item cards) also still named the old card, so a rewind
// (tail delete, or a regenerate once allowed) put them back under an id
// nothing reads.
//
// Red-proved: on the tip before the fix, all five tests fail (the four
// refusals and the guest/stamp case). With only the message id re-keyed and
// the `'char'` stamps left alone, the item-card case still fails.

import 'dart:convert';
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
          return Directory.systemTemp.createTempSync('fpai_msgowner_').path;
        }
        return null;
      });
}

/// Answers every reply call with one plain line and every eval with nothing.
/// The line is never asserted: the tests count reply calls to tell "the
/// regenerate or continue reached the model" from "it was refused".
class _CountingLlm extends LLMService {
  int replyCalls = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      replyCalls++;
      yield 'The porch swing creaks.';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'CountingLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late ChatService chat;
  late _CountingLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db, storage);
    llm = _CountingLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = llm;
    await storage.initialized;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 400 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<CharacterCard> seedCard(String name) async {
    final card = CharacterCard(
      name: name,
      description: 'Exists only inside the message-owner import test.',
      firstMessage: 'The screen door bangs.',
    );
    final tmpDir = Directory.systemTemp.createTempSync('msgowner_card_');
    final pngPath = '${tmpDir.path}/$name.png';
    await V2CardService().saveCardAsPng(card, pngPath, null);
    card.imagePath = pngPath;
    await repo.addCharacter(card);
    return card;
  }

  /// One real 1:1 turn, so the reply carries the owner stamp the app itself
  /// writes (the stream target's characterId is the speaker's id).
  Future<void> chatOnce(CharacterCard card) async {
    await chat.setActiveCharacter(card);
    await chat.sendMessage('Evening.');
    await drainTurn();
    expect(chat.messages.last.isUser, isFalse);
    expect(
      chat.messages.last.characterId,
      card.stableGroupId,
      reason: 'precondition: a 1:1 reply is stamped with its speaker id',
    );
  }

  Future<CharacterCard> enhancedCopyOf(CharacterCard base) async {
    final enhanced = await repo.duplicateCharacter(
      base,
      newNameOverride: '${base.name} (Enhanced)',
    );
    expect(enhanced, isNotNull);
    expect(enhanced!.stableGroupId, isNot(base.stableGroupId));
    expect(await chat.copyChatsForEnhance(from: base, to: enhanced), 1);
    return enhanced;
  }

  Future<CharacterCard> importedOntoOtherCard() async {
    final bytes = await chat.exportToFpchat();
    expect(bytes, isNotNull);
    final target = await seedCard('Bram');
    await chat.setActiveCharacter(target);
    // The user's "Restore full Front Porch state anyway" answer.
    final result = await chat.importChatPackage(
      bytes!,
      onCharacterMismatch: (_, _) async => true,
    );
    expect(result.fullRestore, isTrue);
    return target;
  }

  for (final regenerate in [true, false]) {
    final action = regenerate ? 'regenerate' : 'continue';
    final refusal = regenerate ? 'Can’t regenerate' : 'Can’t continue';

    Future<void> act() =>
        regenerate ? chat.regenerateLastMessage() : chat.continueGeneration();

    Future<void> expectReachesModel() async {
      final before = llm.replyCalls;
      await act();
      await drainTurn();
      expect(
        chat.guestActivityStatus ?? '',
        isNot(contains(refusal)),
        reason: 'the host is not a guest who left the scene',
      );
      expect(
        llm.replyCalls,
        before + 1,
        reason: '$action must reach the model',
      );
    }

    test('AI Enhance: $action on the last copied reply works', () async {
      final base = await seedCard('Odile');
      await chatOnce(base);
      await enhancedCopyOf(base);
      await expectReachesModel();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Import Chat onto another card: $action on the last reply '
        'works', () async {
      await chatOnce(await seedCard('Ines'));
      await importedOntoOtherCard();
      await expectReachesModel();
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('a scene guest keeps their id; the host\'s pocket and Journal item '
      'stamps move to the new card', () async {
    final base = await seedCard('Odile');
    // Scene-guest turns and item-card retires need the guest and pockets
    // machinery, so these rows are written in the shapes their producers
    // write: a guest reply stamped with the guest's id, `pockets_before`
    // on shared metadata (chat_service_pockets_pass.dart) and
    // `item_cards_retired` on the swipe (chat_service_item_cards.dart).
    const wrenId = 'Wren_1700000000123';
    final baseId = base.stableGroupId;
    const sid = '1700000000303';
    await db.insertSession(
      SessionsCompanion.insert(id: sid, characterId: Value(base.dbId)),
    );
    final rows = <(String, bool, String?, String, String?, String?)>[
      ('You', true, null, 'Evening.', null, null),
      ('Odile', false, baseId, 'You are late.', null, null),
      ('You', true, null, 'Wren, you too?', null, null),
      ('Wren', false, wrenId, 'Wren waves from the steps.', null, null),
      ('You', true, null, 'Where are the keys?', null, null),
      (
        'Odile',
        false,
        baseId,
        'She hangs the house keys back on the hook.',
        jsonEncode({
          'pockets_before': {
            'char': baseId,
            'record': {'worn': <Object>[], 'carrying': <Object>[]},
          },
        }),
        jsonEncode([
          {
            'item_cards_retired': [
              {
                'char': baseId,
                'item': 'house keys',
                'content': 'Odile keeps the house keys on the hook.',
                'positions': [1],
                'heat': 0.6,
              },
            ],
          },
        ]),
      ),
    ];
    for (final (i, (sender, isUser, cid, line, meta, swipeMeta))
        in rows.indexed) {
      await db.insertMessage(
        MessagesCompanion.insert(
          id: '$sid-m$i',
          sessionId: sid,
          position: i,
          sender: sender,
          isUser: isUser,
          characterId: Value(cid),
          swipes: Value(jsonEncode([line])),
          metadata: Value(meta),
          swipeMetadata: Value(swipeMeta),
        ),
      );
    }

    final enhanced = await enhancedCopyOf(base);
    final newId = enhanced.stableGroupId;
    expect(chat.messages, hasLength(rows.length));
    final ids = [for (final m in chat.messages) m.characterId];
    final pocketsOwner =
        (chat.messages[5].metadata?['pockets_before'] as Map?)?['char'];

    // Regenerate rewinds the turn: the retired item card comes back, and it
    // must come back under the card the chat now belongs to.
    await chat.regenerateLastMessage();
    await drainTurn();
    expect(chat.guestActivityStatus ?? '', isNot(contains('left the scene')));
    final newSid = chat.currentSessionId!;
    var cards = await chat.journalStore.cardsFor(newSid, newId);
    for (
      var i = 0;
      i < 300 && !cards.any((c) => c.content.contains('house keys'));
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cards = await chat.journalStore.cardsFor(newSid, newId);
    }
    expect(
      cards.map((c) => c.content),
      contains('Odile keeps the house keys on the hook.'),
    );
    expect(
      await chat.journalStore.cardsFor(newSid, baseId),
      isEmpty,
      reason: 'a card put back under the old id is unreachable',
    );
    expect(ids[1], newId);
    expect(ids[3], wrenId, reason: 'a real guest stays a guest');
    expect(ids[5], newId);
    expect(pocketsOwner, newId, reason: 'the pockets rewind reads this owner');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
