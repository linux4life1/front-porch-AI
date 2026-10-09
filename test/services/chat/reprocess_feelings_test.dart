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

// Manual Reprocess → Feelings: the Realism judges asked again about the user
// line the last reply answers, without throwing the reply away. A reply whose
// judge failed gets its score once (not stacked on top of anything), a second
// re-score lands where the first did, deleting the reply and generating again
// scores the line exactly once, and a re-score that cannot read an answer
// leaves the reply as it was. Real ChatService, real HTTP to the fake backend.

import 'dart:convert';
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
import 'package:front_porch_ai/utils/utils.dart' show StableGroupId;

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
        name: 'Rescore Tester',
        description: 'Exists only inside the feelings re-score test.',
        firstMessage: 'Welcome to the porch.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-rescore',
    );
    await _drain();
  }

  int last() => chat.messages.length - 1;
  Map<String, dynamic> lastMeta() =>
      chat.messages.last.activeMetadata ?? const <String, dynamic>{};

  Map<String, dynamic> phoneChips() {
    final facade = ChatFacade(chat, repo, null, null, null);
    final msgs = (facade.state()['messages'] as List)
        .cast<Map<String, dynamic>>();
    return Map<String, dynamic>.from((msgs.last['chips'] as Map?) ?? const {});
  }

  void expectScoredOnce(String why) {
    final meta = lastMeta();
    expect(meta[kFeelingsUnscoredMeta], isNull, reason: why);
    expect(meta['bond_delta'], 13, reason: why);
    expect(meta['trust_delta'], 1, reason: why);
    expect(meta['bond_reason'], 'smoke-test warmth', reason: why);
  }

  for (final mode in [OneShotMode.on, OneShotMode.off]) {
    test('1:1 ${mode.name}: a failed score is fixed by Feelings once, a '
        'second pass lands in the same place, and delete + Generate reply '
        'scores the line once', () async {
      await storage.realismSettings.setOneShotMode(mode);
      await oneToOne();
      final bond0 = chat.relationshipService.affectionScore;
      final trust0 = chat.relationshipService.trustLevel;

      backend.feelingsJudgeAnswer = _prose;
      await chat.sendMessage('I bring you a cup of tea.');
      await _drain();
      expect(lastMeta()[kFeelingsUnscoredMeta], isTrue, reason: 'baseline');
      expect(chat.reprocessFeelingsTargetFor(last()), 'Rescore Tester');
      expect(phoneChips()['feelingsReprocessable'], isTrue);
      final text = chat.messages.last.text;
      final swipes = chat.messages.last.swipes.length;
      final clock = chat.timeService.storyClockIso;

      backend.feelingsJudgeAnswer = null;
      expect(await chat.reprocessFeelings(last()), FeelingsRescore.scored);
      await _drain();
      expectScoredOnce('the re-score read the judge');
      expect(chat.relationshipService.affectionScore, bond0 + 13);
      expect(chat.relationshipService.trustLevel, trust0 + 1);
      final rs = lastMeta()['realism_state'] as Map;
      expect(rs['affectionScore'], bond0 + 13, reason: 'swipe/regen stamp');
      expect(chat.messages.last.text, text, reason: 'the reply stays');
      expect(chat.messages.last.swipes.length, swipes, reason: 'no new swipe');
      expect(chat.timeService.storyClockIso, clock, reason: 'no clock tick');
      final chips = phoneChips();
      expect(chips['bondDelta'], 13);
      expect(chips['trustDelta'], 1);
      expect(chips['feelingsUnscored'], isNull);

      expect(await chat.reprocessFeelings(last()), FeelingsRescore.scored);
      await _drain();
      expectScoredOnce('second pass');
      expect(
        chat.relationshipService.affectionScore,
        bond0 + 13,
        reason: 'a second re-score replaces the first, never stacks on it',
      );
      expect(chat.relationshipService.trustLevel, trust0 + 1);

      chat.deleteMessage(last());
      await _drain();
      expect(chat.messages.last.isUser, isTrue);
      await chat.regenerateLastMessage();
      await _drain();
      expect(chat.messages.last.isUser, isFalse);
      expect(
        chat.relationshipService.affectionScore,
        bond0 + 13,
        reason: 'the deleted reply took its re-scored bond with it',
      );
      expect(chat.relationshipService.trustLevel, trust0 + 1);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('1:1 ${mode.name}: a re-score asks the judge exactly what the send '
        'asked, and lands the same score', () async {
      await storage.realismSettings.setOneShotMode(mode);
      await oneToOne();
      final bond0 = chat.relationshipService.affectionScore;
      await chat.sendMessage('I bring you a cup of tea.');
      await _drain();
      expectScoredOnce('baseline: the send scored');
      final asked = List<String>.of(backend.feelingsJudgePrompts);
      expect(asked, isNotEmpty);

      expect(await chat.reprocessFeelings(last()), FeelingsRescore.scored);
      await _drain();
      expect(
        backend.feelingsJudgePrompts.skip(asked.length).first,
        asked.last,
        reason: 'same user line, same state before it, same question',
      );
      expectScoredOnce('the re-score');
      expect(chat.relationshipService.affectionScore, bond0 + 13);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('a re-score that cannot read an answer leaves the reply as it was, '
      'scored or not', () async {
    await storage.realismSettings.setOneShotMode(OneShotMode.off);
    await oneToOne();
    final bond0 = chat.relationshipService.affectionScore;
    await chat.sendMessage('I bring you a cup of tea.');
    await _drain();
    expectScoredOnce('baseline');

    backend.feelingsJudgeAnswer = _prose;
    expect(await chat.reprocessFeelings(last()), FeelingsRescore.unreadable);
    await _drain();
    expectScoredOnce('the old score stands');
    expect(chat.relationshipService.affectionScore, bond0 + 13);
    expect(chat.isSettlingTurn, isFalse, reason: 'input is not wedged');

    await chat.sendMessage('And a biscuit.');
    await _drain();
    expect(lastMeta()[kFeelingsUnscoredMeta], isTrue);
    final bond1 = chat.relationshipService.affectionScore;
    expect(await chat.reprocessFeelings(last()), FeelingsRescore.unreadable);
    expect(lastMeta()[kFeelingsUnscoredMeta], isTrue, reason: 'still says so');
    expect(chat.relationshipService.affectionScore, bond1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a re-score that crosses a bond tier files its Our Story card at '
      'the reply, not the line before it', () async {
    await storage.realismSettings.setOneShotMode(OneShotMode.off);
    await oneToOne();
    backend.feelingsJudgeAnswer = _prose;
    await chat.sendMessage('I bring you a cup of tea.');
    await _drain();
    final ownerId = chat.activeCharacter!.stableGroupId;
    Future<List<List<dynamic>>> milestoneCites() async => [
      for (final c in await chat.journalStore.cardsFor(
        chat.currentSessionId!,
        ownerId,
      ))
        if ((jsonDecode(c.metadata ?? '{}') as Map)['kind'] == 'milestone')
          jsonDecode(c.sourceMessageIds ?? '[]') as List<dynamic>,
    ];
    expect(await milestoneCites(), isEmpty, reason: 'baseline: not scored');

    backend.feelingsJudgeAnswer = null;
    expect(await chat.reprocessFeelings(last()), FeelingsRescore.scored);
    for (var i = 0; i < 5; i++) {
      await _drain();
    }
    expect(
      await milestoneCites(),
      [
        [last()],
      ],
      reason:
          '0 → 13 crosses into the first bond tier; the card cites the '
          'reply the score is on',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('only the last reply, and not with Realism off', () async {
    await storage.realismSettings.setOneShotMode(OneShotMode.off);
    await oneToOne();
    await chat.sendMessage('I bring you a cup of tea.');
    await _drain();
    final first = last();
    await chat.sendMessage('And a biscuit.');
    await _drain();
    expect(chat.reprocessFeelingsTargetFor(first), isNull);
    expect(await chat.reprocessFeelings(first), FeelingsRescore.refused);
    expect(chat.reprocessFeelingsTargetFor(last()), isNotNull);

    await chat.setRealismEnabled(false);
    expect(chat.reprocessFeelingsTargetFor(last()), isNull);
    expect(await chat.reprocessFeelings(last()), FeelingsRescore.refused);
    expect(phoneChips()['feelingsReprocessable'], isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('group: the speaker is re-scored once in their own entry, and delete '
      '+ Generate reply scores the line once', () async {
    await storage.realismSettings.setOneShotMode(OneShotMode.off);
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
    CharacterCard ada() =>
        chat.groupCharacters.firstWhere((c) => c.name == 'Ada');
    CharacterCard bea() =>
        chat.groupCharacters.firstWhere((c) => c.name == 'Bea');
    final adaBond0 = chat.getAffectionForGroupCharacter(ada());
    final adaTrust0 = chat.getTrustForGroupCharacter(ada());
    final beaBond0 = chat.getAffectionForGroupCharacter(bea());

    backend.feelingsJudgeAnswer = _prose;
    chat.setNextCharacter(ada());
    await chat.sendMessage('Evening, you two.');
    await _drain();
    expect(chat.messages.last.sender, 'Ada');
    expect(lastMeta()[kFeelingsUnscoredMeta], isTrue, reason: 'baseline');
    expect(chat.getAffectionForGroupCharacter(ada()), adaBond0);

    backend.feelingsJudgeAnswer = null;
    expect(chat.reprocessFeelingsTargetFor(last()), 'Ada');
    expect(await chat.reprocessFeelings(last()), FeelingsRescore.scored);
    await _drain();
    expectScoredOnce("Ada's re-score");
    expect(chat.getAffectionForGroupCharacter(ada()), adaBond0 + 13);
    expect(chat.getTrustForGroupCharacter(ada()), adaTrust0 + 1);
    expect(
      chat.getAffectionForGroupCharacter(bea()),
      beaBond0,
      reason: "Bea did not speak; her entry is not Ada's",
    );

    expect(await chat.reprocessFeelings(last()), FeelingsRescore.scored);
    await _drain();
    expect(
      chat.getAffectionForGroupCharacter(ada()),
      adaBond0 + 13,
      reason: 'second pass replaces, never stacks',
    );

    chat.deleteMessage(last());
    await _drain();
    expect(chat.messages.last.isUser, isTrue);
    chat.setNextCharacter(ada());
    await chat.regenerateLastMessage();
    await _drain();
    expect(chat.messages.last.sender, 'Ada');
    expect(
      chat.getAffectionForGroupCharacter(ada()),
      adaBond0 + 13,
      reason: 'the deleted reply took its re-scored bond with it',
    );
    expect(chat.getAffectionForGroupCharacter(bea()), beaBond0);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
