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

// PR 3 of docs/design/one-chat-ux.md: Realism, Needs, Afterglow and Objectives
// are switches of the CHARACTER, for this chat. A real group chat over the
// in-process backend: the gates read the speaking member's switch, a rewind
// reads the switch of the reply's speaker (never whoever is up next), a chat
// saved before the switches seeds them from what it held, and a 1:1 chat is
// untouched. A scripted model answer only ever feeds a gate or the clock
// here: what is asserted is whether a judge was ASKED, and where state went.

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
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_switch_').path;
        }
        return null;
      });
}

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  // A delete or a rewind saves on the real database after it returns.
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

const _on = '{"realism_engine":{"realism_enabled":true}}';
const _lite = '{"realism_engine":{"realism_enabled":true,"tier":"lite"}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late FakeBackendServer backend;

  Future<void> openGroup({bool withGuest = false}) async {
    await chat.setActiveGroup(
      GroupChat(id: 'grp-switch', name: 'The Cast'),
      groupRepo: GroupChatRepository(storage, db),
    );
  }

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
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
      GroupsCompanion.insert(id: 'grp-switch', name: 'The Cast'),
    );
    for (final (id, name, ext) in [
      ('mem-ada', 'Ada', _on),
      ('mem-bea', 'Bea', _on),
      ('mem-cy', 'Cy', _lite),
    ]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-switch',
          name: name,
          personality: Value('$name keeps the porch.'),
          avatarFilename: Value('${name.toLowerCase()}.png'),
          frontPorchExtensions: Value(ext),
        ),
      );
    }
    await openGroup();
    await chat.setRealismEnabled(true);
    await chat.setNeedsSimEnabled(true);
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    await backend.close();
  });

  CharacterCard member(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);
  String idOf(String name) => groupMemberStoreId(member(name));
  int bond(String name) =>
      chat.relationshipService.getGroupAffectionScore(idOf(name));

  group('the gates read the speaking member\'s switch', () {
    test(
      'a member with Realism off is not scored while the other is',
      () async {
        final ada = idOf('Ada');
        await chat.setMemberRealismEnabled(ada, false);
        expect(chat.realismSwitchFor(ada), isFalse);
        expect(chat.realismSwitchFor(idOf('Bea')), isTrue, reason: 'only Ada');

        chat.setNextCharacter(member('Ada'));
        await chat.sendMessage('I bring you both a cup of tea.');
        await _drain();
        expect(chat.messages.last.sender, 'Ada');
        expect(
          backend.feelingsJudgePrompts,
          isEmpty,
          reason: 'Ada has Realism off, so no judge scores her',
        );
        expect(bond('Ada'), 0, reason: 'her bond held');

        // Bea answers the same line through the Next button: her turn is
        // scored, the other member's switch does not reach her.
        chat.setNextCharacter(member('Bea'));
        await chat.triggerNextCharacter();
        await _drain();
        expect(chat.messages.last.sender, 'Bea');
        expect(
          backend.feelingsJudgePrompts,
          isNotEmpty,
          reason: 'Bea has Realism on, so the judge is asked for her',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('Continue follows the continued member\'s switch', () async {
      final ada = idOf('Ada');
      await chat.setMemberRealismEnabled(ada, false);
      chat.setNextCharacter(member('Ada'));
      await chat.sendMessage('I bring you both a cup of tea.');
      await _drain();
      expect(chat.messages.last.sender, 'Ada');
      // Bea is up next, with Realism on: if the gate read the next speaker
      // the continued reply of Ada would be scored.
      expect(chat.nextCharacter?.name, 'Bea');
      await chat.continueGeneration();
      await _drain();
      expect(chat.messages.last.sender, 'Ada');
      expect(backend.feelingsJudgePrompts, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Needs: a member with Needs off does not tick, the rest do', () async {
      final ada = idOf('Ada');
      final bea = idOf('Bea');
      chat.debugSeedGroupSpeakerState(ada, needs: {'hunger': 80, 'energy': 80});
      chat.debugSeedGroupSpeakerState(bea, needs: {'hunger': 80, 'energy': 80});
      await chat.setMemberNeedsEnabled(ada, false);
      expect(chat.needsSwitchFor(ada), isFalse);
      expect(chat.needsSwitchFor(bea), isTrue);

      // The clock moves an hour: scripted minutes feed the clock's math.
      await chat.timeService.evaluateTimeProgressAndPostureIfNeeded(
        charName: 'Ada',
        recent: 'User: hi\nAda: hello',
        shortTermTierName: 'Warm',
        onChunk: null,
        fireLLMEval: (prompt, {onChunk}) async =>
            '{"minutes_elapsed": 180, "new_day": false}',
        stripThinkBlocks: (s) => s,
        extractJsonBool: (text, key) {
          final m = RegExp('"$key"\\s*:\\s*(true|false)').firstMatch(text);
          return m == null ? null : m.group(1) == 'true';
        },
        setSpatialStance: (_) {},
        getCurrentSpatialStance: () => '',
        getCharacterEmotion: () => '',
        getEmotionIntensity: () => '',
        timeOnly: true,
      );

      // Ada is the one speaking, with Needs off: the cast still wears.
      chat.debugPinTurnSpeakerForRealism(ada);
      expect(chat.needsActive, isFalse, reason: 'the speaker\'s gate is shut');
      chat.realism.needsPass.wearBeatOn(
        ChatMessage(text: 'x', sender: 'Ada', isUser: false),
      );
      chat.debugPinTurnSpeakerForRealism(null);

      expect(chat.debugGroupNeeds(ada)['hunger'], 80, reason: 'held, not worn');
      expect(
        chat.debugGroupNeeds(bea)['hunger'],
        lessThan(80),
        reason: 'Bea\'s body still lives',
      );
    });

    test('Needs: an Away member wears by their own switch', () async {
      final ada = idOf('Ada');
      final bea = idOf('Bea');
      chat.debugSeedGroupSpeakerState(ada, needs: {'hunger': 80});
      chat.debugSeedGroupSpeakerState(bea, needs: {'hunger': 80});
      await chat.setGroupMemberAway(ada, away: false);
      expect(chat.realismSwitchFor(ada), isTrue, reason: 'Away leaves it');
      await chat.setMemberNeedsEnabled(bea, false);
      await chat.timeService.evaluateTimeProgressAndPostureIfNeeded(
        charName: 'Ada',
        recent: 'User: hi\nAda: hello',
        shortTermTierName: 'Warm',
        onChunk: null,
        fireLLMEval: (prompt, {onChunk}) async =>
            '{"minutes_elapsed": 180, "new_day": false}',
        stripThinkBlocks: (s) => s,
        extractJsonBool: (text, key) {
          final m = RegExp('"$key"\\s*:\\s*(true|false)').firstMatch(text);
          return m == null ? null : m.group(1) == 'true';
        },
        setSpatialStance: (_) {},
        getCurrentSpatialStance: () => '',
        getCharacterEmotion: () => '',
        getEmotionIntensity: () => '',
        timeOnly: true,
      );
      chat.debugPinTurnSpeakerForRealism(ada);
      chat.realism.needsPass.wearBeatOn(
        ChatMessage(text: 'x', sender: 'Ada', isUser: false),
      );
      chat.debugPinTurnSpeakerForRealism(null);
      expect(chat.debugGroupNeeds(ada)['hunger'], lessThan(80));
      expect(chat.debugGroupNeeds(bea)['hunger'], 80, reason: 'Needs off');
    });

    test('Objectives: the speaking member\'s own switch', () async {
      final ada = idOf('Ada');
      final bea = idOf('Bea');
      await chat.controlsDoor.memberSwitches.setObjectives(ada, false);
      chat.debugPinTurnSpeakerForRealism(ada);
      expect(chat.objectivesActive, isFalse);
      chat.debugPinTurnSpeakerForRealism(bea);
      expect(chat.objectivesActive, isTrue);
      chat.debugPinTurnSpeakerForRealism(null);
    });

    test('Afterglow: a member\'s switch is theirs for this chat', () async {
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      final ada = idOf('Ada');
      final bea = idOf('Bea');
      expect(chat.afterglowRunsFor(member('Ada')), isTrue);
      await chat.setMemberAfterglowSwitch(ada, false);
      expect(chat.afterglowRunsFor(member('Ada')), isFalse);
      expect(chat.afterglowRunsFor(member('Bea')), isTrue);
      expect(chat.afterglowSwitchFor(bea), isTrue);
      // The member copy's flag is only the default for a new chat.
      expect(
        member('Ada').frontPorchExtensions?.afterglowEnabled ?? true,
        true,
      );
    });
  });

  group(
    'a rewind reads the reply speaker\'s switches, never the next one\'s',
    () {
      test('regen of Ada rewinds and re-scores her while Bea (up next) has '
          'Realism off and the chat-wide switch is off', () async {
        // Only Ada has Realism on: the chat's own switch is off, so a rewind
        // that read it (or the next speaker's) would skip Ada's.
        await chat.setRealismEnabled(false);
        await chat.setMemberRealismEnabled(idOf('Ada'), true);
        chat.setNextCharacter(member('Ada'));
        await chat.sendMessage('I bring you a cup of tea.');
        await _drain();
        expect(chat.messages.last.sender, 'Ada');
        final scored = bond('Ada');
        expect(scored, isNot(0), reason: 'baseline: Ada\'s send scored');
        expect(chat.nextCharacter?.name, 'Bea');

        await chat.regenerateLastMessage();
        await _drain();
        expect(chat.messages.last.sender, 'Ada');
        expect(
          bond('Ada'),
          scored,
          reason: 'the same line, rewound by Ada\'s own switch: not stacked',
        );
      }, timeout: const Timeout(Duration(minutes: 2)));

      test(
        'delete of a reply whose speaker has Needs off gives nothing back',
        () async {
          final ada = idOf('Ada');
          chat.setNextCharacter(member('Ada'));
          await chat.sendMessage('I bring you a cup of tea.');
          await _drain();
          expect(chat.messages.last.sender, 'Ada');
          expect(
            chat.messages.last.activeMetadata?['needs_deltas'],
            isA<Map>(),
            reason: 'baseline: the reply carries Needs chips to give back',
          );
          final held = Map<String, int>.from(chat.debugGroupNeeds(ada));
          expect(held, isNotEmpty);

          // Needs off for Ada AFTER the reply (the chat's own switch stays on):
          // her bars are held, so deleting the reply must not move them.
          await chat.setMemberNeedsEnabled(ada, false);
          chat.deleteMessage(chat.messages.length - 1);
          await _drain();
          expect(chat.debugGroupNeeds(ada), held);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'Reprocess Needs is offered by the reply speaker\'s switch',
        () async {
          final bea = idOf('Bea');
          chat.setNextCharacter(member('Ada'));
          await chat.sendMessage('I bring you a cup of tea.');
          await _drain();
          expect(chat.messages.last.sender, 'Ada');
          await chat.setMemberNeedsEnabled(bea, false);
          expect(chat.nextCharacter?.name, 'Bea');
          expect(chat.needsActive, isFalse, reason: 'up next has Needs off');
          expect(
            chat.reprocessNeedsTargetFor(chat.messages.length - 1),
            isNotNull,
            reason: 'the reply is Ada\'s, and her Needs run',
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
  );

  group('a chat saved before the switches', () {
    test('seeds every member\'s switches from what the chat held, and a '
        'default edited later never reaches it', () async {
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      chat.setNextCharacter(member('Ada'));
      await chat.sendMessage('I bring you a cup of tea.');
      await _drain();
      // The chat as an older build saved it: no per-member switch keys, one
      // chat-wide Afterglow switch on, Bea's flag on her member copy off.
      for (final name in ['Ada', 'Bea']) {
        final bag = chat.realism.groups.members[idOf(name)];
        bag?.realismSwitch = null;
        bag?.needsSwitch = null;
        bag?.afterglowSwitch = null;
        bag?.objectivesSwitch = null;
      }
      chat.realism.groups.afterglowOn = true;
      member('Bea').frontPorchExtensions = member(
        'Bea',
      ).frontPorchExtensions!.copyWith(afterglowEnabled: false);
      await chat.persistGroupMemberExtensions(memberId: idOf('Bea'));
      await chat.sessionStore.save();

      await openGroup();
      final ada = idOf('Ada');
      final bea = idOf('Bea');
      for (final id in [ada, bea]) {
        final bag = chat.realism.groups.members[id]!;
        expect(bag.realismSwitch, isTrue, reason: 'the chat\'s Realism');
        expect(bag.needsSwitch, isTrue, reason: 'the chat\'s Needs');
        expect(bag.afterglowSwitch, isNotNull, reason: 'seeded, not derived');
      }
      expect(chat.afterglowSwitchFor(ada), isTrue);
      expect(chat.afterglowSwitchFor(bea), isFalse, reason: 'her old flag');

      // The default for the NEXT chat is edited: this one is untouched.
      await chat.setMemberAfterglowEnabled(member('Ada'), false);
      expect(chat.afterglowSwitchFor(ada), isTrue);
      expect(chat.afterglowRunsFor(member('Ada')), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a member\'s switches survive a turn, a reopen and a reset', () async {
      final ada = idOf('Ada');
      await chat.setMemberRealismEnabled(ada, false);
      await chat.setMemberNeedsEnabled(ada, false);
      chat.setNextCharacter(member('Bea'));
      await chat.sendMessage('I bring you a cup of tea.');
      await _drain();
      await openGroup();
      expect(chat.realismSwitchFor(ada), isFalse);
      expect(chat.needsSwitchFor(ada), isFalse);
      expect(chat.realismSwitchFor(idOf('Bea')), isTrue);
      chat.resetRealismForGroupCharacter(member('Ada'));
      expect(chat.realismSwitchFor(ada), isFalse, reason: 'a reset keeps it');
      expect(chat.needsSwitchFor(ada), isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a guest promoted to full starts with the chat\'s switches', () async {
      final cy = idOf('Cy');
      expect(member('Cy').isLite, isTrue);
      expect(chat.realism.groups.members[cy]?.realismSwitch, isNull);
      await chat.promoteGuestToFull(member('Cy'));
      final bag = chat.realism.groups.members[cy]!;
      expect(bag.realismSwitch, isTrue);
      expect(bag.needsSwitch, isTrue);
      expect(chat.realismSwitchFor(cy), isTrue);
    });
  });

  test('a 1:1 chat has one character and one switch', () async {
    final solo = CharacterCard(
      name: 'Solo',
      description: 'Keeps the porch.',
      firstMessage: 'Evening.',
      imagePath: '/tmp/solo-switch.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
      ),
    );
    await CharacterRepository(db, storage).addCharacter(solo);
    await chat.setActiveCharacter(solo);
    expect(chat.isGroupMode, isFalse);
    expect(chat.realismEnabled, isTrue);
    // Whatever id the caller names, the chat's one switch answers.
    await chat.setMemberRealismEnabled('', false);
    expect(chat.realismChatSwitch, isFalse);
    expect(chat.realismSwitchFor('anyone'), isFalse);
    expect(chat.realismEnabled, isFalse);
    expect(chat.realismEnabledFor('anyone'), isFalse);
    await chat.setMemberRealismEnabled('', true);
    expect(chat.realismEnabledFor(''), isTrue);
    await chat.setMemberNeedsEnabled('', false);
    expect(chat.needsSimEnabled, isFalse);
    expect(chat.needsSwitchFor(''), isFalse);
  });
}
