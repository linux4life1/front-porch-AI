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
// Since each chat's own switch came back: a 1:1 chat the October save left
// off while it held Lust is repaired when it opens; a chat switched off stays
// off and settled through a rewind or a receipt, and starts from calm when
// switched back on; a chat package carries the switch; and a fork and a
// collapse carry the switch and the Lust that goes with it.
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

  test('a 1:1 chat stored off that holds Lust, a recovery or a warmth tail '
      'opens on, keeping it; one with none stays off', () async {
    await chat.setActiveCharacter(card('Mara', 'char-ownflag-mara'));
    await chat.sendMessage('Evening.');
    await settle();
    final sid = chat.currentSessionId!;
    // v1.6.1 saved Porch Life's off over a chat's own on and left what it
    // held. A chat switched off holds nothing, so "nothing" stays off.
    for (final (held, setting, on) in [
      ('Lust', 'arousal_level = 40', true),
      ('aversion', 'arousal_level = -20', true),
      ('a recovery', 'refractory_minutes_remaining = 30', true),
      ('an old recovery in turns', 'cooldown_turns_remaining = 2', true),
      ('a warmth tail', 'refractory_tail_minutes = 20', true),
      ('nothing', 'arousal_level = 0', false),
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
      expect(chat.afterglowChatSwitch, on, reason: held);
    }
    await chat.startNewChat();
    await db.customUpdate(
      'UPDATE sessions SET nsfw_cooldown_enabled = 0, arousal_level = 40, '
      'refractory_minutes_remaining = NULL, refractory_tail_minutes = NULL '
      'WHERE id = ?',
      variables: [Variable(sid)],
    );
    await chat.loadSession(sid);
    expect(chat.nsfwService.arousalLevel, 40, reason: 'the repair keeps it');
  });

  test('a chat switched off stays settled: a rewind does not bring a '
      "stamp's Lust back", () async {
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
    expect(chat.nsfwService.arousalLevel, 0);
    await chat.regenerateLastMessage();
    await settle();
    expect(
      chat.nsfwService.arousalLevel,
      0,
      reason: "the regen's rewind reloaded the earlier stamp's Lust",
    );

    await chat.startNewChat();
    await chat.loadSession(sid);
    expect(chat.afterglowChatSwitch, isFalse);
    expect(chat.nsfwService.arousalLevel, 0);
  });

  test("a chat switched off stays off when a regenerate's receipt brings a "
      'recovery back: it is not saved, and the chat opens off', () async {
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
    await chat.regenerateLastMessage();
    await settle();
    final row = await db
        .customSelect(
          'SELECT arousal_level AS a, refractory_minutes_remaining AS m, '
          'refractory_tail_minutes AS t FROM sessions WHERE id = ?',
          variables: [Variable(sid)],
        )
        .getSingle();
    expect(row.data['a'], 0);
    expect(row.data['m'] ?? 0, 0, reason: 'no recovery saved in an off chat');
    expect(row.data['t'], isNull);

    await chat.startNewChat();
    await chat.loadSession(sid);
    expect(
      chat.afterglowChatSwitch,
      isFalse,
      reason: 'switched off, stays off',
    );
  });

  test('saving a 1:1 chat that is switched off writes no Lust or recovery, '
      'whatever a re-score left in memory, so it opens off', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      card('Rhea', 'char-ownflag-rhea', realism: true),
    );
    await chat.sendMessage('Evening.');
    await settle();
    final sid = chat.currentSessionId!;
    await chat.setAfterglowEnabled(false);
    // What "Score again" can leave behind in a chat that is off.
    chat.nsfwService.setArousalLevel(-12);
    chat.nsfwService.setRefractory(const Refractory(minutes: 75, total: 75));

    await chat.startNewChat(); // leaving the chat saves it
    final row = await db
        .customSelect(
          'SELECT arousal_level AS a, refractory_minutes_remaining AS m '
          'FROM sessions WHERE id = ?',
          variables: [Variable(sid)],
        )
        .getSingle();
    expect(row.data['a'], 0);
    expect(row.data['m'] ?? 0, 0);
    await chat.loadSession(sid);
    expect(
      chat.afterglowChatSwitch,
      isFalse,
      reason: 'switched off, stays off',
    );
  });

  test('switching a chat back on starts it from calm, whatever was left in '
      'it while it was off', () async {
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      card('Pia', 'char-ownflag-pia', realism: true),
    );
    await chat.sendMessage('Evening.');
    await settle();
    await chat.setAfterglowEnabled(false);
    // A re-score or a receipt can leave Lust or a recovery in memory.
    chat.nsfwService.setArousalLevel(25);
    chat.nsfwService.setRefractory(const Refractory(minutes: 30, total: 30));

    await chat.setAfterglowEnabled(true);
    expect(chat.nsfwService.arousalLevel, 0);
    expect(chat.nsfwService.refractory.running, isFalse);
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

    test('forking a 1:1 chat that is switched off carries no Lust into the '
        'group', () async {
      await chat.setActiveCharacter(card('Nia', 'char-gsw-nia', realism: true));
      await chat.sendMessage('Evening.');
      await settle();
      await chat.setAfterglowEnabled(false);
      // Whatever a re-score or a receipt left in memory while it was off.
      chat.nsfwService.setArousalLevel(25);
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
      expect((perChar[nia] as Map?)?['arousal'] ?? 0, 0);
    });

    test("switching it off settles every member's Lust", () async {
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
      perChar[rue] = {
        ...?(perChar[rue] as Map<String, dynamic>?),
        'arousal': 60,
      };
      await db.customUpdate(
        'UPDATE sessions SET group_realism_state = ? WHERE id = ?',
        variables: [Variable(jsonEncode(state)), Variable(sid)],
      );
      await chat.loadSession(sid);

      await chat.setAfterglowEnabled(false);
      final saved = (await groupState(sid))['perChar'] as Map<String, dynamic>;
      expect((saved[rue] as Map)['arousal'], 0);
    });
  });
}
