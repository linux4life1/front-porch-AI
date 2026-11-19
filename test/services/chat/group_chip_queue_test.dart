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

// The cast chip's Next pill and the Director's cue share one slot: a hold,
// not a fired turn. queueSpeaker keeps a member for the next pick, the chip
// reads it back so the pill can show (and cancel) the hold, and a second
// queue replaces it — one chat, one next speaker. A hold survives refusal
// (the rotation snapshot puts it back); once picked, a failed stream goes
// down the standard failure path, so the pill must not double-promise.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  late FakeBackendServer backend;
  late GroupChatRepository groupRepo;

  Future<void> enterGroup() async {
    await chat.setActiveGroup(
      GroupChat(id: 'grp-queue', name: 'Porch Trio'),
      groupRepo: groupRepo,
    );
  }

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    backend = await FakeBackendServer.start(
      replyPieces: const ['The porch boards creak.'],
    );
    db = AppDatabase.forTesting();
    final storage = StorageService();
    groupRepo = GroupChatRepository(storage, db);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await storage.initialized;
    await db.insertGroup(GroupsCompanion.insert(id: 'grp-queue', name: 'Trio'));
    for (final (id, name) in [
      ('mem-ada', 'Ada'),
      ('mem-bea', 'Bea'),
      ('mem-cy', 'Cy'),
    ]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-queue',
          name: name,
          personality: Value('$name keeps the porch.'),
          avatarFilename: Value('${name.toLowerCase()}.png'),
        ),
      );
    }
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  CharacterCard member(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);

  test('a queued member answers the next turn and the hold clears', () async {
    await enterGroup();
    expect(chat.queuedSpeaker, isNull, reason: 'baseline: nobody held');

    chat.queueSpeaker(member('Cy'));
    expect(chat.queuedSpeaker?.name, 'Cy', reason: 'the pill reads the hold');

    await chat.triggerNextCharacter();
    await _drain();
    expect(chat.messages.last.sender, 'Cy', reason: 'the hold speaks');
    expect(chat.queuedSpeaker, isNull, reason: 'one-shot: the hold is spent');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('queueing someone else moves the hold — one next speaker', () async {
    await enterGroup();
    chat.queueSpeaker(member('Cy'));
    chat.queueSpeaker(member('Bea'));
    expect(chat.queuedSpeaker?.name, 'Bea');

    await chat.triggerNextCharacter();
    await _drain();
    expect(chat.messages.last.sender, 'Bea');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('cancel clears the hold, the rotation speaks as if never held',
      () async {
    await enterGroup();
    chat.queueSpeaker(member('Cy'));
    chat.clearQueuedSpeaker();
    expect(chat.queuedSpeaker, isNull);

    await chat.triggerNextCharacter();
    await _drain();
    expect(
      chat.messages.last.sender,
      'Ada',
      reason: 'rotation baseline, not Cy',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an away member can be queued: preview names them, the turn is theirs',
      () async {
    // The chip queue means "them, at work or away" — the present-walk in
    // the preview must not second-guess it, or the Next tooltip and the
    // sidebar badge name someone else while the pick speaks the queue.
    await enterGroup();
    final beaId = chat.characterIdFor(member('Bea'));
    expect(await chat.setGroupMemberAway(beaId, away: true), isTrue);

    chat.queueSpeaker(member('Bea'));
    expect(chat.queuedSpeaker?.name, 'Bea');
    expect(
      chat.nextCharacter?.name,
      'Bea',
      reason: 'preview == pick: the hold is not re-walked for presence',
    );

    await chat.triggerNextCharacter();
    await _drain();
    expect(chat.messages.last.sender, 'Bea', reason: 'Away speaks anyway');
    expect(chat.queuedSpeaker, isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a lite guest can be queued: holds, speaks, and the pill clears',
      () async {
    // The regression that hid the roster proved guests could only speak
    // via @name typing; the Next pill must reach them too, keyed by row
    // id — the name-matched hand pick used to drop them or land on the
    // first member.
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-mara',
        groupId: 'grp-queue',
        name: 'Mara',
        personality: const Value('Mara keeps the gate.'),
        avatarFilename: const Value('mara.png'),
        frontPorchExtensions: const Value('{"realism_engine":{"tier":"lite"}}'),
      ),
    );
    await enterGroup();
    expect(
      chat.cast.any((p) => p.name == 'Mara' && p.isLite),
      isTrue,
      reason: 'the lite row joined the cast',
    );

    chat.queueSpeaker(member('Mara'));
    expect(chat.queuedSpeaker?.name, 'Mara', reason: 'the pill holds a guest');

    await chat.triggerNextCharacter();
    await _drain();
    expect(
      chat.messages.last.sender,
      'Mara',
      reason: 'the rotation picks a queued lite guest',
    );
    expect(chat.queuedSpeaker, isNull, reason: 'one-shot');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a queued turn that fails spends the hold and lands the failure note',
      () async {
    await enterGroup();
    backend.failChatCompletionContaining = 'Cy keeps the porch';
    chat.queueSpeaker(member('Cy'));

    await chat.triggerNextCharacter();
    await _drain();
    expect(backend.chatFailuresServed, 1, reason: 'the turn did fail');
    expect(
      chat.messages.last.sender,
      'System',
      reason: 'the failure note replaces the empty bubble',
    );
    expect(
      chat.queuedSpeaker,
      isNull,
      reason: 'the pick consumed the hold — like any @ pick the retry rides '
          'the failure path, so the pill must not double-promise',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
