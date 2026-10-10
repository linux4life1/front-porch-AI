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

// A hand-picked group turn is still a turn. Ada, Bea and Cy take turns in
// order; the user picks Cy, Cy speaks, and the next turn is Ada's, as if
// Cy had spoken in rotation. The pick used to leave the rotation parked on
// Cy, so Cy answered again on the very next turn.

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
      GroupChat(id: 'grp-pick', name: 'Porch Trio'),
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
    await db.insertGroup(GroupsCompanion.insert(id: 'grp-pick', name: 'Trio'));
    for (final (id, name) in [
      ('mem-ada', 'Ada'),
      ('mem-bea', 'Bea'),
      ('mem-cy', 'Cy'),
    ]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-pick',
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

  test('a speaker picked by hand: the next turn follows them', () async {
    await enterGroup();
    expect(chat.nextCharacter?.name, 'Ada', reason: 'baseline: Ada first');

    chat.setNextCharacter(member('Cy'));
    await chat.sendMessage('Evening, all.');
    await _drain();
    expect(chat.messages.last.sender, 'Cy', reason: 'the pick speaks');
    expect(chat.nextCharacter?.name, 'Ada', reason: 'Next: Ada');

    await chat.triggerNextCharacter();
    await _drain();
    expect(chat.messages.last.sender, 'Ada', reason: 'not Cy again');
    await chat.triggerNextCharacter();
    await _drain();
    expect(chat.messages.last.sender, 'Bea');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an @mention: the next turn follows the named member', () async {
    await enterGroup();
    await chat.sendMessage('@Bea how was the day?');
    await _drain();
    expect(chat.messages.last.sender, 'Bea', reason: 'the mention speaks');
    expect(chat.nextCharacter?.name, 'Cy', reason: 'Next: Cy, not Bea');

    await chat.triggerNextCharacter();
    await _drain();
    expect(chat.messages.last.sender, 'Cy');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('/speak: the next turn follows the member who spoke', () async {
    await enterGroup();
    await chat.sendMessage('/speak Cy');
    await _drain();
    expect(chat.messages.last.sender, 'Cy', reason: '/speak Cy speaks');
    expect(chat.nextCharacter?.name, 'Ada', reason: 'Next: Ada, not Cy');

    await chat.triggerNextCharacter();
    await _drain();
    expect(chat.messages.last.sender, 'Ada');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    '/speak that fails: the member is still up next for the retry',
    () async {
      await enterGroup();
      backend.failChatCompletionContaining = 'Cy keeps the porch';
      await chat.sendMessage('/speak Cy');
      await _drain();
      expect(backend.chatFailuresServed, 1, reason: 'the turn did fail');
      expect(
        chat.messages.where((m) => m.sender == 'Cy' && m.text.isNotEmpty),
        isEmpty,
        reason: 'only the empty bubble the failed stream left',
      );
      expect(chat.nextCharacter?.name, 'Cy', reason: 'Next: still Cy');

      await chat.sendMessage('Go on, Cy.');
      await _drain();
      expect(chat.messages.last.sender, 'Cy', reason: 'the retry gives Cy');
      expect(chat.nextCharacter?.name, 'Ada');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('/exit: the member after the leaver still gets the next turn', () async {
    await enterGroup();
    await chat.sendMessage('Evening, all.');
    await _drain();
    expect(chat.messages.last.sender, 'Ada', reason: 'baseline: Ada first');

    expect(await chat.exitGroupMember(member('Bea'), groupRepo), isTrue);
    await _drain();
    expect(chat.messages.last.sender, 'Bea', reason: "Bea's goodbye");
    expect(chat.nextCharacter?.name, 'Cy', reason: 'Cy follows Bea');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
