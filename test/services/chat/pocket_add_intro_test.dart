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

// HAND-ADDED ITEMS: THE GIFT AND THE EASTER EGG (maintainer feature,
// 2026-08-13).
//
// The sidebar panel was ✕-only. Now the user can put things IN — and the
// two ways of doing it are opposite fictions with opposite prompt notes:
//
//  * GIVE — handed over in-scene. Lands in her hands, and the next reply
//    has her accept it knowing it came from the user.
//  * ADD QUIETLY — conjured out-of-band. Lands in the chosen section, and
//    the next reply has her SURPRISED by something she cannot account for
//    ("how did I end up with this?").
//
// The note is one-shot with regen-honest consumption: it rides the next
// generation's prompt, a regenerate of that reply reproduces it (identical
// inputs law), and the user's FOLLOWING message drops it.
//
// Guards proven to fail before passing: with the intros block removed from
// the inventory injection, the surprise/gift prompt asserts go red; with
// _dropConsumedItemIntros unwired, the consumed-after-next-turn assert
// goes red.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show PocketSection;

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_padd_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  /// Every conversational prompt (the one call carrying a system prompt).
  final List<String> chatPrompts = [];

  /// Every pockets bookkeeping prompt.
  final List<String> pocketsPrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      chatPrompts.add(params.prompt);
      yield '*She hums on the porch, unhurried.*';
      return;
    }
    if (params.prompt.contains('You are keeping track of what')) {
      pocketsPrompts.add(params.prompt);
      yield '{"inventory_ops": []}';
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

  CharacterCard card(String dbId, {Map<String, dynamic>? inventory}) =>
      CharacterCard(
        name: 'Mara',
        description: 'Exists only inside the pocket-add test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: inventory == null
            ? null
            : FrontPorchExtensions(inventory: inventory),
      )..dbId = dbId;

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

  test('quiet add: record updated, next reply is surprised, note consumed '
      'after the following turn, regen reproduces it', () async {
    await chat.setActiveCharacter(card('char-padd-1'));
    final id = chat.characterIdFor(chat.activeCharacter!);

    await chat.addPocketItem(
      id,
      section: PocketSection.carrying,
      name: 'brass key (scuffed)',
    );
    expect(chat.pocketsFor(id)!.carrying.single.display, 'brass key (scuffed)');

    await chat.sendMessage('Anything new?');
    await drainTurn();
    expect(llm.chatPrompts, hasLength(1));
    expect(
      llm.chatPrompts.last,
      contains('NO memory of how it got there'),
      reason:
          'the Easter egg: a conjured item must reach the reply as '
          'genuine surprise, not slip in unremarked',
    );
    expect(llm.chatPrompts.last, contains('brass key (scuffed)'));

    // The eval recognizes it immediately: the record is its ground truth.
    expect(
      llm.pocketsPrompts.last,
      contains('brass key'),
      reason: 'the bookkeeping prompt must list the hand-added item',
    );

    // A regenerate of the reacting reply reproduces the reaction — the note
    // is consumed by the NEXT user turn, not by the prompt build.
    await chat.regenerateLastMessage();
    await drainTurn();
    expect(llm.chatPrompts, hasLength(2));
    expect(llm.chatPrompts.last, contains('NO memory of how it got there'));

    // The following user turn drops it.
    await chat.sendMessage('And now?');
    await drainTurn();
    expect(llm.chatPrompts, hasLength(3));
    expect(
      llm.chatPrompts.last,
      isNot(contains('NO memory of how it got there')),
      reason:
          'the reaction already played out — repeating it every turn '
          'would make her permanently baffled by her own keys',
    );
    // The item itself stays in the ordinary inventory fragment.
    expect(llm.chatPrompts.last, contains('brass key (scuffed)'));
  });

  test('gift: lands in her hands regardless of section, and the note names '
      'the giver instead of surprising her', () async {
    await chat.setActiveCharacter(card('char-padd-2'));
    final id = chat.characterIdFor(chat.activeCharacter!);

    await chat.addPocketItem(
      id,
      // Deliberately worn: a gift is handed over, not dressed onto her.
      section: PocketSection.worn,
      name: 'pocket watch',
      gift: true,
    );
    final p = chat.pocketsFor(id)!;
    expect(p.carrying.single.name, 'pocket watch');
    expect(p.worn, isEmpty);

    await chat.sendMessage('For you.');
    await drainTurn();
    expect(llm.chatPrompts.last, contains('has just handed Mara pocket watch'));
    expect(llm.chatPrompts.last, contains('knowing it came from'));
    expect(
      llm.chatPrompts.last,
      isNot(contains('NO memory of how it got there')),
      reason:
          'a gift is the opposite fiction — she knows exactly where it '
          'came from',
    );
  });

  test('the reaction fires in the chat the add happened in — not whichever '
      'chat is open when the user next sends', () async {
    // Hostile self-review find (2026-08-13): the intro queue is keyed per
    // CHARACTER, and a character appears in many chats. Without the session
    // stamp, add-then-switch made the NEXT chat's reply react to an item
    // its record never had. The card MUST author an inventory here: an
    // empty second-chat record would suppress the whole fragment and mask
    // the missing filter (that is how this guard's first red-proof failed
    // to go red).
    await chat.setActiveCharacter(
      card(
        'char-padd-4',
        inventory: {
          'carrying': ['sun hat'],
        },
      ),
    );
    final id = chat.characterIdFor(chat.activeCharacter!);
    final firstSession = chat.currentSessionId!;

    await chat.addPocketItem(
      id,
      section: PocketSection.carrying,
      name: 'brass key',
    );

    // A second chat with the same character, opened before the reaction ran.
    await chat.startNewChat();
    expect(chat.currentSessionId, isNot(firstSession));
    await chat.sendMessage('Fresh porch, fresh start.');
    await drainTurn();
    expect(
      llm.chatPrompts.last,
      isNot(contains('NO memory of how it got there')),
      reason:
          'the add belongs to the FIRST chat — reacting here would have '
          'her baffled by an item this record does not hold',
    );

    // Back in the original chat, the queued reaction still fires.
    await chat.loadSession(firstSession);
    await chat.sendMessage('Anything new?');
    await drainTurn();
    expect(
      llm.chatPrompts.last,
      contains('NO memory of how it got there'),
      reason:
          'returning to the chat the add happened in must still pay off '
          'the queued reaction',
    );
  });

  test('feature off or empty name: a strict no-op', () async {
    await chat.setActiveCharacter(card('char-padd-3'));
    final id = chat.characterIdFor(chat.activeCharacter!);

    await chat.addPocketItem(id, section: PocketSection.carrying, name: '   ');
    expect(chat.pocketsFor(id), isNull, reason: 'blank name adds nothing');

    await storage.realismSettings.setPocketsEnabled(false);
    await chat.addPocketItem(
      id,
      section: PocketSection.carrying,
      name: 'brass key',
    );
    await storage.realismSettings.setPocketsEnabled(true);
    expect(
      chat.pocketsFor(id),
      isNull,
      reason: 'the one Pockets switch gates the add like every other surface',
    );
  });

  test('correction: lands on worn, gift is ignored, next reply is NOT '
      'surprised and is NOT a gift', () async {
    // Wardrobe error-correction (2026-08-20): the model stripped them; the
    // user puts a coat back on the record. That is neither a gift (hands)
    // nor an Easter egg (magic coat). The inventory fragment already states
    // wearing as fact — that is enough for the next reply to be dressed.
    await chat.setActiveCharacter(card('char-padd-corr'));
    final id = chat.characterIdFor(chat.activeCharacter!);

    await chat.addPocketItem(
      id,
      section: PocketSection.worn,
      name: 'coat (buttoned)',
      gift: true,
      correction: true,
    );
    final p = chat.pocketsFor(id)!;
    expect(p.worn.single.display, 'coat (buttoned)');
    expect(
      p.carrying,
      isEmpty,
      reason: 'correction ignores gift — it must not force carrying',
    );

    await chat.sendMessage('You look cold.');
    await drainTurn();
    expect(
      llm.chatPrompts.last,
      isNot(contains('NO memory of how it got there')),
      reason: 'correcting a wardrobe error is not an Easter egg',
    );
    expect(
      llm.chatPrompts.last,
      isNot(contains('has just handed')),
      reason: 'correction is not a gift either',
    );
    expect(
      llm.chatPrompts.last,
      contains('coat (buttoned)'),
      reason: 'the ordinary inventory fragment still names what they wear',
    );
  });
}
