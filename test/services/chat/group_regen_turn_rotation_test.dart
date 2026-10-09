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

// A group regen redoes a turn; it does not take one. Ada speaks, Bea speaks
// ("Next: Ada"), Bea's reply is regenerated: the next turn is still Ada's.
// The regen used to leave Bea parked as a forced pick, so she answered twice.

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

  Future<void> enterGroup(TurnOrder order) async {
    await chat.setActiveGroup(
      GroupChat(id: 'grp-rot', name: 'Porch Duet', turnOrder: order),
      groupRepo: GroupChatRepository(StorageService(), db),
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
    await db.insertGroup(GroupsCompanion.insert(id: 'grp-rot', name: 'Duet'));
    for (final (id, name) in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-rot',
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

  /// Ada answers the send, Bea follows; the rotation is back on Ada.
  Future<void> adaThenBea() async {
    await chat.sendMessage('Evening, you two.');
    await _drain();
    expect(chat.messages.last.sender, 'Ada', reason: 'baseline: Ada first');
    await chat.triggerNextCharacter();
    await _drain();
    expect(chat.messages.last.sender, 'Bea', reason: 'baseline: Bea next');
    expect(chat.nextCharacter?.name, 'Ada', reason: 'baseline: Next: Ada');
  }

  test('round robin: regen of Bea leaves the next turn with Ada', () async {
    await enterGroup(TurnOrder.roundRobin);
    await adaThenBea();

    await chat.regenerateLastMessage();
    await _drain();
    expect(chat.messages.last.sender, 'Bea', reason: 'Bea re-speaks');
    expect(chat.messages.last.swipes.length, 2, reason: 'a new swipe');
    expect(chat.nextCharacter?.name, 'Ada', reason: 'Next: Ada still');

    await chat.sendMessage('How was the day?');
    await _drain();
    expect(chat.messages.last.sender, 'Ada');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('round robin: a failed regen leaves the next turn with Ada', () async {
    await enterGroup(TurnOrder.roundRobin);
    await adaThenBea();

    backend.failChatCompletionContaining = 'Evening, you two';
    await chat.regenerateLastMessage();
    await _drain();
    expect(backend.chatFailuresServed, 1, reason: 'the regen did fail');
    expect(
      chat.messages.where((m) => m.sender == 'Bea').length,
      1,
      reason: "Bea's reply is restored (the error banner follows it)",
    );
    expect(chat.nextCharacter?.name, 'Ada');

    await chat.sendMessage('How was the day?');
    await _drain();
    expect(chat.messages.last.sender, 'Ada');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a speaker picked before the regen is still picked after', () async {
    await enterGroup(TurnOrder.roundRobin);
    await adaThenBea();
    chat.setNextCharacter(member('Bea'));

    await chat.regenerateLastMessage();
    await _drain();
    expect(chat.nextCharacter?.name, 'Bea', reason: 'the pick stands');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('random: the regen does not leave Bea as a forced pick', () async {
    await enterGroup(TurnOrder.random);
    chat.setNextCharacter(member('Bea'));
    await chat.sendMessage('Evening, you two.');
    await _drain();
    expect(chat.messages.last.sender, 'Bea');
    expect(chat.nextCharacter, isNull, reason: 'baseline: nobody forced');

    await chat.regenerateLastMessage();
    await _drain();
    expect(chat.messages.last.sender, 'Bea', reason: 'Bea re-speaks');
    expect(
      chat.nextCharacter,
      isNull,
      reason: 'random picks at send time; a forced Bea would answer again',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
