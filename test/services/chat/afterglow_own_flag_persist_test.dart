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

// A chat's own Afterglow flag survives every save and every carry between
// chats, whatever Porch Life says. #614 made Porch Life Afterglow the live
// gate and said the per-chat flag still rides the save wire. It did not: the
// 1:1 save, the fork into a group, the collapse back to a 1:1 and the branch
// from a message all read the gated getter, so each one replaced the chat's
// own choice with Porch Life's.
//
// Red proofs: put `nsfwCooldownEnabled` back for `storedNsfwCooldownEnabled`
// in the 1:1 save (chat_service_session_state_save), the fork's host capture
// (chat_service_group_membership), the collapse fallback
// (chat_service_cast_shrink) or the branch walk (chat_service_import_walk),
// and the matching test fails.

import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import '../../helpers/chat_db_teardown.dart';
import '../../helpers/refractory_judges.dart';

final Directory _root = Directory.systemTemp.createTempSync('fpai_ownflag_');

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return _root.path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late GroupChatRepository groupRepo;
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
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    HttpOverrides.global = null;
    // Porch Life Afterglow off: the gate says no, so any save that writes
    // the gate instead of the chat's own flag writes false.
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'needs_sim_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
      'nsfw_cooldown_default': false,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
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
          ..testLlmServiceOverride = RefractoryJudges();
    await storage.initialized;
  });

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    await disposeChatThenCloseDb(chat, db);
  });

  Future<bool?> storedFlag(String sessionId) async {
    final row = await db
        .customSelect(
          'SELECT nsfw_cooldown_enabled AS v FROM sessions WHERE id = ?',
          variables: [Variable(sessionId)],
        )
        .getSingleOrNull();
    final v = row?.data['v'];
    return v == null ? null : v == 1 || v == true;
  }

  /// A card that asks for Afterglow seeds the chat's own flag on, even with
  /// Porch Life off (the seed ORs the card with the Porch Life default).
  CharacterCard card(String name, String id, {bool afterglow = true}) =>
      CharacterCard(
        name: name,
        description: 'Exists only inside the own-flag test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(
          nsfwCooldownEnabled: afterglow,
        ),
      )..dbId = id;

  test('a 1:1 save keeps the chat\'s own flag on while Porch Life is '
      'off', () async {
    await chat.setActiveCharacter(card('Mara', 'char-ownflag-mara'));
    expect(
      chat.nsfwService.nsfwCooldownEnabled,
      isFalse,
      reason: 'the live gate follows Porch Life',
    );
    await chat.sendMessage('Evening.');
    await settle();

    expect(
      await storedFlag(chat.currentSessionId!),
      isTrue,
      reason: 'THE BUG: the save wrote the gate, so the chat lost its own on',
    );
  });

  test('a 1:1 save keeps the chat\'s own flag off while Porch Life is '
      'on', () async {
    await chat.setActiveCharacter(
      card('Wren', 'char-ownflag-wren', afterglow: false),
    );
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    expect(
      chat.nsfwService.nsfwCooldownEnabled,
      isTrue,
      reason: 'the live gate follows Porch Life',
    );
    await chat.sendMessage('Evening.');
    await settle();

    expect(
      await storedFlag(chat.currentSessionId!),
      isFalse,
      reason: 'the save wrote the gate, so a chat left off came back on',
    );
  });

  test('forking a 1:1 into a group carries the chat\'s own flag', () async {
    await chat.setActiveCharacter(card('Nia', 'char-ownflag-nia'));
    await chat.sendMessage('Evening.');
    await settle();

    final group = await chat.forkToGroupChat([
      card('Marisol', 'char-ownflag-marisol'),
    ], groupRepo);
    expect(group, isNotNull, reason: 'the conversion itself must succeed');

    expect(
      await storedFlag(chat.currentSessionId!),
      isTrue,
      reason: 'the fork captured the gate for the host, not her own flag',
    );
  });

  test('collapsing a group to a 1:1 carries the group chat\'s own flag when '
      'the survivor has none of her own', () async {
    const groupId = 'grp-ownflag';
    const sid = '1700000000777';

    // The survivor's library character, so the collapse can find her.
    final nia = CharacterCard(
      name: 'Nia',
      description: 'Exists only inside the own-flag test.',
      firstMessage: 'The porch boards creak.',
    );
    final tmpDir = Directory.systemTemp.createTempSync('ownflag_card_');
    final pngPath = '${tmpDir.path}/Nia_1700000000.png';
    await V2CardService().saveCardAsPng(nia, pngPath, null);
    nia.imagePath = pngPath;
    await repo.addCharacter(nia);

    await db.insertGroup(GroupsCompanion.insert(id: groupId, name: 'Pair'));
    // Realism off, so no member carries a flag of her own: the collapse
    // falls back to the group chat's flag, stored on.
    await db.insertSession(
      SessionsCompanion.insert(
        id: sid,
        groupId: const Value(groupId),
        nsfwCooldownEnabled: const Value(true),
      ),
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
    final avatarDir = Directory(
      p.join(storage.groupsDir.path, groupId, 'avatars'),
    );
    await avatarDir.create(recursive: true);
    for (final (id, name, origin) in [
      ('mem-nia', 'Nia', nia.stableGroupId),
      ('mem-rue', 'Rue', null),
    ]) {
      await V2CardService().saveCardAsPng(
        CharacterCard(name: name),
        p.join(avatarDir.path, '$id.png'),
        null,
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: groupId,
          name: name,
          avatarFilename: Value('$id.png'),
          memberState: origin == null
              ? const Value('{}')
              : Value('{"originStableId":"$origin"}'),
        ),
      );
    }

    await chat.setActiveGroup(
      GroupChat(id: groupId, name: 'Pair'),
      groupRepo: groupRepo,
    );
    final rue = chat.groupCharacters.firstWhere((c) => c.name == 'Rue');
    final removed = await chat.removeCharacterFromGroup(rue, groupRepo);
    expect(removed, isTrue);
    expect(chat.isGroupMode, isFalse, reason: 'the pair collapses to a 1:1');

    expect(
      await storedFlag(chat.currentSessionId!),
      isTrue,
      reason: 'the collapse fell back to the gate, not the group chat\'s flag',
    );
  });

  test('branching from a message keeps the chat\'s own flag', () async {
    await chat.setActiveCharacter(card('Ivy', 'char-ownflag-ivy'));
    await chat.sendMessage('Evening.');
    await settle();
    final parent = chat.currentSessionId!;

    await chat.forkFromMessage(chat.messages.length - 1);
    await settle();
    expect(chat.currentSessionId, isNot(parent));

    expect(
      await storedFlag(chat.currentSessionId!),
      isTrue,
      reason: 'the branch walk kept the gate as the chat\'s toggle',
    );
  });
}
