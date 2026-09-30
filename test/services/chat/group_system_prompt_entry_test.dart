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

// A PER-CHARACTER GROUP SYSTEM PROMPT MUST SURVIVE OPENING THE GROUP.
//
// The prompt is authored in the create-group wizard (and in Edit Group) and
// stored in the group row's own v32 column, keyed by the member's UUID — which
// is exactly the id the member card resolves to at runtime, because the
// member's avatar file is named after that UUID.
//
// setActiveGroup seeded that map from the group row and then, a hundred lines
// later, called `_loadGroupRealismStateFromSession(null)`, whose first act is
// to zero every per-character config map. Its only refill source in that call
// is `defaultMemberRealismState`, which is perChar-only and cannot carry
// system prompts — so the authored prompt was gone before the first turn was
// ever built, and the greeting's `_saveChat()` then wrote the empty map into
// `sessions.group_realism_state`, making the loss permanent for that chat.
// (startNewChat's group branch documents the same trap in a comment and dodges
// it by never calling that loader.)
//
// These two guards were proven to fail: moving the seed back above the
// fresh-entry block turns both of them red (getSystemPromptForGroupCharacter
// returns '' and the persisted blob's characterSystemPrompts is {}).

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grpsys_').path;
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

  const prompt = 'Speak only in questions. Never answer one.';

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
          // setActiveGroup returns early without one and would resolve zero
          // members, so the assertions below would pass vacuously.
          ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;

    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-1', name: 'The Porch'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-1',
        groupId: 'grp-1',
        name: 'Evelyn',
        // A greeting, so the fresh chat actually mints and SAVES a session —
        // an empty transcript makes _saveChat bail and the persistence half of
        // this guard would prove nothing.
        firstMessage: const Value('The screen door bangs shut behind you.'),
        // The member's stable key IS the avatar basename, i.e. the member UUID
        // — the same key the wizard writes its prompt under.
        avatarFilename: const Value('mem-1.png'),
      ),
    );
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> enter() => chat.setActiveGroup(
    GroupChat(
      id: 'grp-1',
      name: 'The Porch',
      characterSystemPrompts: {'mem-1': prompt},
    ),
    // The no-repo fallback reads the AppDatabase singleton, not this test's
    // in-memory database, and would resolve no members at all.
    groupRepo: GroupChatRepository(storage, db),
  );

  test('opening a group keeps its per-character system prompt', () async {
    await enter();

    expect(chat.groupCharacters, hasLength(1));
    expect(
      chat.getSystemPromptForGroupCharacter(chat.groupCharacters.single),
      prompt,
      reason:
          'THE BUG: the fresh-entry realism load zeroes every per-character '
          'config map, so a seed placed before it is wiped and the member '
          'generates with her plain card prompt for the life of the chat.',
    );
  });

  test(
    'and the first save writes it into the session, not an empty map',
    () async {
      await enter();

      final sessions = await db.getSessionsForGroup('grp-1');
      expect(
        sessions,
        hasLength(1),
        reason: 'the greeting branch mints and saves the first session',
      );
      final blob = jsonDecode(sessions.single.groupRealismState);
      expect(
        (blob as Map)['characterSystemPrompts'],
        {'mem-1': prompt},
        reason:
            'the wipe was persisted, which is why re-opening the chat (or '
            'restarting the app) never recovered the prompt — the session blob '
            'is what later loads read.',
      );
    },
  );
}
