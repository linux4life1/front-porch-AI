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

// MESSAGE 0 — the sidebar has to show an authored wardrobe the moment a chat
// opens, before anyone has typed anything.
//
// Reported: "why do I not see pockets or wardrobe in the chat sidebar on
// message 0 when pockets and wardrobe is enabled?"
//
// THE BUG, and it is a half-finished fix of mine rather than a fresh one.
// `seedPocketsFromCards()` was introduced so an authored wardrobe reaches turn
// 1's PROMPT, and it was wired at exactly two call sites: the top of
// `sendMessage`, and session restore. Neither of those runs when a chat is
// merely OPENED. Meanwhile all three fresh-chat reset sites
// (chat_entry, and both branches of startNewChat) set `_pockets = null` and
// stop there, each carrying a comment saying the record "re-seeds from the card
// on the first pass" — which was true when it was written and stopped being
// true when the seed moved earlier.
//
// So: open a chat with a character her author has dressed, and the record is
// null until you send your first message. `pocketsFor` returns null, PocketsRow
// renders SizedBox.shrink(), and the sidebar shows nothing at all — at exactly
// the moment an author who has just set a wardrobe goes to check it saved.
//
// The turn-1 test file next door states this hole in its own header ("The
// sidebar had the same hole: blank until after the first reply") and then never
// asserts it, because every assertion in it is against InventoryInjection — the
// prompt. That is the "verified via source review" trap: the sentence was
// written, the guard was not. This file is the guard.
//
// It drives the REAL ChatService against an in-memory Drift database, the same
// harness start_fresh_chat_test uses, because the whole question is whether an
// entry path calls the seed — which no amount of testing the seed itself can
// answer.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    // Not awaited: nothing here asserts on personas.
    final personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db)
      // setActiveGroup returns early without one, so the group case below
      // would resolve zero members and quietly assert nothing.
      ..setCharacterRepository(CharacterRepository(db, storage));

    // AWAIT THE REAL SIGNAL, never a sleep. StorageService kicks off `_init()`
    // from its constructor and that init ends with `_realismSettings.load()`,
    // which reads SharedPreferences over the top of whatever is in memory. Set
    // the switch before it lands and the write is doubly lost — `prefs` is
    // still null so nothing is persisted, and `load()` then resets the field to
    // its default.
    //
    // This file first used `await Future.delayed(50ms)`, copied from the
    // sibling suite. It passed alone every time and failed in the full
    // `--concurrency=4` run, where four suites compete and 50ms stops being
    // enough. A flaky guard is worse than none, so the delay is gone rather
    // than lengthened.
    await storage.initialized;

    // The one switch Pockets answers to. Everything below is about a user who
    // has turned it ON and sees nothing.
    await storage.realismSettings.setPocketsEnabled(true);
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  /// A card dressed the way the character editor now writes it.
  CharacterCard dressed(String name, String id) =>
      CharacterCard(
        name: name,
        firstMessage: 'Evening.',
        frontPorchExtensions: FrontPorchExtensions(
          inventory: Pockets.cardJsonFrom(
            worn: const ['flour-dusted apron (well-worn)'],
            carrying: const ['shop keys'],
          ),
        ),
      )..dbId = id;

  /// What the sidebar's Builder reads — `chat.pocketsFor(...)`, keyed exactly
  /// as character_state_group.dart keys it. Asserting through this rather than
  /// an internal field is the point: it is the value the widget gets.
  Pockets? sidebarSees() {
    final c = chat.activeCharacter;
    if (c == null) return null;
    return chat.pocketsFor(chat.characterIdFor(c));
  }

  void expectDressed(Pockets? p, {required String reason}) {
    expect(p, isNotNull, reason: reason);
    expect(
      p!.worn.map((i) => i.name),
      contains('flour-dusted apron'),
      reason: reason,
    );
    expect(p.carrying.map((i) => i.name), contains('shop keys'), reason: reason);
  }

  test('opening a chat with a dressed character shows her wardrobe at once', () async {
    await chat.setActiveCharacter(dressed('Jennifer', 'char-open'));

    expectDressed(
      sidebarSees(),
      reason: 'THE REPORTED BUG. Nothing has been typed yet — this is message '
          '0, the greeting. seedPocketsFromCards ran only from sendMessage and '
          'session restore, so the record was null and the sidebar drew '
          'nothing until after the first reply',
    );
  });

  test('and again after New Chat, which is where an author actually looks', () async {
    // The likeliest real sequence: dress her in the editor, open her, start a
    // fresh chat to try it out.
    final card = dressed('Jennifer', 'char-new');
    await chat.setActiveCharacter(card);
    await chat.startNewChat();

    expectDressed(
      sidebarSees(),
      reason: 'startNewChat nulls the record in its own reset block and did '
          'not re-seed; its comment claimed the first pass would',
    );
  });

  test('an undressed character still gets no record, not an empty one', () async {
    // The seed deliberately leaves the record ABSENT rather than empty when a
    // card authored nothing: the web facade sends null to hide its panel, so an
    // empty record would show an empty panel instead. Fixing the bug above must
    // not quietly change that.
    await chat.setActiveCharacter(
      CharacterCard(name: 'Plain', firstMessage: 'Hi.')..dbId = 'char-plain',
    );

    expect(sidebarSees(), isNull);
  });

  test('with the switch off, opening a dressed character shows nothing', () async {
    // Off still means off. The seed is gated, and `pocketsFor` is gated again
    // on the read, so turning the feature on later must be what reveals her —
    // not the chat having been opened while it was on.
    await storage.realismSettings.setPocketsEnabled(false);
    await chat.setActiveCharacter(dressed('Jennifer', 'char-off'));

    expect(sidebarSees(), isNull);
  });

  test('turning the switch off hides a record that already exists', () async {
    // THE READ GATE. Opening with the switch already down (the test above)
    // never seeds, so `_pockets` stays null and deleting the pocketsFor
    // early-return still looks green. The gate's comment says it HIDES and
    // does not erase: seed first, then flip the switch, then the same
    // sidebar read must be null while the stored record stays.
    await chat.setActiveCharacter(dressed('Jennifer', 'char-hide'));
    expectDressed(
      sidebarSees(),
      reason: 'need a live record before the switch goes down',
    );

    await storage.realismSettings.setPocketsEnabled(false);
    expect(
      chat.pocketsFor(chat.characterIdFor(chat.activeCharacter!)),
      isNull,
      reason:
          'pocketsFor must hide when the switch is down — the seed already '
          'ran, so a missing gate would still return the apron and keys',
    );
  });

  test('a group member arrives dressed too — parity, and a different trap', () async {
    // Parity is mandatory in this project, and the group path had its own
    // ordering hazard: startNewChat's group branch nulls the record and THEN
    // rebuilds _groupRealism from the group's member baselines a dozen lines
    // later, so a seed placed beside the null would be wiped for every group
    // while working perfectly for every 1:1. That is why the call sits after
    // the if/else closes rather than next to the assignment it undoes.
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-1', name: 'The Bakery'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-1',
        groupId: 'grp-1',
        name: 'Jennifer',
        frontPorchExtensions: Value(
          // The envelope FrontPorchExtensions.fromJson actually reads. A bare
          // top-level 'inventory' parses to {} and the assertion below would
          // fail against correct code.
          jsonEncode({
            'realism_engine': {
              'inventory': Pockets.cardJsonFrom(
                worn: const ['flour-dusted apron (well-worn)'],
                carrying: const ['shop keys'],
              ),
            },
          }),
        ),
      ),
    );

    // The repo must be passed explicitly: setActiveGroup's no-repo fallback
    // reads AppDatabase.instance() — the singleton — which is not this test's
    // in-memory database, so the members would silently resolve to none.
    await chat.setActiveGroup(
      GroupChat(id: 'grp-1', name: 'The Bakery'),
      groupRepo: GroupChatRepository(storage, db),
    );

    final member = chat.groupCharacters.firstWhere((c) => c.name == 'Jennifer');
    expectDressed(
      chat.pocketsFor(chat.characterIdFor(member)),
      reason: 'entering a group must dress its members exactly as entering a '
          '1:1 dresses her — the group prompt reads the same record',
    );

    // And through the other entry: a fresh chat inside the group.
    await chat.startNewChat();
    final after = chat.groupCharacters.firstWhere((c) => c.name == 'Jennifer');
    expectDressed(
      chat.pocketsFor(chat.characterIdFor(after)),
      reason: 'startNewChat in a group — the branch whose _groupRealism rebuild '
          'would have eaten a seed placed beside the null',
    );
  });


  test('a group New Chat re-reads the Porch Life Chaos default', () async {
    // The 1:1 branch of startNewChat re-seeded Chaos from card-or-global; the
    // group branch touched Chaos at all. It simply inherited whatever
    // setActiveGroup had left in the service — usually right, which is why it
    // went unnoticed, and wrong the moment the global CHANGES while a group is
    // open. "New Chat" is exactly when a user expects their defaults re-applied.
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-chaos', name: 'The Bakery'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-c',
        groupId: 'grp-chaos',
        name: 'Jennifer',
      ),
    );

    await chat.setActiveGroup(
      GroupChat(id: 'grp-chaos', name: 'The Bakery'),
      groupRepo: GroupChatRepository(storage, db),
    );
    expect(chat.chaosModeService.chaosModeEnabled, isFalse);

    // The user turns Chaos on globally with the group already open, then starts
    // a fresh chat in it.
    await storage.realismSettings.setChaosModeDefault(true);
    await chat.startNewChat();

    expect(
      chat.chaosModeService.chaosModeEnabled,
      isTrue,
      reason: 'the group branch never re-read the global, so a fresh group chat '
          'started with Chaos off however the user had set it',
    );
  });

  test('a chat that has moved on is not re-dressed from the card', () async {
    // The other half of the seed's contract: it must never hand back something
    // she put down. Simulate a chat that has already recorded a change, then
    // re-enter it the way switching characters and coming back does.
    final card = dressed('Jennifer', 'char-moved');
    await chat.setActiveCharacter(card);
    final id = chat.characterIdFor(chat.activeCharacter!);

    chat.setPocketsFor(id, Pockets.fromJson(Pockets.cardJsonFrom(
      worn: const ['apron (muddy)'],
      carrying: const [],
    )));

    // Re-seeding now would resurrect the shop keys she is no longer carrying.
    chat.seedPocketsFromCards();

    final p = chat.pocketsFor(id);
    expect(p!.carrying, isEmpty, reason: 'the keys were put down and stay down');
    expect(p.worn.single.name, 'apron');
  });
}
