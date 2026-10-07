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
    await chat.setNsfwCooldownEnabled(true);
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

  test('clock off: every reply is a quarter hour for every member', () async {
    await chat.setPassageOfTimeEnabled(false);
    await speak('Ada', line: 'The wave crests.', climax: true, turns: 5);
    expect(refractoryOf('Ada').minutes, 75);

    await speak('Bea');
    expect(
      refractoryOf('Ada').minutes,
      60,
      reason: 'Bea\'s reply counts for Ada, who is present but silent',
    );
  });
}
