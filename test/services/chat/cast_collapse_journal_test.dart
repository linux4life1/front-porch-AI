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

// THE DIARY MUST FOLLOW ITS OWNER THROUGH A CAST COLLAPSE.
//
// A group member's journal cards are keyed by the MEMBER INSTANCE id (the
// member UUID), while a 1:1 reads them under the library card's
// stableGroupId. When a group drops to one member the chat is re-homed in
// place to that member's library character, and the collapse re-keys
// objectives, growth rings and embeddings — journal cards were missed, so the
// survivor's whole diary (memories, item placements, promises) stayed in the
// same session under an id no reader ever asks for while her quests and rings
// came along.
//
// Red-proved: with the `_moveJournalCards` call removed from the collapse,
// the first test's "readable under the library id" expectation returns [].
// Likewise the second test's delete assertion, with its call removed.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
          return Directory.systemTemp.createTempSync('fpai_collapse_').path;
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

  const groupId = 'grp-collapse';
  const sid = '1700000000303';

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late GroupChatRepository groupRepo;
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
    groupRepo = GroupChatRepository(storage, db);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..setGroupChatRepository(groupRepo)
          ..testLlmServiceOverride = _InertLlm();
    await storage.initialized;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  /// The survivor's library character. A distinct portrait basename is what
  /// makes her library id differ from her member instance id.
  Future<CharacterCard> seedLibraryCard(String name) async {
    final card = CharacterCard(
      name: name,
      description: 'Exists only inside the cast-collapse test.',
      firstMessage: 'The porch boards creak.',
    );
    final tmpDir = Directory.systemTemp.createTempSync('collapse_card_');
    final pngPath = '${tmpDir.path}/${name}_1700000000.png';
    await V2CardService().saveCardAsPng(card, pngPath, null);
    card.imagePath = pngPath;
    await repo.addCharacter(card);
    return card;
  }

  /// The roster reload only keeps members whose private avatar FILE exists, so
  /// the portrait has to be on disk for the member to survive a removal.
  Future<void> seedMember(
    String memberId,
    String name, {
    String? originStableId,
  }) async {
    final avatarDir = Directory(
      p.join(storage.groupsDir.path, groupId, 'avatars'),
    );
    await avatarDir.create(recursive: true);
    await V2CardService().saveCardAsPng(
      CharacterCard(name: name),
      p.join(avatarDir.path, '$memberId.png'),
      null,
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: memberId,
        groupId: groupId,
        name: name,
        avatarFilename: Value('$memberId.png'),
        memberState: originStableId == null
            ? const Value('{}')
            : Value('{"originStableId":"$originStableId"}'),
      ),
    );
  }

  Future<void> enterGroupWithSession() async {
    await db.insertGroup(GroupsCompanion.insert(id: groupId, name: 'The Cast'));
    await db.insertSession(
      SessionsCompanion.insert(id: sid, groupId: const Value(groupId)),
    );
    await db.insertMessage(
      MessagesCompanion.insert(
        id: '$sid-m0',
        sessionId: sid,
        position: 0,
        sender: 'You',
        isUser: true,
        swipes: const Value('["Evening, both of you."]'),
      ),
    );
  }

  test('collapsing a group back to a 1:1 carries the survivor\'s journal cards '
      'onto her library id, so her diary is still readable', () async {
    final nia = await seedLibraryCard('Nia');
    await enterGroupWithSession();
    await seedMember('mem-nia', 'Nia', originStableId: nia.stableGroupId);
    await seedMember('mem-rue', 'Rue');

    await chat.setActiveGroup(
      GroupChat(id: groupId, name: 'The Cast'),
      groupRepo: groupRepo,
    );
    expect(chat.currentSessionId, sid);
    final member = chat.groupCharacters.firstWhere((c) => c.name == 'Nia');
    expect(
      member.stableGroupId,
      'mem-nia',
      reason: 'a member card is keyed by its instance id, not the library id',
    );
    expect(member.stableGroupId, isNot(nia.stableGroupId));

    // Her group-era diary, written under the member instance id.
    await chat.journalStore.addCard(
      sessionId: sid,
      characterId: 'mem-nia',
      content: 'She set her car keys down on the hallway table.',
      category: 'moment',
      maxCards: 40,
    );

    final rue = chat.groupCharacters.firstWhere((c) => c.name == 'Rue');
    expect(await chat.removeCharacterFromGroup(rue, groupRepo), isTrue);

    // The chat is now a 1:1 with the library character…
    expect(chat.activeGroup, isNull);
    expect(chat.activeCharacter?.name, 'Nia');
    expect(chat.currentSessionId, sid);

    // …and her diary came with her.
    final carried = await chat.journalStore.cardsFor(sid, nia.stableGroupId);
    expect(carried, hasLength(1));
    expect(carried.first.content, contains('hallway table'));
    expect(
      await chat.journalStore.cardsFor(sid, 'mem-nia'),
      isEmpty,
      reason: 'a card left under the member id is unreachable forever',
    );
  });

  test('hard-removing a member from a still-multi-member group deletes that '
      'member\'s journal cards (no unreadable leftovers)', () async {
    await enterGroupWithSession();
    await seedMember('mem-nia', 'Nia');
    await seedMember('mem-rue', 'Rue');
    await seedMember('mem-sol', 'Sol');

    await chat.setActiveGroup(
      GroupChat(id: groupId, name: 'The Cast'),
      groupRepo: groupRepo,
    );
    await chat.journalStore.addCard(
      sessionId: sid,
      characterId: 'mem-rue',
      content: 'Rue hid the spare key under the mat.',
      category: 'moment',
      maxCards: 40,
    );
    await chat.journalStore.addCard(
      sessionId: sid,
      characterId: 'mem-nia',
      content: 'Nia keeps the porch light on.',
      category: 'moment',
      maxCards: 40,
    );

    final rue = chat.groupCharacters.firstWhere((c) => c.name == 'Rue');
    expect(await chat.removeCharacterFromGroup(rue, groupRepo), isTrue);
    expect(chat.activeGroup, isNotNull, reason: 'two members remain');

    expect(await chat.journalStore.cardsFor(sid, 'mem-rue'), isEmpty);
    expect(
      await chat.journalStore.cardsFor(sid, 'mem-nia'),
      hasLength(1),
      reason: 'only the removed member loses her diary',
    );
  });
}
