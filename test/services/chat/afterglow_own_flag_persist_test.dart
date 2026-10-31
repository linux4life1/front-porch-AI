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

// A chat's own Afterglow flag survives its saves, a fork into a group, the
// group's replies, the collapse back to a 1:1 and a branch from a message,
// whatever Porch Life says. #614 made Porch Life Afterglow the live gate and
// said the per-chat flag still rides the save wire. It did not: the 1:1 save,
// the fork's host capture, the collapse fallback and the branch walk read the
// gated getter, the fork put the host's flag only in the chat-level register
// (per-speaker state in a group, so the first reply overwrote it), the group
// branch reset every unstamped member's flag to the seed, and a collapse onto
// a member with no flag of her own handed her the gate (or, read from the
// register, another member's flag).
//
// Since each chat's own switch came back: off hides Lust and recovery and
// keeps them, through a rewind, a receipt, a save and a reopen, and on shows
// them where they were (zeroing them was a bug; off hides, never erases, as
// Pockets does). The stored switch alone decides: a chat stored off opens off
// whatever it holds. A chat package carries the switch, and a fork, a
// collapse, a branch and a package carry the switch and the Lust with it.
//
// Red proofs, one site at a time: put `nsfwCooldownEnabled` back for
// `storedNsfwCooldownEnabled` in the save (chat_service_session_state_save),
// the fork's host capture (chat_service_group_membership) or the 1:1 branch
// walk (chat_service_import_walk); drop the host-member write in
// _carryHostStateIntoForkedGroup; or drop the kept flag in
// _restoreGroupRealismWalkingBack. Each fails its own tests.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/refractory.dart';
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

  /// A group member's own flag, as the session row stores it.
  Future<Object?> memberFlag(String sessionId, String memberName) async {
    final row = await db
        .customSelect(
          'SELECT group_realism_state AS v FROM sessions WHERE id = ?',
          variables: [Variable(sessionId)],
        )
        .getSingle();
    final state = jsonDecode(row.data['v'] as String) as Map<String, dynamic>;
    final perChar = state['perChar'] as Map<String, dynamic>? ?? const {};
    final member = chat.groupCharacters.firstWhere((c) => c.name == memberName);
    final entry = perChar[groupMemberStoreId(member)];
    return entry is Map ? entry['nsfwCooldownEnabled'] : null;
  }

  /// The card's Afterglow switch seeds a new chat's own flag; Porch Life only
  /// decides whether it runs.
  CharacterCard card(
    String name,
    String id, {
    bool afterglow = true,
    bool realism = false,
  }) => CharacterCard(
    name: name,
    description: 'Exists only inside the own-flag test.',
    firstMessage: 'The porch light hums.',
    frontPorchExtensions: FrontPorchExtensions(
      afterglowEnabled: afterglow,
      realismEnabled: realism,
    ),
  )..dbId = id;

  /// [card] in the library, so a collapse can find her again.
  Future<CharacterCard> libraryCard(
    String name, {
    bool afterglow = true,
    bool realism = false,
  }) async {
    final c = card(name, 'unused', afterglow: afterglow, realism: realism)
      ..dbId = null;
    final dir = Directory.systemTemp.createTempSync('ownflag_card_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final png = p.join(dir.path, '${name}_1700000000.png');
    await V2CardService().saveCardAsPng(c, png, null);
    c.imagePath = png;
    await repo.addCharacter(c);
    return c;
  }

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
      isFalse,
      reason: "Porch Life allows it; the chat's own switch is off",
    );
    await chat.sendMessage('Evening.');
    await settle();

    expect(
      await storedFlag(chat.currentSessionId!),
      isFalse,
      reason: 'the save wrote the gate, so a chat left off came back on',
    );
  });

  for (final realism in [false, true]) {
    test('forking a 1:1 into a group puts the chat\'s own flag on the host '
        'member (realism ${realism ? 'on' : 'off'})', () async {
      await chat.setActiveCharacter(
        card('Nia', 'char-ownflag-nia', realism: realism),
      );
      await chat.sendMessage('Evening.');
      await settle();

      final group = await chat.forkToGroupChat([
        card('Marisol', 'char-ownflag-marisol'),
      ], groupRepo);
      expect(group, isNotNull, reason: 'the conversion itself must succeed');

      expect(
        await memberFlag(chat.currentSessionId!, 'Nia'),
        isTrue,
        reason:
            'the fork put the host\'s flag only in the chat-level register, '
            'which the first group reply overwrites',
      );
    });
  }

  test('a flag carried into a group survives a group reply and comes back '
      'with the collapse to a 1:1', () async {
    final nia = await libraryCard('Nia', realism: true);
    await chat.setActiveCharacter(nia);
    await chat.sendMessage('Evening.');
    await settle();

    final group = await chat.forkToGroupChat([
      card('Rue', 'char-ownflag-rue'),
    ], groupRepo);
    expect(group, isNotNull);
    await chat.sendMessage('Evening, both of you.');
    await settle();

    final rue = chat.groupCharacters.firstWhere((c) => c.name == 'Rue');
    expect(await chat.removeCharacterFromGroup(rue, groupRepo), isTrue);
    expect(chat.isGroupMode, isFalse, reason: 'the pair collapses to a 1:1');

    expect(
      await storedFlag(chat.currentSessionId!),
      isTrue,
      reason: 'Nia went into the group with Afterglow on and came out off',
    );
  });

  test("collapsing to a 1:1 keeps the group chat's own Afterglow switch, "
      "never a member's old flag", () async {
    // The group chat took Nia's switch at the fork. Rue never spoke, so she
    // holds no per-member flag, which the old collapse read as off, and her
    // card starts new chats off, which the 1:1 must not take either.
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(card('Nia', 'char-ownflag-nia'));
    await chat.sendMessage('Evening.');
    await settle();
    final rue = await libraryCard('Rue', afterglow: false);
    final group = await chat.forkToGroupChat([rue], groupRepo);
    expect(group, isNotNull);
    expect(chat.afterglowChatSwitch, isTrue, reason: "Nia's switch came along");

    final nia = chat.groupCharacters.firstWhere((c) => c.name == 'Nia');
    expect(await chat.removeCharacterFromGroup(nia, groupRepo), isTrue);
    expect(chat.isGroupMode, isFalse, reason: 'the pair collapses to a 1:1');
    expect(chat.activeCharacter?.name, 'Rue');

    expect(
      await storedFlag(chat.currentSessionId!),
      isTrue,
      reason: 'the 1:1 keeps the switch the group chat showed',
    );
  });

  test("a collapse keeps the survivor's Lust when the group chat's switch is "
      "on, whatever her chat row's old flag says", () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    final nia = await libraryCard('Nia', realism: true);
    await chat.setActiveCharacter(nia);
    await chat.sendMessage('Evening.');
    await settle();
    final rue = await libraryCard('Rue', realism: true);
    final group = await chat.forkToGroupChat([rue], groupRepo);
    expect(group, isNotNull);
    expect(chat.afterglowChatSwitch, isTrue);
    final sid = chat.currentSessionId!;
    final rueId = groupMemberStoreId(
      chat.groupCharacters.firstWhere((c) => c.name == 'Rue'),
    );
    // Leaving a chat saves it, so it is edited from another character's (a
    // second group chat would stop the collapse): Rue is partway up, and the
    // row's legacy flag (a member's, never the group chat's switch) says off.
    await chat.setActiveCharacter(card('Ivo', 'char-ownflag-ivo'));
    final row = await db
        .customSelect(
          'SELECT group_realism_state AS v FROM sessions WHERE id = ?',
          variables: [Variable(sid)],
        )
        .getSingle();
    final state = jsonDecode(row.data['v'] as String) as Map<String, dynamic>;
    final perChar = state['perChar'] as Map<String, dynamic>;
    perChar[rueId] = {
      ...?(perChar[rueId] as Map<String, dynamic>?),
      'arousal': 30,
    };
    await db.customUpdate(
      'UPDATE sessions SET group_realism_state = ?, '
      'nsfw_cooldown_enabled = 0 WHERE id = ?',
      variables: [Variable(jsonEncode(state)), Variable(sid)],
    );
    await chat.setActiveGroup(group!, groupRepo: groupRepo);
    expect(chat.currentSessionId, sid);

    final niaMember = chat.groupCharacters.firstWhere((c) => c.name == 'Nia');
    expect(await chat.removeCharacterFromGroup(niaMember, groupRepo), isTrue);
    expect(chat.isGroupMode, isFalse, reason: 'the pair collapses to a 1:1');
    expect(chat.afterglowChatSwitch, isTrue);
    expect(chat.nsfwService.arousalLevel, 30, reason: "Rue's Lust came along");
  });

  test("a collapse from a group chat switched off keeps the survivor's Lust "
      'and leaves the 1:1 off', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    final nia = await libraryCard('Nia', realism: true);
    await chat.setActiveCharacter(nia);
    await chat.sendMessage('Evening.');
    await settle();
    final rue = await libraryCard('Rue', realism: true);
    final group = await chat.forkToGroupChat([rue], groupRepo);
    expect(group, isNotNull);
    final sid = chat.currentSessionId!;
    final rueId = groupMemberStoreId(
      chat.groupCharacters.firstWhere((c) => c.name == 'Rue'),
    );
    // Rue is partway up, edited from another character's chat as above.
    await chat.setActiveCharacter(card('Ivo', 'char-ownflag-ivo'));
    final row = await db
        .customSelect(
          'SELECT group_realism_state AS v FROM sessions WHERE id = ?',
          variables: [Variable(sid)],
        )
        .getSingle();
    final state = jsonDecode(row.data['v'] as String) as Map<String, dynamic>;
    final perChar = state['perChar'] as Map<String, dynamic>;
    perChar[rueId] = {
      ...?(perChar[rueId] as Map<String, dynamic>?),
      'arousal': 30,
    };
    // The row's own column is a stale 1:1 value the collapse must overwrite.
    await db.customUpdate(
      'UPDATE sessions SET group_realism_state = ?, arousal_level = 5 '
      'WHERE id = ?',
      variables: [Variable(jsonEncode(state)), Variable(sid)],
    );
    await chat.setActiveGroup(group!, groupRepo: groupRepo);
    expect(chat.currentSessionId, sid);
    await chat.setAfterglowEnabled(false);

    final niaMember = chat.groupCharacters.firstWhere((c) => c.name == 'Nia');
    expect(await chat.removeCharacterFromGroup(niaMember, groupRepo), isTrue);
    expect(chat.isGroupMode, isFalse, reason: 'the pair collapses to a 1:1');
    expect(chat.afterglowChatSwitch, isFalse, reason: 'the group chat was off');
    expect(chat.nsfwService.arousalLevel, 30, reason: "Rue's kept Lust came");
  });

  test('forking a 1:1 that runs Afterglow keeps it running for the host, '
      'whatever their card starts new chats with', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      card('Nia', 'char-ownflag-nia', afterglow: false, realism: true),
    );
    expect(chat.afterglowChatSwitch, isFalse, reason: 'the card starts it off');
    await chat.setAfterglowEnabled(true);
    await chat.sendMessage('Evening.');
    await settle();
    chat.nsfwService.setArousalLevel(60);

    final group = await chat.forkToGroupChat([
      card('Rue', 'char-ownflag-rue', realism: true),
    ], groupRepo);
    expect(group, isNotNull);
    final nia = chat.groupCharacters.firstWhere((c) => c.name == 'Nia');
    expect(chat.afterglowRunsFor(nia), isTrue);
    expect(chat.getArousalForGroupCharacter(nia), 60, reason: 'her Lust came');
  });

  test('collapsing to the 1:1 of a member switched off in the group leaves '
      'its Afterglow off', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(card('Nia', 'char-ownflag-nia'));
    await chat.sendMessage('Evening.');
    await settle();
    final rue = await libraryCard('Rue');
    final group = await chat.forkToGroupChat([rue], groupRepo);
    expect(group, isNotNull);
    await chat.setMemberAfterglowEnabled(
      chat.groupCharacters.firstWhere((c) => c.name == 'Rue'),
      false,
    );

    final nia = chat.groupCharacters.firstWhere((c) => c.name == 'Nia');
    expect(await chat.removeCharacterFromGroup(nia, groupRepo), isTrue);
    expect(chat.isGroupMode, isFalse, reason: 'the pair collapses to a 1:1');
    expect(chat.activeCharacter?.name, 'Rue');
    expect(
      await storedFlag(chat.currentSessionId!),
      isFalse,
      reason: 'Afterglow was not running for Rue in the group',
    );
  });

  test('branching a 1:1 from a message keeps the chat\'s own flag', () async {
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

  test('branching a chat switched off copies the Lust its message recorded, '
      'still off', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      card('Ivy', 'char-ownflag-ivy', realism: true),
    );
    chat.nsfwService.setArousalLevel(20);
    await chat.sendMessage('Evening.');
    await settle();
    final at = chat.messages.length - 1;
    chat.nsfwService.setArousalLevel(35);
    await chat.sendMessage('Still up?');
    await settle();
    await chat.setAfterglowEnabled(false);
    final parent = chat.currentSessionId!;

    // A branch is a copy of the chat at that reply, not a rewind of this
    // one: it takes the reply's stamp even with the switch off.
    await chat.forkFromMessage(at);
    await settle();
    expect(chat.currentSessionId, isNot(parent));
    expect(chat.afterglowChatSwitch, isFalse);
    expect(chat.nsfwService.arousalLevel, 20, reason: "the reply's own Lust");
  });

  test('branching a group from a message keeps each member\'s own '
      'flag', () async {
    await chat.setActiveCharacter(card('Juno', 'char-ownflag-juno'));
    await chat.sendMessage('Evening.');
    await settle();
    final group = await chat.forkToGroupChat([
      card('Sol', 'char-ownflag-sol'),
    ], groupRepo);
    expect(group, isNotNull);
    final parent = chat.currentSessionId!;
    expect(await memberFlag(parent, 'Juno'), isTrue);

    // Realism is off, so no reply carries a realism stamp: the walk resets
    // every member to the group's seed.
    await chat.forkFromMessage(chat.messages.length - 1);
    await settle();
    expect(chat.currentSessionId, isNot(parent));

    expect(
      await memberFlag(chat.currentSessionId!, 'Juno'),
      isTrue,
      reason: 'the group walk reset the member\'s flag along with her scalars',
    );
  });

  // The trap: the open used to read "stored off but holding Lust or a
  // recovery" as the October overwrite and switch the chat back on. Off now
  // keeps both, so that is exactly a chat the user switched off.
  test('a 1:1 chat stored off opens off whatever Lust, recovery or warmth '
      'tail it holds, and keeps them', () async {
    await chat.setActiveCharacter(card('Mara', 'char-ownflag-mara'));
    await chat.sendMessage('Evening.');
    await settle();
    final sid = chat.currentSessionId!;
    for (final (held, setting) in [
      ('Lust', 'arousal_level = 40'),
      ('aversion', 'arousal_level = -20'),
      ('a recovery', 'refractory_minutes_remaining = 30'),
      ('an old recovery in turns', 'cooldown_turns_remaining = 2'),
      ('a warmth tail', 'refractory_tail_minutes = 20'),
      ('nothing', 'arousal_level = 0'),
    ]) {
      // Leaving a chat saves it, so it is edited from the next one.
      await chat.startNewChat();
      await db.customUpdate(
        'UPDATE sessions SET nsfw_cooldown_enabled = 0, arousal_level = 0, '
        'refractory_minutes_remaining = NULL, cooldown_turns_remaining = 0, '
        'refractory_tail_minutes = NULL, $setting WHERE id = ?',
        variables: [Variable(sid)],
      );
      await chat.loadSession(sid);
      expect(chat.afterglowChatSwitch, isFalse, reason: held);
    }
    await chat.startNewChat();
    await db.customUpdate(
      'UPDATE sessions SET nsfw_cooldown_enabled = 0, arousal_level = 40, '
      'refractory_minutes_remaining = 30, refractory_minutes_total = 30, '
      'refractory_tail_minutes = NULL WHERE id = ?',
      variables: [Variable(sid)],
    );
    await chat.loadSession(sid);
    expect(chat.afterglowChatSwitch, isFalse);
    expect(chat.nsfwService.arousalLevel, 40, reason: 'off keeps it');
    expect(chat.nsfwService.refractory.minutes, 30, reason: 'and the recovery');
    // Its next save keeps it off too.
    await chat.startNewChat();
    expect(await storedFlag(sid), isFalse);
  });

  test('a chat switched off keeps its Lust through a regenerate, a save and '
      'a reopen', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      card('Lena', 'char-ownflag-lena', realism: true),
    );
    chat.nsfwService.setArousalLevel(40);
    await chat.sendMessage('Evening.');
    await settle();
    await chat.sendMessage('Still up?');
    await settle();
    final sid = chat.currentSessionId!;
    expect(chat.nsfwService.arousalLevel, 40, reason: 'the stamps hold Lust');

    await chat.setAfterglowEnabled(false);
    expect(
      chat.nsfwService.arousalLevel,
      40,
      reason: 'off hides, never erases',
    );
    await chat.regenerateLastMessage();
    await settle();
    expect(chat.nsfwService.arousalLevel, 40);

    await chat.startNewChat();
    await chat.loadSession(sid);
    expect(chat.afterglowChatSwitch, isFalse);
    expect(chat.nsfwService.arousalLevel, 40);
  });

  // Stamps record the real Lust while a chat is off, so a rewind after it is
  // switched back on puts back what the chat kept, never a zero.
  test('a regenerate and a swipe of replies written while a chat was off put '
      'back the Lust it kept', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      card('Ines', 'char-ownflag-ines', realism: true),
    );
    await chat.sendMessage('Evening.');
    await settle();
    chat.nsfwService.setArousalLevel(40);
    await chat.setAfterglowEnabled(false);
    await chat.sendMessage('Still up?');
    await settle();
    await chat.sendMessage('Stay a while.');
    await settle();
    final last = chat.messages.length - 1;
    // A second swipe of the last reply, written while off.
    await chat.regenerateLastMessage();
    await settle();
    expect(chat.messages[last].swipes.length, 2);

    await chat.setAfterglowEnabled(true);
    expect(chat.nsfwService.arousalLevel, 40);
    // The regenerate rewinds to the reply before, also written while off.
    await chat.regenerateLastMessage();
    await settle();
    expect(
      chat.nsfwService.arousalLevel,
      40,
      reason: 'the stamp of a reply written while off records the kept Lust',
    );
    chat.nsfwService.setArousalLevel(70);
    await chat.swipeMessage(last, -1);
    await settle();
    expect(chat.messages[last].swipeIndex, 1);
    expect(
      chat.nsfwService.arousalLevel,
      40,
      reason: 'the swipe written while off puts back the Lust it kept',
    );
  });

  test('a regenerate in a chat switched off leaves its recovery where the '
      'switch found it, stamps it, saves it, and the chat opens off', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    final judges = RefractoryJudges()..climax = true;
    chat.testLlmServiceOverride = judges;
    await chat.setActiveCharacter(
      card('Odile', 'char-ownflag-odile', realism: true),
    );
    await chat.sendMessage('Evening.');
    await settle();
    expect(chat.nsfwService.refractory.running, isTrue, reason: 'a climax');
    judges.climax = false;
    await chat.sendMessage('Still with me?');
    await settle();
    final sid = chat.currentSessionId!;

    await chat.setAfterglowEnabled(false);
    final kept = chat.nsfwService.refractory;
    expect(kept.running, isTrue, reason: 'off hides the recovery, keeps it');
    await chat.regenerateLastMessage();
    await settle();
    expect(
      chat.nsfwService.refractory,
      kept,
      reason: "neither the receipt nor the clock moves a body that is off",
    );
    final stamp = Map<String, dynamic>.from(
      chat.messages.last.activeMetadata?['realism_state'] as Map,
    );
    expect(Refractory.read(stamp)?.minutes, kept.minutes);
    final row = await db
        .customSelect(
          'SELECT refractory_minutes_remaining AS m FROM sessions WHERE id = ?',
          variables: [Variable(sid)],
        )
        .getSingle();
    expect(row.data['m'], kept.minutes, reason: 'an off chat saves its own');

    await chat.startNewChat();
    await chat.loadSession(sid);
    expect(
      chat.afterglowChatSwitch,
      isFalse,
      reason: 'switched off, stays off',
    );
    expect(chat.nsfwService.refractory.minutes, kept.minutes);
  });

  test('a 1:1 chat switched off and back on keeps its Lust and recovery, '
      'saved, and still there when the chat is opened again', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      card('Rhea', 'char-ownflag-rhea', realism: true),
    );
    await chat.sendMessage('Evening.');
    await settle();
    final sid = chat.currentSessionId!;
    chat.nsfwService.setArousalLevel(-12);
    chat.nsfwService.setRefractory(const Refractory(minutes: 75, total: 75));
    await chat.setAfterglowEnabled(false);
    expect(chat.nsfwService.nsfwCooldownEnabled, isFalse, reason: 'hidden');

    await chat.startNewChat(); // leaving the chat saves it
    final row = await db
        .customSelect(
          'SELECT arousal_level AS a, refractory_minutes_remaining AS m '
          'FROM sessions WHERE id = ?',
          variables: [Variable(sid)],
        )
        .getSingle();
    expect(row.data['a'], -12, reason: 'the save wrote 0 for an off chat');
    expect(row.data['m'], 75);
    await chat.loadSession(sid);
    expect(
      chat.afterglowChatSwitch,
      isFalse,
      reason: 'switched off, stays off',
    );
    await chat.setAfterglowEnabled(true);
    expect(chat.nsfwService.arousalLevel, -12);
    expect(chat.nsfwService.refractory.minutes, 75);
  });

  test('deleting a reply while a chat is off leaves its recovery where the '
      'switch found it', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    final judges = RefractoryJudges()..climax = true;
    chat.testLlmServiceOverride = judges;
    await chat.setActiveCharacter(
      card('Vale', 'char-ownflag-vale', realism: true),
    );
    await chat.sendMessage('Evening.');
    await settle();
    expect(chat.nsfwService.refractory.running, isTrue, reason: 'a climax');
    judges.climax = false;
    await chat.sendMessage('Still with me?');
    await settle();

    await chat.setAfterglowEnabled(false);
    final kept = chat.nsfwService.refractory;
    // A tail delete replays the reply's beat receipt.
    await chat.deleteMessage(chat.messages.length - 1);
    await settle();
    expect(chat.nsfwService.refractory, kept);
  });

  test('a chat that is off records no beat receipts, so a regenerate after '
      'it is switched back on brings no recovery', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      card('Una', 'char-ownflag-una', realism: true),
    );
    await chat.sendMessage('Evening.');
    await settle();
    await chat.setAfterglowEnabled(false);
    // What a receipt could put back while the chat is off.
    chat.nsfwService.setRefractory(
      const Refractory(minutes: 75, total: 75, opened: true),
    );
    await chat.sendMessage('Still up?');
    await settle();

    await chat.setAfterglowEnabled(true);
    await chat.regenerateLastMessage();
    await settle();
    expect(chat.nsfwService.refractory.running, isFalse);
  });

  test("'Score again' while a chat is off leaves its Lust alone", () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      card('Tove', 'char-ownflag-tove', realism: true),
    );
    await chat.sendMessage('Evening.');
    await settle();
    final i = chat.messages.length - 1;
    // The reply moved Lust by +12 when it was first scored.
    chat.messages[i].activeMetadata = {
      ...?chat.messages[i].activeMetadata,
      'arousal_delta': 12,
    };
    await chat.setAfterglowEnabled(false);

    expect(await chat.reprocessFeelings(i), isNot(FeelingsRescore.refused));
    await settle();
    expect(chat.nsfwService.arousalLevel, 0, reason: 'not 0 - 12 + 0');
  });

  test('switching a chat back on shows its Lust and recovery where they '
      'were', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      card('Pia', 'char-ownflag-pia', realism: true),
    );
    await chat.sendMessage('Evening.');
    await settle();
    chat.nsfwService.setArousalLevel(25);
    chat.nsfwService.setRefractory(const Refractory(minutes: 30, total: 30));
    await chat.setAfterglowEnabled(false);

    await chat.setAfterglowEnabled(true);
    expect(chat.nsfwService.arousalLevel, 25);
    expect(chat.nsfwService.refractory.minutes, 30);
  });

  test('switching on a chat that is already on leaves its Lust alone, as the '
      'phone can send its switch again', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      card('Quin', 'char-ownflag-quin', realism: true),
    );
    await chat.sendMessage('Evening.');
    await settle();
    chat.nsfwService.setArousalLevel(25);

    await chat.setAfterglowEnabled(true);
    expect(chat.nsfwService.arousalLevel, 25);
  });

  for (final group in [false, true]) {
    test("a chat package carries the chat's own Afterglow switch "
        "(${group ? 'group' : '1:1'})", () async {
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      final tess = await libraryCard('Tess', realism: true);
      await chat.setActiveCharacter(tess);
      await chat.sendMessage('Evening.');
      await settle();
      if (group) {
        final g = await chat.forkToGroupChat([
          await libraryCard('Uma', realism: true),
        ], groupRepo);
        expect(g, isNotNull);
      }
      await chat.setAfterglowEnabled(false);
      final zip = await chat.exportToFpchat();
      expect(zip, isNotNull);

      await chat.startNewChat();
      expect(chat.afterglowChatSwitch, isTrue, reason: 'a new chat starts on');
      final result = await chat.importChatPackage(zip!);
      expect(result.fullRestore, isTrue);
      expect(
        chat.afterglowChatSwitch,
        isFalse,
        reason: 'the package came from a chat switched off',
      );
    });
  }

  for (final group in [false, true]) {
    test("a chat package from a chat switched off carries the Lust it kept "
        "(${group ? 'group' : '1:1'})", () async {
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      final tess = await libraryCard('Tess', realism: true);
      await chat.setActiveCharacter(tess);
      await chat.sendMessage('Evening.');
      await settle();
      chat.nsfwService.setArousalLevel(25);
      await chat.sendMessage('Still up?');
      await settle();
      if (group) {
        final g = await chat.forkToGroupChat([
          await libraryCard('Uma', realism: true),
        ], groupRepo);
        expect(g, isNotNull);
      }
      int lust() => group
          ? chat.getArousalForGroupCharacter(
              chat.groupCharacters.firstWhere((c) => c.name == 'Tess'),
            )
          : chat.nsfwService.arousalLevel;
      expect(lust(), 25);
      await chat.setAfterglowEnabled(false);
      final zip = await chat.exportToFpchat();
      expect(zip, isNotNull);

      await chat.startNewChat();
      final result = await chat.importChatPackage(zip!);
      expect(result.fullRestore, isTrue);
      expect(chat.afterglowChatSwitch, isFalse);
      expect(lust(), 25, reason: 'the package carried what the chat kept');
    });
  }

  group("a group chat's own Afterglow switch, while Porch Life allows it", () {
    setUp(() async {
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
    });

    Future<Map<String, dynamic>> groupState(String sessionId) async {
      final row = await db
          .customSelect(
            'SELECT group_realism_state AS v FROM sessions WHERE id = ?',
            variables: [Variable(sessionId)],
          )
          .getSingle();
      return jsonDecode(row.data['v'] as String) as Map<String, dynamic>;
    }

    /// Nia's 1:1, with her card's Afterglow switch, forked into a group.
    Future<void> intoGroup({bool afterglow = true}) async {
      await chat.setActiveCharacter(
        card('Nia', 'char-gsw-nia', afterglow: afterglow, realism: true),
      );
      await chat.sendMessage('Evening.');
      await settle();
      final group = await chat.forkToGroupChat([
        card('Rue', 'char-gsw-rue', realism: true),
      ], groupRepo);
      expect(group, isNotNull, reason: 'the conversion itself must succeed');
    }

    test('it gates Afterglow, saves, and comes back with the chat', () async {
      await intoGroup();
      final sid = chat.currentSessionId!;
      expect(chat.nsfwService.nsfwCooldownEnabled, isTrue);

      await chat.setAfterglowEnabled(false);
      expect(
        chat.nsfwService.nsfwCooldownEnabled,
        isFalse,
        reason: "the gate reads the group chat's own switch",
      );
      expect((await groupState(sid))[kGroupAfterglowKey], isFalse);

      await chat.startNewChat();
      expect(chat.afterglowChatSwitch, isTrue, reason: 'a new chat starts on');
      await chat.loadSession(sid);
      expect(
        chat.afterglowChatSwitch,
        isFalse,
        reason: 'the switch came back with its chat',
      );
      expect(chat.nsfwService.nsfwCooldownEnabled, isFalse);
    });

    test("new chats start it as the group says, read when each "
        "starts", () async {
      // Nia's 1:1 had it off, so the group made from it starts chats off.
      await intoGroup(afterglow: false);
      expect(chat.afterglowChatSwitch, isFalse, reason: "Nia's switch came");
      expect(
        groupAfterglowIn(chat.activeGroup!.defaultMemberRealismState),
        isFalse,
      );

      await chat.startNewChat();
      expect(chat.afterglowChatSwitch, isFalse, reason: "the group's setting");

      final g = chat.activeGroup!;
      g.defaultMemberRealismState = withGroupAfterglow(
        g.defaultMemberRealismState,
        true,
      );
      await groupRepo.save(g);
      await chat.startNewChat();
      expect(chat.afterglowChatSwitch, isTrue, reason: "the group's new one");
    });

    test('forking a 1:1 chat that is switched off carries its kept Lust into '
        'the group, still off', () async {
      await chat.setActiveCharacter(card('Nia', 'char-gsw-nia', realism: true));
      await chat.sendMessage('Evening.');
      await settle();
      chat.nsfwService.setArousalLevel(25);
      await chat.setAfterglowEnabled(false);
      final g = await chat.forkToGroupChat([
        card('Rue', 'char-gsw-rue', realism: true),
      ], groupRepo);
      expect(g, isNotNull);
      expect(chat.afterglowChatSwitch, isFalse);
      final nia = groupMemberStoreId(
        chat.groupCharacters.firstWhere((c) => c.name == 'Nia'),
      );
      final perChar =
          (await groupState(chat.currentSessionId!))['perChar']
              as Map<String, dynamic>;
      expect((perChar[nia] as Map?)?['arousal'], 25);
    });

    test("a member's own switch: off, Afterglow stops for them alone, their "
        'Lust is kept, the rest are untouched, and the switch stays on their '
        'row', () async {
      await intoGroup();
      final sid = chat.currentSessionId!;
      final group = chat.activeGroup!;
      final rueId = groupMemberStoreId(
        chat.groupCharacters.firstWhere((c) => c.name == 'Rue'),
      );
      final niaId = groupMemberStoreId(
        chat.groupCharacters.firstWhere((c) => c.name == 'Nia'),
      );
      // Rue is partway up in the saved chat, edited from another character's.
      await chat.setActiveCharacter(card('Ivo', 'char-gsw-ivo'));
      final state = await groupState(sid);
      final perChar = state['perChar'] as Map<String, dynamic>;
      perChar[rueId] = {
        ...?(perChar[rueId] as Map<String, dynamic>?),
        'arousal': 40,
        'refractoryMinutesRemaining': 45,
        'refractoryMinutesTotal': 45,
      };
      perChar[niaId] = {
        ...?(perChar[niaId] as Map<String, dynamic>?),
        'arousal': 15,
      };
      await db.customUpdate(
        'UPDATE sessions SET group_realism_state = ? WHERE id = ?',
        variables: [Variable(jsonEncode(state)), Variable(sid)],
      );
      await chat.setActiveGroup(group, groupRepo: groupRepo);
      final rue = chat.groupCharacters.firstWhere((c) => c.name == 'Rue');
      final nia = chat.groupCharacters.firstWhere((c) => c.name == 'Nia');
      expect(chat.getArousalForGroupCharacter(rue), 40);
      expect(chat.afterglowRunsFor(rue), isTrue);

      await chat.setMemberAfterglowEnabled(rue, false);
      expect(chat.afterglowRunsFor(rue), isFalse);
      expect(chat.afterglowRunsFor(nia), isTrue, reason: 'the rest keep it');
      expect(chat.getArousalForGroupCharacter(rue), 40, reason: 'kept');
      expect(
        Refractory.read(chat.getRealismStateForGroupCharacter(rue)!)?.minutes,
        45,
        reason: 'her recovery is kept',
      );
      expect(
        chat.getRefractoryForGroupCharacter(rue).minutes,
        0,
        reason: 'and hidden',
      );
      expect(chat.getArousalForGroupCharacter(nia), 15, reason: 'untouched');
      await chat.setMemberAfterglowEnabled(rue, true);
      expect(chat.getArousalForGroupCharacter(rue), 40, reason: 'back as was');
      expect(chat.getRefractoryForGroupCharacter(rue).minutes, 45);
      expect(chat.getArousalForGroupCharacter(nia), 15);
      await chat.setMemberAfterglowEnabled(rue, false);
      final row = await db
          .customSelect(
            'SELECT front_porch_extensions AS e FROM group_members '
            'WHERE id = ?',
            variables: [Variable(rue.dbId!)],
          )
          .getSingle();
      final ext = FrontPorchExtensions.fromJson(
        jsonDecode(row.data['e'] as String) as Map<String, dynamic>,
      );
      expect(ext.afterglowEnabled, isFalse, reason: "kept on Rue's own row");
    });

    // A branch is a copy of the chat at that reply, not a rewind: with the
    // group chat's switch off it still takes the reply's stamped Lust, as
    // the 1:1 branch does.
    test('branching a group chat switched off from an earlier reply copies '
        "the Lust that reply's speaker had there", () async {
      await intoGroup();
      final rueId = groupMemberStoreId(
        chat.groupCharacters.firstWhere((c) => c.name == 'Rue'),
      );
      chat.debugSeedGroupSpeakerState(rueId, arousal: 20);
      await chat.sendMessage('@Rue Evening.');
      await settle();
      expect(chat.messages.last.sender, 'Rue');
      final at = chat.messages.length - 1;
      chat.debugSeedGroupSpeakerState(rueId, arousal: 35);
      await chat.sendMessage('@Rue Still up?');
      await settle();
      expect(chat.messages.last.sender, 'Rue');
      await chat.setAfterglowEnabled(false);
      final parent = chat.currentSessionId!;

      await chat.forkFromMessage(at);
      await settle();
      expect(chat.currentSessionId, isNot(parent));
      expect(chat.isGroupMode, isTrue);
      final rue = chat.groupCharacters.firstWhere((c) => c.name == 'Rue');
      expect(
        chat.getArousalForGroupCharacter(rue),
        20,
        reason: "the branch point's stamp, not the parent's live 35",
      );
    });

    test('a member switched off takes no climax; the rest of the cast still '
        'do', () async {
      await intoGroup();
      final judges = RefractoryJudges()..climax = true;
      chat.testLlmServiceOverride = judges;
      final rue = chat.groupCharacters.firstWhere((c) => c.name == 'Rue');
      await chat.setMemberAfterglowEnabled(rue, false);

      await chat.sendMessage('@Rue Evening.');
      await settle();
      expect(chat.messages.last.sender, 'Rue');
      expect(chat.messages.last.activeMetadata?['climax_triggered'], isNull);

      await chat.sendMessage('@Nia And you?');
      await settle();
      expect(chat.messages.last.sender, 'Nia');
      expect(chat.messages.last.activeMetadata?['climax_triggered'], isTrue);
    });

    test("switching it off and on keeps every member's Lust, saved and "
        'live', () async {
      await intoGroup();
      final sid = chat.currentSessionId!;
      final rue = groupMemberStoreId(
        chat.groupCharacters.firstWhere((c) => c.name == 'Rue'),
      );
      // Leaving a chat saves it, so it is edited from the group's next one.
      await chat.startNewChat();
      // Rue is partway up in the saved chat.
      final state = await groupState(sid);
      final perChar = state['perChar'] as Map<String, dynamic>;
      final nia = groupMemberStoreId(
        chat.groupCharacters.firstWhere((c) => c.name == 'Nia'),
      );
      perChar[rue] = {
        ...?(perChar[rue] as Map<String, dynamic>?),
        'arousal': 60,
      };
      perChar[nia] = {
        ...?(perChar[nia] as Map<String, dynamic>?),
        'arousal': 20,
      };
      await db.customUpdate(
        'UPDATE sessions SET group_realism_state = ? WHERE id = ?',
        variables: [Variable(jsonEncode(state)), Variable(sid)],
      );
      await chat.loadSession(sid);

      await chat.setAfterglowEnabled(false);
      final saved = (await groupState(sid))['perChar'] as Map<String, dynamic>;
      expect((saved[rue] as Map)['arousal'], 60);
      expect((saved[nia] as Map)['arousal'], 20);
      await chat.setAfterglowEnabled(true);
      CharacterCard member(String name) =>
          chat.groupCharacters.firstWhere((c) => c.name == name);
      expect(chat.getArousalForGroupCharacter(member('Rue')), 60);
      expect(chat.getArousalForGroupCharacter(member('Nia')), 20);
    });
  });
}
