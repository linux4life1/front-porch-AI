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

// A TURN THAT IS REFUSED BEFORE IT STARTS MUST LEAVE THE CHAT USABLE.
// `_generateResponse` raises the generating flag before its first await, and
// Continue then refuses a line whose scene guest has left, or a group line
// whose speaker is unclear. Those refusals returned with the flag still up:
// Send did nothing from then on, and the phone never heard the turn end.
//
// Red-proved: with the refusals returning without lowering the flag (the
// tip before the fix), the two Continue cases fail. The Regenerate case
// guards the twin: Regenerate refuses before any flag goes up, and its own
// finally clears the settling hold, so it passes on both sides.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
          return Directory.systemTemp.createTempSync('fpai_refused_').path;
        }
        return null;
      });
}

/// Answers every reply call with one plain line and every eval with nothing.
/// The line is never asserted: the tests count reply calls to tell "Send
/// reached the model" from "Send was swallowed".
class _CountingLlm extends LLMService {
  int replyCalls = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      replyCalls++;
      yield 'The porch swing creaks.';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'CountingLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late ChatService chat;
  late _CountingLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db, storage);
    llm = _CountingLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = llm;
    await storage.initialized;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 400 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> insertRows(
    String sid,
    List<(String, bool, String?, String)> rows,
  ) async {
    for (final (i, (sender, isUser, cid, line)) in rows.indexed) {
      await db.insertMessage(
        MessagesCompanion.insert(
          id: '$sid-m$i',
          sessionId: sid,
          position: i,
          sender: sender,
          isUser: isUser,
          characterId: Value(cid),
          swipes: Value(jsonEncode([line])),
        ),
      );
    }
  }

  /// A 1:1 chat whose last line is a scene guest's, and the guest is gone
  /// (no guest is stored on the session), the way it is after `/exit`.
  Future<void> openChatEndingOnDepartedGuest() async {
    final card = CharacterCard(
      name: 'Odile',
      description: 'Exists only inside the refused-turn test.',
      firstMessage: 'The screen door bangs.',
    );
    final tmpDir = Directory.systemTemp.createTempSync('refused_card_');
    card.imagePath = '${tmpDir.path}/Odile.png';
    await V2CardService().saveCardAsPng(card, card.imagePath!, null);
    await repo.addCharacter(card);
    const sid = '1700000000505';
    await db.insertSession(
      SessionsCompanion.insert(id: sid, characterId: Value(card.dbId)),
    );
    // Guest replies are stamped with the guest's own id, the host's with the
    // host's (chat_service_generation_stream.dart).
    await insertRows(sid, [
      ('You', true, null, 'Evening.'),
      ('Odile', false, card.stableGroupId, 'You are late.'),
      ('You', true, null, 'Wren, you too?'),
      ('Wren', false, 'Wren_1700000000123', 'Wren waves from the steps.'),
    ]);
    await chat.setActiveCharacter(card);
    await chat.loadSession(sid);
    expect(chat.messages.last.sender, 'Wren');
  }

  Future<void> expectSendStillWorks() async {
    expect(chat.isGenerating, isFalse, reason: 'the refused turn never ran');
    expect(chat.isSettlingTurn, isFalse);
    final calls = llm.replyCalls;
    final count = chat.messages.length;
    await chat.sendMessage('Hello?');
    await drainTurn();
    expect(llm.replyCalls, calls + 1, reason: 'Send must reach the model');
    expect(chat.messages.length, greaterThan(count));
  }

  test('a refused Continue on a guest who left leaves the chat usable, and '
      'tells the phone the turn is over', () async {
    await openChatEndingOnDepartedGuest();
    final ends = <String>[];
    final sub = chat.tokenStream.listen((t) {
      if (t == '__ERROR__' || t == '__DONE__') ends.add(t);
    });
    addTearDown(sub.cancel);

    await chat.continueGeneration();
    await drainTurn();
    expect(chat.guestActivityStatus, contains('they have left the scene'));
    expect(ends, isNotEmpty, reason: 'the phone ends its pending reply on it');
    await expectSendStillWorks();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the Regenerate twin: a refused Regenerate on a guest who left '
      'leaves the chat usable', () async {
    await openChatEndingOnDepartedGuest();
    await chat.regenerateLastMessage();
    await drainTurn();
    expect(chat.guestActivityStatus, contains('they have left the scene'));
    await expectSendStillWorks();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('group: a Continue whose speaker is unclear is refused and leaves the '
      'chat usable', () async {
    const gid = 'grp-two-alex';
    await db.insertGroup(GroupsCompanion.insert(id: gid, name: 'Two Alexes'));
    for (final (id, side) in const [
      ('mem-north', 'NORTH porch'),
      ('mem-south', 'SOUTH dock'),
    ]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: gid,
          name: 'Alex',
          personality: Value('Alex from the $side.'),
          avatarFilename: Value('Alex_$id.png'),
        ),
      );
    }
    const sid = '1700000000606';
    await db.insertSession(
      SessionsCompanion.insert(id: sid, groupId: const Value(gid)),
    );
    // Two members share the name and this line carries no speaker id, so
    // nobody can say which Alex spoke (group_speaker_resolution.dart).
    await insertRows(sid, [
      ('You', true, null, 'Which of you fixed the gate?'),
      ('Alex', false, null, 'I did, last spring.'),
    ]);
    await chat.setActiveGroup(
      GroupChat(id: gid, name: 'Two Alexes'),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.loadSession(sid);
    expect(chat.messages.last.sender, 'Alex');

    await chat.continueGeneration();
    await drainTurn();
    expect(chat.guestActivityStatus, contains('who said it is ambiguous'));
    await expectSendStillWorks();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
