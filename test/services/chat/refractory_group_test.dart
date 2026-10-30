// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group refractory on the clock: a beat ticks every member at once, not only
// the speaker, and each member keeps their own opening afterglow turn. A
// regen replays the beat once for everyone it reached.
//
// Red proofs, each run with the named piece taken out:
//  * the 30-minute beat: the co-present (member entry) branch of
//    `_moveRefractory`, i.e. ticking only the loaded speaker;
//  * regen: the receipt restore in `_revertRegenRealismBaseline`;
//  * clock off: the per-reply tick in `_evaluateRealismForUpcomingSpeaker`.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Refractory;
import '../../helpers/chat_db_teardown.dart';
import '../../helpers/refractory_judges.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_refr_group_').path;
        }
        return null;
      });
}

const _realismOn = '{"realism_engine":{"realism_enabled":true}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late RefractoryJudges llm;
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
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = RefractoryJudges();
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
    await db.insertGroup(GroupsCompanion.insert(id: 'grp-refr', name: 'Porch'));
    for (final (id, name) in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-refr',
          name: name,
          personality: Value('$name keeps the porch.'),
          avatarFilename: Value('refr-${name.toLowerCase()}.png'),
          frontPorchExtensions: const Value(_realismOn),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-refr', name: 'Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
  });

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    await disposeChatThenCloseDb(chat, db);
  });

  CharacterCard member(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);

  Refractory refractoryOf(String name) {
    final state = chat.getRealismStateForGroupCharacter(member(name));
    return state == null ? Refractory.none : Refractory.read(state)!;
  }

  /// [name] answers the user's line (or, with no line, takes the next turn).
  Future<void> speak(
    String name, {
    String? line,
    int minutes = 5,
    bool climax = false,
    int turns = 5,
  }) async {
    llm
      ..minutes = minutes
      ..climax = climax
      ..refractoryTurns = turns;
    chat.setNextCharacter(member(name));
    if (line != null) {
      await chat.sendMessage(line);
    } else {
      await chat.triggerNextCharacter();
    }
    await settle();
    expect(chat.messages.last.sender, name, reason: 'baseline: $name spoke');
  }

  test('one speaks, a 30-minute beat ticks both members in refractory; the '
      'opening turn is the speaker\'s own', () async {
    await speak('Ada', line: 'The wave crests.', climax: true, turns: 5);
    expect(refractoryOf('Ada').minutes, 75);
    await speak('Bea', climax: true, turns: 4);
    expect(refractoryOf('Bea').minutes, 60);
    expect(
      refractoryOf('Ada').minutes,
      70,
      reason: 'Bea\'s 5-minute beat passed for Ada too',
    );
    expect(refractoryOf('Ada').opened, isFalse, reason: 'Ada has not spoken');

    await speak('Ada', line: 'Stay a while.', minutes: 30);
    expect(refractoryOf('Ada').minutes, 40, reason: 'the speaker ticks');
    expect(
      refractoryOf('Bea').minutes,
      30,
      reason: 'and so does everyone else present',
    );
    expect(llm.lastReplyWasOpening, isTrue, reason: 'Ada\'s first since');
    expect(refractoryOf('Ada').opened, isTrue);
    expect(
      refractoryOf('Bea').opened,
      isFalse,
      reason: 'Bea has not spoken since her climax',
    );
  });

  test('regen replays the beat once for every member it reached', () async {
    await speak('Ada', line: 'The wave crests.', climax: true, turns: 5);
    await speak('Bea', climax: true, turns: 4);
    await speak('Ada', line: 'Stay a while.', minutes: 30);
    expect(refractoryOf('Ada').minutes, 40);
    expect(refractoryOf('Bea').minutes, 30);

    llm.minutes = 30;
    await chat.regenerateLastMessage();
    await settle();
    expect(refractoryOf('Ada').minutes, 40);
    expect(
      refractoryOf('Bea').minutes,
      30,
      reason: 'the co-present tick is given back before the replay ticks it',
    );
    expect(refractoryOf('Ada').opened, isTrue);
  });

  // Review (Needs v2): with the clock off a reply is fifteen minutes for
  // the character who spoke, as it was one turn before, so a refractory
  // still ends after the same number of that character's replies as it
  // did. Another member's reply does not spend it.
  test('clock off: a reply is a quarter hour for the one who spoke', () async {
    await chat.setPassageOfTimeEnabled(false);
    await speak('Ada', line: 'The wave crests.', climax: true, turns: 5);
    expect(refractoryOf('Ada').minutes, 75);

    await speak('Bea');
    expect(
      refractoryOf('Ada').minutes,
      75,
      reason: 'Bea\'s reply is Bea\'s turn, not Ada\'s',
    );

    await speak('Ada');
    expect(refractoryOf('Ada').minutes, 60, reason: 'Ada\'s own reply counts');
  });

  // 2026-10-24: a group whose members were saved with Afterglow off kept
  // their stored "off" after Porch Life Afterglow went on; only the removed
  // per-chat toggle could flip it. Porch Life (18+ on) is the one live gate.
  test('members saved with Afterglow off obey Porch Life turned on later, '
      'and 18+ off turns it off again', () async {
    await storage.realismSettings.setNsfwCooldownDefault(false);
    await speak('Ada', line: 'Evening.');
    expect(chat.isGroupNsfwEnabled, isFalse);

    await storage.realismSettings.setNsfwCooldownDefault(true);
    expect(
      chat.isGroupNsfwEnabled,
      isTrue,
      reason: 'the stored per-member "off" must not outvote Porch Life',
    );
    await speak('Bea', line: 'The wave crests.', climax: true, turns: 4);
    expect(refractoryOf('Bea').minutes, 60, reason: 'the climax landed');

    await storage.realismSettings.setAdultThemesEnabled(false);
    expect(chat.isGroupNsfwEnabled, isFalse, reason: 'Afterglow needs 18+');
  });

  // Each member's own Afterglow switch. A beat ages and rewinds body by body,
  // so a member switched off neither stops the rest of the cast's recovery
  // nor gets one back.
  test('a member switched off still lets the beat pass for the rest of the '
      'cast, and deleting their reply gives it back', () async {
    await speak('Ada', line: 'The wave crests.', climax: true, turns: 5);
    expect(refractoryOf('Ada').minutes, 75);
    await chat.setMemberAfterglowEnabled(member('Bea'), false);

    await speak('Bea', minutes: 30);
    expect(
      refractoryOf('Ada').minutes,
      45,
      reason: "Bea's beat passed for Ada",
    );
    expect(refractoryOf('Bea'), Refractory.none);

    await chat.deleteMessage(chat.messages.length - 1);
    await settle();
    expect(refractoryOf('Ada').minutes, 75, reason: 'the beat is given back');
    expect(refractoryOf('Bea'), Refractory.none);
  });

  test('switching off the member the chat holds live settles them there too, '
      'so switching them back on starts from calm', () async {
    await speak('Ada', line: 'Evening.');
    expect(
      chat.nsfwService.loadedMemberId,
      chat.characterIdFor(member('Ada')),
      reason: "baseline: the live scalars are Ada's after her turn",
    );
    chat.nsfwService.setArousalLevel(60);

    await chat.setMemberAfterglowEnabled(member('Ada'), false);
    await chat.setMemberAfterglowEnabled(member('Ada'), true);
    expect(
      chat.nsfwService.arousalLevel,
      0,
      reason: 'what the phone shows for the group when no one is focused',
    );
  });

  test('deleting a reply gives the beat back to the cast, and no recovery to '
      'a member switched off since', () async {
    await speak('Ada', line: 'The wave crests.', climax: true, turns: 5);
    await speak('Bea', climax: true, turns: 4);
    await speak('Ada', line: 'Stay a while.', minutes: 30);
    expect(refractoryOf('Ada').minutes, 40);
    expect(refractoryOf('Bea').minutes, 30);

    await chat.setMemberAfterglowEnabled(member('Bea'), false);
    expect(refractoryOf('Bea'), Refractory.none, reason: 'off settles her');
    // A tail delete puts every body back where the reply's beat found it.
    await chat.deleteMessage(chat.messages.length - 1);
    await settle();
    expect(refractoryOf('Ada').minutes, 70);
    expect(refractoryOf('Bea'), Refractory.none);
  });
}
