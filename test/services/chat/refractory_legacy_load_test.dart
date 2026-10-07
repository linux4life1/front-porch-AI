// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chats saved before the refractory counted minutes load their turns once as
// turns × 15: a 1:1 session row that has only the old cooldown_turns_*
// columns (the v55 ladder step adds the minute columns as NULL), and a group
// member whose JSON has only the old keys. A reply that had already ticked
// the old count (remaining below total) had already spoken the opening turn.
//
// Red proofs: the turns branch of `Refractory.read` taken out (both cases
// load no refractory); the v55 ladder block taken out (the reload fails on
// the missing columns).

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Migrator, Value, Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Refractory;
import 'package:front_porch_ai/utils/utils.dart';
import '../../helpers/chat_db_teardown.dart';
import '../../helpers/refractory_judges.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_refr_legacy_').path;
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
    db = AppDatabase.forTesting(sameIsolate: true);
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
  });

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    await disposeChatThenCloseDb(chat, db);
  });

  Future<Object?> column(String name, String sessionId) async {
    final row = await db
        .customSelect(
          'SELECT $name AS v FROM sessions WHERE id = ?',
          variables: [Variable(sessionId)],
        )
        .getSingle();
    return row.data['v'];
  }

  test('a 1:1 row with only the turn columns loads turns × 15', () async {
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        firstMessage: 'The porch light hums.',
        imagePath: 'refr-legacy-mara.png',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      )..dbId = 'char-refr-legacy',
    );
    await chat.setRealismEnabled(true);
    await chat.setNsfwCooldownEnabled(true);
    await chat.sendMessage('Evening.');
    await settle();
    final id = chat.currentSessionId!;

    // The installed base: a v54 row. Drop the minute columns, put the turns
    // in, and run the ladder from 54 the way an upgrade does.
    for (final c in [
      'refractory_minutes_remaining',
      'refractory_minutes_total',
      'refractory_opened',
    ]) {
      await db.customStatement('ALTER TABLE sessions DROP COLUMN $c');
    }
    await db.customUpdate(
      'UPDATE sessions SET cooldown_turns_remaining = 5, '
      'cooldown_turns_total = 7 WHERE id = ?',
      variables: [Variable(id)],
      updates: {db.sessions},
    );
    await db.migration.onUpgrade(Migrator(db), 54, db.schemaVersion);
    expect(
      await column('refractory_minutes_remaining', id),
      isNull,
      reason: 'the v55 step adds the column, NULL on every existing row',
    );

    await chat.reloadCurrentSession();
    expect(
      chat.nsfwService.refractory,
      const Refractory(minutes: 75, total: 105, opened: true),
    );

    // Read once: the next save writes minutes, which win from then on.
    llm.minutes = 20;
    await chat.sendMessage('We sit a while.');
    await settle();
    expect(chat.nsfwService.refractoryMinutesRemaining, 55);
    expect(await column('refractory_minutes_remaining', id), 55);
  });

  test('a group member with only the old keys loads turns × 15, speaking '
      'or present', () async {
    await db.insertGroup(GroupsCompanion.insert(id: 'grp-old', name: 'Old'));
    for (final (id, name) in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-old',
          name: name,
          avatarFilename: Value('refr-old-${name.toLowerCase()}.png'),
          frontPorchExtensions: const Value(_realismOn),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-old', name: 'Old'),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
    await chat.setNsfwCooldownEnabled(true);
    CharacterCard member(String name) =>
        chat.groupCharacters.firstWhere((c) => c.name == name);
    chat.setNextCharacter(member('Ada'));
    await chat.sendMessage('Evening, both of you.');
    await settle();
    final id = chat.currentSessionId!;

    // Rewrite both members the way a pre-minutes build saved them.
    final raw = await column('group_realism_state', id) as String;
    final state = jsonDecode(raw) as Map<String, dynamic>;
    final perChar = state['perChar'] as Map<String, dynamic>;
    void legacy(String name, int remaining, int total) {
      final m = perChar[groupMemberStoreId(member(name))] as Map? ?? {};
      m.removeWhere((k, _) => k.toString().startsWith('refractory'));
      m['nsfwCooldownEnabled'] = true;
      m['cooldownTurnsRemaining'] = remaining;
      m['cooldownTurnsTotal'] = total;
      perChar[groupMemberStoreId(member(name))] = m;
    }

    legacy('Ada', 5, 5); // climaxed, has not spoken since
    legacy('Bea', 3, 4); // already had her opening turn
    await db.customUpdate(
      'UPDATE sessions SET group_realism_state = ? WHERE id = ?',
      variables: [Variable(jsonEncode(state)), Variable(id)],
      updates: {db.sessions},
    );
    await chat.reloadCurrentSession();

    llm.minutes = 30;
    chat.setNextCharacter(member('Bea'));
    await chat.triggerNextCharacter();
    await settle();
    expect(chat.messages.last.sender, 'Bea', reason: 'baseline: Bea spoke');

    Refractory of(String name) =>
        Refractory.read(chat.getRealismStateForGroupCharacter(member(name))!)!;
    expect(
      of('Ada'),
      const Refractory(minutes: 45, total: 75),
      reason: 'present, silent: 5 turns = 75 min, less the 30-minute beat',
    );
    expect(
      of('Bea'),
      const Refractory(minutes: 15, total: 60, opened: true),
      reason: 'speaking: 3 turns = 45 min, less the 30-minute beat',
    );
  });
}
