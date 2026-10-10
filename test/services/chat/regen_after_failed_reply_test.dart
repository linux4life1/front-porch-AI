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

// Regenerate after a reply that failed with a server error. The failure
// leaves `user -> empty reply -> error banner`; Regenerate used to do
// nothing there, because only `user -> banner` was recognised. It now drops
// both and answers the user line again, as the same speaker (in a group the
// member who failed, not the next one in the rotation).
//
// Real ChatService, real HTTP to the FakeBackendServer, whose
// failChatCompletionContaining answers the conversation call with a 500.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

/// The goal check runs only with a provider wired, as in the app; this one
/// never starts or probes an engine.
class _QuietBackend extends BackendManager {
  _QuietBackend(super.storage);

  @override
  String? get backendPath =>
      p.join(Directory.systemTemp.path, 'fake-koboldcpp');

  @override
  Future<void> checkBackendAvailability() async {}

  @override
  Future<void> ensureEngineInstalled() async {}
}

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _reply = 'The porch boards creak.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    backend = await FakeBackendServer.start(replyPieces: const [_reply]);
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
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  /// Sends [line] with its conversation call failing, and checks the
  /// failure left `user -> empty [speaker] reply -> banner`.
  Future<void> sendThatFails(String line, String speaker) async {
    backend.failChatCompletionContaining = line;
    await chat.sendMessage(line);
    await _drain();
    expect(backend.chatFailuresServed, 1, reason: 'the turn did fail');
    final m = chat.messages;
    expect(m.last.sender, 'System', reason: 'the error banner is last');
    expect(m[m.length - 2].sender, speaker, reason: 'its bubble landed');
    expect(m[m.length - 2].text, isEmpty, reason: 'with nothing in it');
    expect(m[m.length - 3].isUser, isTrue);
  }

  /// After the regenerate: the user line answered by [speaker], no banner
  /// and no empty bubble left on screen or in the saved chat.
  Future<void> expectAnsweredBy(String line, String speaker) async {
    final m = chat.messages;
    expect(m.last.sender, speaker, reason: 'the same speaker answers');
    expect(m.last.text, _reply, reason: 'with a real reply');
    expect(m[m.length - 2].isUser, isTrue);
    expect(m[m.length - 2].text, line);
    expect(m.where((x) => x.sender == 'System'), isEmpty);
    expect(m.where((x) => !x.isUser && x.text.trim().isEmpty), isEmpty);
    final rows = await db.getMessagesForSession(chat.currentSessionId!);
    expect(rows.where((r) => r.sender == 'System'), isEmpty);
    expect(
      rows.where((r) => r.sender == speaker).length,
      m.where((x) => x.sender == speaker).length,
      reason: 'the saved chat matches the screen',
    );
  }

  test('1:1: regenerate after a failed reply answers the line', () async {
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Keeper',
        description: 'Exists only inside the failed-reply regen test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-keeper',
    );
    const line = 'The lanterns sway in the evening wind.';
    await sendThatFails(line, 'Keeper');

    await chat.regenerateLastMessage();
    await _drain();
    expect(backend.chatFailuresServed, 1);
    await expectAnsweredBy(line, 'Keeper');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('1:1: a quest the failed turn finished is open again', () async {
    // The pre-reply goal check finishes the quest; that change rides the
    // turn's reply so deleting the reply reopens it. Here it rode the empty
    // bubble of the failed turn, which Regenerate drops.
    backend.objectiveCheckVerdict = '1: YES';
    final storage = StorageService();
    final provider = LLMProvider(
      KoboldService(storage),
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _QuietBackend(storage),
    );
    addTearDown(provider.dispose);
    chat.setLLMProvider(provider);
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Keeper',
        description: 'Exists only inside the failed-reply regen test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-keeper-quest',
    );
    await chat.setObjective('Share porch lemonade before sunset');
    await chat.updateCheckFrequency(chat.activeObjectives.single, 1);
    const line = 'Want some lemonade?';
    await sendThatFails(line, 'Keeper');
    final ghostOps = chat
        .messages[chat.messages.length - 2]
        .activeMetadata?['objective_turn_ops'];
    expect(ghostOps, isNotEmpty, reason: 'the quest change rode the ghost');
    expect(chat.activeObjectives, isEmpty, reason: 'the check finished it');

    await chat.regenerateLastMessage();
    await _drain();
    await expectAnsweredBy(line, 'Keeper');
    expect(
      chat.activeObjectives,
      hasLength(1),
      reason:
          'a turn with no reply finishes no quest: the change is taken back '
          'with its bubble, as deleting a reply takes it back',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('group: the member whose reply failed answers again', () async {
    await db.insertGroup(GroupsCompanion.insert(id: 'grp-fail', name: 'Duet'));
    for (final (id, name) in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-fail',
          name: name,
          personality: Value('$name keeps the porch.'),
          avatarFilename: Value('${name.toLowerCase()}.png'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-fail',
        name: 'Porch Duet',
        turnOrder: TurnOrder.roundRobin,
      ),
      groupRepo: GroupChatRepository(StorageService(), db),
    );
    const line = 'Evening, you two.';
    await sendThatFails(line, 'Ada');

    await chat.regenerateLastMessage();
    await _drain();
    await expectAnsweredBy(line, 'Ada');
    expect(chat.nextCharacter?.name, 'Bea', reason: "Ada's turn is done");

    await chat.sendMessage('How was the day?');
    await _drain();
    expect(chat.messages.last.sender, 'Bea', reason: 'the order carries on');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
