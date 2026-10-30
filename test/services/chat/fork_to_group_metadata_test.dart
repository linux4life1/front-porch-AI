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

// CONVERTING A 1:1 INTO A GROUP MUST NOT THROW THE TRANSCRIPT'S METADATA AWAY.
//
// `/join --full <name>` (and the sidebar's "promote scene") duplicates every
// message row into the new group session by hand. That copy listed eight
// columns and left `metadata` / `swipeMetadata` out, so they inserted NULL —
// and because setActiveGroup immediately re-hydrates `_messages` from exactly
// those rows, the in-memory copies were dropped too.
//
// Metadata is not bookkeeping here. A generated image is an EMPTY-text message
// whose only content is `metadata['image_path']`, so the whole history's
// pictures rendered as blank bubbles; `realism_state` / `needs_pre_turn_vector`
// / `pockets_before` are the baseline every later regen, swipe and delete
// rewinds to, so the converted chat also lost its time machine.
//
// Proven to fail: drop the two columns from the companion in
// chat_service_group_membership.dart and both expectations go red (image_path
// null, realism_state null).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/chat/chat.dart' show Biome;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart' show parseGroupRealismSeeds;
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_forkmeta_').path;
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
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
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
          ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  CharacterCard card(String name, String id) => CharacterCard(
    name: name,
    description: 'Exists only inside the fork-metadata test.',
    firstMessage: 'The screen door bangs shut behind you.',
  )..dbId = id;

  test('forking a 1:1 into a group carries every message stamp with it', () async {
    await chat.setActiveCharacter(card('Nia', 'char-fork-host'));

    // A generated image: empty text, all of its content in metadata. If the
    // copy drops metadata this message becomes a blank bubble forever.
    await chat.addGeneratedImageMessage(
      '/pictures/porch-dusk.png',
      'a porch at dusk',
    );
    // And a stamp of the kind every rewind reads back.
    final stamped = chat.messages.last;
    stamped.metadata!['realism_state'] = {'affection': 42};

    final group = await chat.forkToGroupChat([
      card('Marisol', 'char-fork-arrival'),
    ], GroupChatRepository(storage, db));

    expect(group, isNotNull, reason: 'the conversion itself must succeed');

    final carried = chat.messages.where(
      (m) => m.metadata?['is_generated_image'] == true,
    );
    expect(
      carried,
      hasLength(1),
      reason:
          'THE BUG: the hand-written row copy omitted the metadata column, and '
          'setActiveGroup re-hydrates the list from those very rows — so the '
          'image message survived as an empty bubble with nothing in it.',
    );
    expect(carried.single.metadata!['image_path'], '/pictures/porch-dusk.png');
    expect(
      carried.single.metadata!['realism_state'],
      {'affection': 42},
      reason:
          'the snapshot regen/swipe/delete rewind to must cross the conversion '
          'too, or the whole pre-fork history becomes un-rewindable',
    );
  });

  // Discord report: `/join --full` turned the user into an unrelated persona.
  // The fork wrote the group session row without userPersonaId, and
  // setActiveGroup re-activates the persona from that row — so it fell back
  // to the default. Proven to fail: drop userPersonaId from the companion in
  // chat_service_group_membership.dart and both expectations go red.
  test(
    'forking a 1:1 into a group keeps the chat\'s persona, not the default',
    () async {
      final personas = UserPersonaService(db);
      final forkChat =
          ChatService(
              KoboldService(storage),
              personas,
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(CharacterRepository(db, storage));
      addTearDown(forkChat.dispose);
      while (personas.personas.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final defaultId = personas.defaultPersonaId;
      // Persona ids are epoch-millis — space the new one out.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final lady = await personas.createPersona(
        'Lady',
        'Victoria',
        'A polite Victorian lady.',
        null,
        activate: false,
      );
      expect(lady, isNot(defaultId));

      await forkChat.setActiveCharacter(card('Maid', 'char-persona-host'));
      await personas.setActivePersona(lady);

      final group = await forkChat.forkToGroupChat([
        card('Stranger', 'char-persona-arrival'),
      ], GroupChatRepository(storage, db));
      expect(group, isNotNull, reason: 'the conversion itself must succeed');

      expect(
        personas.persona.id,
        lady,
        reason: 'the converted group must speak as the 1:1\'s persona',
      );
      final row = await db.getSessionById(forkChat.currentSessionId!);
      expect(row!.userPersonaId, lady);
    },
  );

  group('a promoted guest and the chat\'s place', () {
    late WorldRepository worlds;
    late ChatService promoteChat;
    late String oneToOne;
    late List<({int effectiveFromDay, String biomeJson})> spansBefore;

    // A 1:1 at the Tea Rooms with a lite guest present, then the guest is
    // promoted to a full member — the user's exact steps.
    setUp(() async {
      final repo = CharacterRepository(db, storage);
      final personas = UserPersonaService(db);
      worlds = WorldRepository(storage, db);
      promoteChat =
          ChatService(KoboldService(storage), personas, storage, worlds)
            ..setDatabase(db)
            ..setCharacterRepository(repo)
            ..setGroupChatRepository(GroupChatRepository(storage, db));
      addTearDown(promoteChat.dispose);

      for (final w in [
        model.World(
          id: 'town',
          name: 'Bletchfield',
          lorebook: Lorebook(entries: []),
          biomeId: 'temperate',
        ),
        model.World(
          id: 'cafe',
          name: 'Tea Rooms',
          lorebook: Lorebook(entries: []),
          parentWorldId: 'town',
          climateEnabled: false,
        ),
        model.World(
          id: 'pier',
          name: 'Old Pier',
          lorebook: Lorebook(entries: []),
          parentWorldId: 'town',
          climateEnabled: false,
        ),
      ]) {
        await worlds.saveWorld(w);
      }
      final host = CharacterCard(
        name: 'Nia',
        description: 'Exists only inside the fork-place test.',
        firstMessage: 'The kettle whistles.',
        worldNames: ['Bletchfield'],
      );
      final guest = CharacterCard(
        name: 'Marisol',
        description: 'Exists only inside the fork-place test.',
        firstMessage: 'Mind if I sit?',
      );
      await repo.addCharacter(host);
      await repo.addCharacter(guest);
      await promoteChat.startFreshChatWith(
        character: host,
        personaId: personas.persona.id,
      );
      oneToOne = promoteChat.currentSessionId!;
      await promoteChat.setChatPlaceSlots(primaryId: 'cafe', loreIds: ['town']);
      // A mid-chat climate changeover the story has already lived through.
      await worlds.setChatBiome(
        chatId: oneToOne,
        dayCount: 1,
        biome: Biome.builtInById('continental')!,
      );
      spansBefore = await worlds.getChatBiomeSpanRows(oneToOne);
      expect(spansBefore, isNotEmpty);
      await storage.webSearchSettings.setChatWikiUrl(
        oneToOne,
        'https://tea-rooms.example/wiki/',
      );

      await promoteChat.debugEnterSceneGuestSilent(guest);
      expect(promoteChat.sceneGuestCards.map((c) => c.name), ['Marisol']);
      await promoteChat.joinFull(promoteChat.sceneGuestCards.single);
      expect(promoteChat.activeGroup, isNotNull, reason: 'now a group');
    });

    // Local report: the converted group had no Setting at all. The fork
    // wrote a fresh session id with no chat_worlds rows, so setActiveGroup
    // loaded an empty place. Proven to fail: drop the world carry from
    // forkToGroupChat in chat_service_group_membership.dart and the Setting,
    // Lore, climate span and wiki expectations go red.
    test('the group keeps the 1:1\'s world and place', () async {
      final groupSession = promoteChat.currentSessionId!;
      expect(groupSession, isNot(oneToOne));
      expect(
        promoteChat.chatPrimaryWorldId,
        'cafe',
        reason: 'THE BUG: the converted group opened with no Setting',
      );
      expect(promoteChat.chatLoreWorldIds, ['town']);
      final stored = await worlds.getChatWorldAttachments(groupSession);
      expect(stored.primaryId, 'cafe', reason: 'and it survives a reopen');
      final spansAfter = await worlds.getChatBiomeSpanRows(groupSession);
      expect(
        spansAfter.map((r) => (r.effectiveFromDay, r.biomeJson)),
        spansBefore.map((r) => (r.effectiveFromDay, r.biomeJson)),
        reason: 'the same story keeps its weather history',
      );
      expect(
        storage.webSearchSettings.wikiUrlForChat(groupSession),
        'https://tea-rooms.example/wiki/',
      );
      // Changed with the group Setting split: the group's settings for new
      // chats now come from the chat's own Setting (Tea Rooms, inside
      // Bletchfield), stored by world id instead of the card's name ref.
      // Same world, same starting place for a later New chat.
      expect(promoteChat.activeGroup!.worldIds, [
        'town',
      ], reason: 'a later New chat in the group starts in the host\'s world');
    });

    // The way back: a move made in the group must win when the guest leaves
    // and the group collapses to a 1:1, not the place the 1:1 had before.
    test('collapsing back to a 1:1 keeps the group\'s newer place', () async {
      final groupSession = promoteChat.currentSessionId!;
      await promoteChat.setChatPlaceSlots(primaryId: 'pier', loreIds: ['town']);

      final marisol = promoteChat.groupCharacters.firstWhere(
        (c) => c.name == 'Marisol',
      );
      await promoteChat.removeCharacterFromGroup(
        marisol,
        GroupChatRepository(storage, db),
      );

      expect(promoteChat.activeGroup, isNull, reason: 'back to a 1:1');
      expect(promoteChat.currentSessionId, groupSession);
      expect(
        promoteChat.chatPrimaryWorldId,
        'pier',
        reason: 'the group\'s move replaces the old 1:1 place',
      );
      expect(promoteChat.chatLoreWorldIds, ['town']);
    });
  });

  // Local report: after adding someone to a 1:1 with realism on, Edit Group
  // said realism and needs were off. The fork saved the group's settings for
  // new chats as an empty '{}', which both the editor and a New Chat read as
  // off. Proven to fail: drop _saveForkTemplate from forkToGroupChat and the
  // seed expectations go red; flip inheritCharacterLorebooks back and the
  // lorebook one does.
  test(
    'a fork with realism on saves realism on for the group\'s new chats',
    () async {
      await chat.setActiveCharacter(card('Nia', 'char-fork-realism-host'));
      await chat.setRealismEnabled(true);
      await chat.setNeedsSimEnabled(true);
      await chat.addGeneratedImageMessage('/pictures/porch.png', 'a porch');
      final groups = GroupChatRepository(storage, db);

      final group = await chat.forkToGroupChat([
        card('Marisol', 'char-fork-realism-guest'),
      ], groups);

      expect(group, isNotNull);
      expect(
        chat.realismEnabled,
        isTrue,
        reason: 'the forked chat itself keeps the 1:1\'s realism',
      );
      await groups.reload();
      final saved = groups.getById(group!.id)!;
      final seeds = parseGroupRealismSeeds(saved.defaultMemberRealismState);
      expect(
        seeds,
        hasLength(2),
        reason: 'THE BUG: no member seeds, so new chats started realism-off',
      );
      expect(
        seeds.values.every((s) => (s['needs'] as Map?)?.isNotEmpty ?? false),
        isTrue,
        reason: 'needs was on in the 1:1, so new chats start with needs on',
      );
      expect(
        saved.inheritCharacterLorebooks,
        isTrue,
        reason: 'the host\'s lorebook fired in the 1:1 and must keep firing',
      );
    },
  );

  // A character card split into its Setting and lore-only worlds (the 1:1
  // world picker). Proven to fail: drop the card's loreWorldNames from
  // _seedChatWorldsForNewSession (chat_service_session_fork.dart), the
  // loreWorldIds copy in forkToGroupChat, or allWorldNames in
  // _createGroupMember, and the matching expectation goes red.
  group('a character card with its Setting and lore split', () {
    late WorldRepository worlds;
    late ChatService splitChat;
    late CharacterRepository repo;
    late UserPersonaService personas;
    late CharacterCard host;

    setUp(() async {
      repo = CharacterRepository(db, storage);
      personas = UserPersonaService(db);
      worlds = WorldRepository(storage, db);
      splitChat = ChatService(KoboldService(storage), personas, storage, worlds)
        ..setDatabase(db)
        ..setCharacterRepository(repo)
        ..setGroupChatRepository(GroupChatRepository(storage, db));
      addTearDown(splitChat.dispose);

      for (final w in [
        model.World(
          id: 'town',
          name: 'Bletchfield',
          lorebook: Lorebook(entries: []),
          biomeId: 'temperate',
        )..defaultPlaceId = 'cafe',
        model.World(
          id: 'cafe',
          name: 'Tea Rooms',
          lorebook: Lorebook(entries: []),
          parentWorldId: 'town',
          climateEnabled: false,
        ),
        model.World(
          id: 'myth',
          name: 'Old Songs',
          lorebook: Lorebook(entries: []),
          climateEnabled: false,
        ),
      ]) {
        await worlds.saveWorld(w);
      }
      host = CharacterCard(
        name: 'Nia',
        description: 'Exists only inside the split-card test.',
        firstMessage: 'The kettle whistles.',
        worldNames: ['town'],
        loreWorldNames: ['myth'],
      );
      await repo.addCharacter(host);
      await splitChat.startFreshChatWith(
        character: host,
        personaId: personas.persona.id,
      );
    });

    test('a new 1:1 chat meets at the Setting and reads the lore', () async {
      expect(splitChat.chatPrimaryWorldId, 'cafe');
      expect(
        splitChat.chatLoreWorldIds,
        contains('myth'),
        reason: 'the card\'s lore-only world must reach the chat',
      );
    });

    test('a fork to a group keeps the card\'s lore, in the template and '
        'in the host\'s member row', () async {
      // An emptied chat leaves the card as the only source of the template.
      await splitChat.setChatPlaceSlots(primaryId: null, loreIds: const []);
      final guest = CharacterCard(
        name: 'Marisol',
        description: 'Exists only inside the split-card test.',
        firstMessage: 'Mind if I sit?',
      );
      await repo.addCharacter(guest);
      final group = await splitChat.forkToGroupChat([
        guest,
      ], GroupChatRepository(storage, db));

      expect(group, isNotNull);
      expect(splitChat.activeGroup!.worldIds, ['town']);
      expect(
        splitChat.activeGroup!.loreWorldIds,
        ['myth'],
        reason: 'a later New chat in the group reads the card\'s lore too',
      );
      final rows = await db.getGroupMembers(splitChat.activeGroup!.id);
      final hostRow = rows.firstWhere((r) => r.name == 'Nia');
      expect(
        (jsonDecode(hostRow.worldNames) as List).cast<String>(),
        containsAll(['town', 'myth']),
        reason: 'group Inherit reads the member row, which has no lore field',
      );
    });
  });
}
