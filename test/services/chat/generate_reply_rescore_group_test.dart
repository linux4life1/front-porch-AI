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

// #339, group twin of generate_reply_rescore_test. User-last regen in a
// group used to skip the dance outright (no score at all). It now rewinds
// the speaker to the user line's per-speaker stamp and dances, so the
// speaker lands on the same bond as the first scoring — not zero, not two.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

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

const _on = '{"realism_engine":{"realism_enabled":true}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
    });
    backend = await FakeBackendServer.start(
      replyPieces: const ['She leans on the porch rail.'],
    );
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
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await storage.initialized;
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-rescore', name: 'The Cast'),
    );
    for (final (id, name) in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-rescore',
          name: name,
          personality: Value('$name keeps the porch.'),
          avatarFilename: Value('${name.toLowerCase()}.png'),
          frontPorchExtensions: const Value(_on),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-rescore', name: 'The Cast'),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  CharacterCard ada() =>
      chat.groupCharacters.firstWhere((c) => c.name == 'Ada');
  int adaBond() => chat.relationshipService.getGroupAffectionScore(
    groupMemberStoreId(ada()),
  );
  CharacterCard bea() =>
      chat.groupCharacters.firstWhere((c) => c.name == 'Bea');
  int beaBond() => chat.relationshipService.getGroupAffectionScore(
    groupMemberStoreId(bea()),
  );

  test('delete reply → Generate reply re-scores the speaker once', () async {
    expect(chat.isGroupRealismActive, isTrue, reason: 'baseline: realism');
    final before = adaBond();
    chat.setNextCharacter(ada());
    await chat.sendMessage('I bring you a cup of tea.');
    final scored = adaBond();
    expect(scored, isNot(before), reason: 'baseline: the send must score');

    chat.deleteMessage(chat.messages.length - 1);
    await _drain();
    expect(chat.messages.last.isUser, isTrue);

    chat.setNextCharacter(ada());
    await chat.regenerateLastMessage();
    await _drain();

    expect(chat.messages.last.isUser, isFalse);
    expect(
      chat.messages.last.activeMetadata?['realism_state'],
      isA<Map>(),
      reason: 'the regenerated group reply must be scored (#339)',
    );
    expect(
      adaBond(),
      scored,
      reason: 'same user line, same baseline → same bond, not stacked',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a pre-stamp group line is not stacked on Generate reply', () async {
    chat.setNextCharacter(ada());
    await chat.sendMessage('I bring you a cup of tea.');
    final scored = adaBond();

    chat.deleteMessage(chat.messages.length - 1);
    await _drain();
    // A line saved by an older build carries no per-speaker stamp.
    chat.messages.last.metadata?.remove('realism_pre_turn_by_speaker');

    chat.setNextCharacter(ada());
    await chat.regenerateLastMessage();
    await _drain();

    expect(chat.messages.last.isUser, isFalse);
    expect(
      adaBond(),
      scored,
      reason: 'no stamp to rewind to, so the retry must not re-score',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'a second responder is rewound too when both replies are deleted',
    () async {
      chat.setNextCharacter(ada());
      await chat.sendMessage('I bring you both a cup of tea.');
      chat.setNextCharacter(bea());
      await chat.triggerNextCharacter();
      await _drain();
      final beaScored = beaBond();
      expect(chat.messages.last.sender, 'Bea');

      chat.deleteMessage(chat.messages.length - 1);
      await _drain();
      chat.deleteMessage(chat.messages.length - 1);
      await _drain();
      expect(chat.messages.last.isUser, isTrue);

      chat.setNextCharacter(bea());
      await chat.regenerateLastMessage();
      await _drain();

      expect(chat.messages.last.sender, 'Bea');
      expect(
        beaBond(),
        beaScored,
        reason: 'Bea scored this line once already; replay must not stack',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
