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

// A bond/trust judge that answers with no readable score must not look like
// a real "no change". Live report: `[Realism:OneShot] Failed — no JSON`, and
// the reply still read "Bond unchanged · Trust unchanged". The reply now
// carries kFeelingsUnscoredMeta and no bond/trust keys, the phone payload
// says feelingsUnscored, and a regen that scores clears it on its own swipe.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show kFeelingsUnscoredMeta;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';

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
const _prose = 'She seems happier now, I think. Hard to say how much.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late CharacterRepository repo;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
    });
    db = AppDatabase.forTesting();
    backend = await FakeBackendServer.start(
      replyPieces: ['She leans on the porch rail ', 'and smiles.'],
    );
    storage = StorageService();
    repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
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

  Future<void> oneToOne() async {
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Unscored Tester',
        description: 'Exists only inside the feelings-unscored test.',
        firstMessage: 'Welcome to the porch.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-unscored',
    );
    await _drain();
  }

  Map<String, dynamic> lastMeta() =>
      chat.messages.last.activeMetadata ?? const <String, dynamic>{};

  Map<String, dynamic> phoneChips() {
    final facade = ChatFacade(chat, repo, null, null, null);
    final msgs = (facade.state()['messages'] as List)
        .cast<Map<String, dynamic>>();
    return Map<String, dynamic>.from((msgs.last['chips'] as Map?) ?? const {});
  }

  void expectUnscored(String why) {
    final meta = lastMeta();
    expect(meta[kFeelingsUnscoredMeta], isTrue, reason: why);
    expect(
      meta.containsKey('bond_delta'),
      isFalse,
      reason: 'a failed judge must not leave a bond score ($why)',
    );
    expect(meta.containsKey('trust_delta'), isFalse, reason: why);
  }

  void expectScored(String why) {
    final meta = lastMeta();
    expect(meta[kFeelingsUnscoredMeta], isNull, reason: why);
    expect(meta['bond_delta'], 13, reason: why);
    expect(meta['trust_delta'], 1, reason: why);
  }

  // '' is the live report's case: an empty answer, logged by one-shot as
  // "Failed — no JSON". Prose is a model that ignored the format.
  const answers = {'empty': '', 'prose': _prose};
  for (final mode in [OneShotMode.on, OneShotMode.off]) {
    for (final answer in answers.entries) {
      test('1:1 ${mode.name}, ${answer.key} answer: a failed judge reads "not '
          'scored", a regen that scores clears it, a failed regen sets it '
          'again', () async {
        await storage.realismSettings.setOneShotMode(mode);
        await oneToOne();
        final bondBefore = chat.relationshipService.affectionScore;

        backend.feelingsJudgeAnswer = answer.value;
        await chat.sendMessage('I bring you a cup of tea.');
        await _drain();
        expect(backend.feelingsJudgeAnswersServed, greaterThan(0));
        expectUnscored('the send was never scored');
        expect(chat.relationshipService.affectionScore, bondBefore);
        final chips = phoneChips();
        expect(chips['feelingsUnscored'], isTrue);
        expect(chips.containsKey('bondDelta'), isFalse);
        expect(chips.containsKey('trustDelta'), isFalse);

        backend.feelingsJudgeAnswer = null;
        await chat.regenerateLastMessage();
        await _drain();
        expect(chat.messages.last.swipes.length, 2);
        expectScored('the regen scored, so its swipe is a real result');
        expect(phoneChips()['feelingsUnscored'], isNull);
        expect(phoneChips()['bondDelta'], 13);

        // Swiping back shows the first swipe as it was: still not scored.
        await chat.swipeMessage(chat.messages.length - 1, -1);
        await _drain();
        expectUnscored('swipe 1 was never scored');
        await chat.swipeMessage(chat.messages.length - 1, 1);
        await _drain();
        expectScored('swipe 2 kept its score');

        backend.feelingsJudgeAnswer = answer.value;
        await chat.regenerateLastMessage();
        await _drain();
        expect(chat.messages.last.swipes.length, 3);
        expectUnscored('a failed regen is not scored either');
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  }

  test('Continue does not score, so it keeps the reply as it was', () async {
    await storage.realismSettings.setOneShotMode(OneShotMode.off);
    await oneToOne();
    backend.feelingsJudgeAnswer = _prose;
    await chat.sendMessage('I bring you a cup of tea.');
    await _drain();
    expectUnscored('baseline: the send was not scored');

    backend.feelingsJudgeAnswer = null;
    await chat.continueGeneration();
    await _drain();
    expectUnscored('Continue runs no judge; the reply is still unscored');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('group: a failed judge on a speaker reads "not scored"', () async {
    await storage.realismSettings.setOneShotMode(OneShotMode.off);
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-unscored', name: 'The Cast'),
    );
    for (final (id, name) in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-unscored',
          name: name,
          personality: Value('$name keeps the porch.'),
          avatarFilename: Value('${name.toLowerCase()}.png'),
          frontPorchExtensions: const Value(_on),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-unscored', name: 'The Cast'),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
    final ada = chat.groupCharacters.firstWhere((c) => c.name == 'Ada');
    expect(chat.isGroupRealismActive, isTrue, reason: 'baseline: realism');

    backend.feelingsJudgeAnswer = _prose;
    chat.setNextCharacter(ada);
    await chat.sendMessage('Evening, you two.');
    await _drain();
    expect(chat.messages.last.sender, 'Ada');
    expectUnscored("Ada's judge gave nothing readable");
    expect(phoneChips()['feelingsUnscored'], isTrue);

    backend.feelingsJudgeAnswer = null;
    await chat.regenerateLastMessage();
    await _drain();
    expect(chat.messages.last.sender, 'Ada');
    expectScored("Ada's regen scored");
  }, timeout: const Timeout(Duration(minutes: 2)));
}
