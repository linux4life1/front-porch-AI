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

/// PR 5b — Chaos Mode per character (docs/design/chaos-per-character.md).
///
/// The maintainer's acceptance: "Tea, Joey and Yugi are in a group chat.
/// Joey has chaos mode on while Tea and Yugi have it off" — same toggle,
/// same behaviour as 1:1. Here the cast is Ada / Bea / Cy and the one
/// rolling is Bea. What this pins:
///
///  * a chaos-off member's turn ticks nobody and rolls no wheel;
///  * a parked event waits for ITS member — it never rides another's turn;
///  * a member whose chaos is off cannot spin;
///  * an existing group seeds each member once from the group's switch.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../../integration_test/support/fake_backend.dart';
import '../../../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChaosModeService per-member math', () {
    ChaosModeService svc() => ChaosModeService(
      onNotify: () {},
      onSaveChat: () async {},
      onSetPendingRealismMetadata: (_, _) {},
    );

    test('a member with no switch seeded is off: no tick, no growth', () {
      final s = svc();
      final bag = GroupMemberRealism();
      expect(s.memberEnabled(bag), isFalse);
      expect(s.checkAndTickMember(bag), isFalse);
      expect(bag.chaosPressure, 0);
    });

    test('an on member grows on their tick; a cooldown turn spends instead', () {
      final s = svc();
      final bag = GroupMemberRealism()..chaosSwitch = true;
      s.checkAndTickMember(bag);
      // Growth lands before the roll either way; Normal grows 5.
      expect(bag.chaosPressure, 5);
      bag.chaosPressure = 50;
      bag.chaosCooldown = 2;
      expect(s.checkAndTickMember(bag), isFalse);
      expect(bag.chaosPressure, 50, reason: 'a cooldown turn grows nobody');
      expect(bag.chaosCooldown, 1);
    });

    test('a parked event reads pending until delivered, then clears only '
        'itself', () async {
      final s = svc();
      final bag = GroupMemberRealism()..chaosSwitch = true;
      final other = GroupMemberRealism()
        ..chaosSwitch = true
        ..chaosPendingEvent = "Cy's own event";
      await s.applyPreparedEventMember(bag, 'A lantern gutters out.');
      expect(bag.chaosPendingEvent, 'A lantern gutters out.');
      expect(bag.chaosPressure, 0);
      expect(bag.chaosCooldown, ChaosModeService.baseChance ~/ 5 * 2); // 2
      expect(s.memberHasPending(bag), isTrue);
      expect(
        other.chaosPendingEvent,
        "Cy's own event",
        reason: 'one member\'s apply never touches another bag',
      );

      s.markEventDeliveredMember(bag);
      expect(s.memberHasPending(bag), isFalse);
      s.clearDeliveredPendingMemberIfAny(bag);
      expect(bag.chaosPendingEvent, isNull);
      expect(
        other.chaosPendingEvent,
        "Cy's own event",
        reason: 'the clear is per member too',
      );
    });

    test('the 18+ gate reads the member\'s own spicy switch and the app '
        'themes switch', () {
      final s = ChaosModeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
        isAdultAllowed: () => true,
      );
      final bag = GroupMemberRealism()
        ..chaosSwitch = true
        ..chaosNsfw = true;
      expect(s.memberSpicyActive(bag), isTrue);
      bag.chaosNsfw = false;
      expect(s.memberSpicyActive(bag), isFalse);
    });
  });

  group('a group rolls per member', () {
    const castChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(castChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory' ||
              call.method == 'getApplicationServicesDirectory') {
            return Directory.systemTemp.createTempSync('fpai_chaosmem_').path;
          }
          return null;
        });

    late FakeBackendServer backend;
    late AppDatabase db;
    late StorageService storage;
    late ChatService chat;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': false,
      });
      backend = await FakeBackendServer.start(replyPieces: ['She nods.']);
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
      await db.insertGroup(GroupsCompanion.insert(id: 'grp-pm', name: 'Trio'));
      for (final name in ['Ada', 'Bea', 'Cy']) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: 'mem-${name.toLowerCase()}',
            groupId: 'grp-pm',
            name: name,
            avatarFilename: Value('${name.toLowerCase()}.png'),
          ),
        );
      }
    });

    tearDown(() async {
      await disposeChatThenCloseDb(chat, db);
      await backend.close();
    });

    Future<void> enter({bool chaosOn = false}) => chat.setActiveGroup(
      GroupChat(
        id: 'grp-pm',
        name: 'Trio',
        turnOrder: TurnOrder.roundRobin,
        chaosModeEnabled: chaosOn,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    CharacterCard cardNamed(String name) =>
        chat.groupCharacters.firstWhere((c) => c.name == name);
    String idOf(String name) => chat.characterIdFor(cardNamed(name));

    test('an existing group seeds every member from its switch, once', () async {
      await enter(chaosOn: true);
      await settle();
      for (final n in ['Ada', 'Bea', 'Cy']) {
        expect(
          chat.chaosSwitchFor(idOf(n)),
          isTrue,
          reason: '$n enters exactly where the group switch had them',
        );
      }
      // One member switches off; a later entry does not re-seed them.
      await chat.setMemberChaosEnabled(idOf('Ada'), false);
      expect(chat.chaosSwitchFor(idOf('Ada')), isFalse);
      expect(
        chat.chaosSwitchFor(idOf('Bea')),
        isTrue,
        reason: 'one member off leaves the others as they were',
      );
    });

    test('a chaos-off group enters with every member off, and one member '
        'switching on leaves the others off', () async {
      await enter();
      await settle();
      expect(chat.chaosSwitchFor(idOf('Ada')), isFalse);
      await chat.setMemberChaosEnabled(idOf('Bea'), true);
      expect(chat.chaosSwitchFor(idOf('Bea')), isTrue);
      expect(chat.chaosSwitchFor(idOf('Ada')), isFalse);
      expect(chat.chaosSwitchFor(idOf('Cy')), isFalse);
    });

    test("only Bea rolls: Ada's turn ticks nobody, Bea's parked event waits "
        'for Bea, and Ada cannot spin', () async {
      await enter();
      await settle();
      await chat.setMemberChaosEnabled(idOf('Bea'), true);

      // Ada answers. Her chaos is off: no wheel, no event, no pressure —
      // and Bea's gauge does not grow on Ada's turn either.
      await chat.sendMessage('Evening, all.');
      await settle();
      expect(chat.messages.last.sender, 'Ada');
      expect(backend.lastChatBody, isNot(contains('SCENE EVENT')));
      expect(chat.chaosPressureFor(idOf('Ada')), 0);

      // A member whose chaos is off cannot spin; Bea can.
      expect(chat.requestManualChanceTime(memberId: idOf('Ada')), isFalse);
      expect(chat.requestManualChanceTime(memberId: idOf('Bea')), isTrue);
      final shown = chat.webChanceTimeDisplay;
      expect(shown, isNotNull);

      // Give Ada another turn while Bea's event is parked: it must not
      // ride Ada's reply (the group-tick-everyone trap, injection side).
      chat.setNextCharacter(cardNamed('Ada'));
      await chat.sendMessage('Nothing for you two.');
      await settle();
      expect(chat.messages.last.sender, 'Ada');
      expect(
        backend.lastChatBody,
        isNot(contains('SCENE EVENT')),
        reason: "Bea's parked event never speaks through Ada",
      );

      // Accept for Bea; her turn then carries it, named to her.
      chat.acceptPendingChanceTime();
      expect(chat.chaosPendingFor(idOf('Bea')), shown);
      chat.setNextCharacter(cardNamed('Bea'));
      await chat.sendMessage('Bea, your turn.');
      await settle();
      expect(chat.messages.last.sender, 'Bea');
      expect(backend.lastChatBody, contains("Write Bea's immediate reaction"));
      expect(
        backend.lastChatBody,
        isNot(contains("Write Ada's")),
        reason: 'the event resolves to its own member',
      );
    });

    test('the cast digest reports each member, and switching one off zeroes '
        'their gauge and holds their parked event', () async {
      await enter();
      await settle();
      await chat.setMemberChaosEnabled(idOf('Bea'), true);
      var digest = chat.chaosCastDigest();
      expect(digest.map((m) => m.name), containsAll(['Ada', 'Bea', 'Cy']));
      expect(
        digest.firstWhere((m) => m.name == 'Bea').enabled,
        isTrue,
        reason: 'the badge reads this digest',
      );
      expect(
        digest.firstWhere((m) => m.name == 'Ada').enabled,
        isFalse,
      );

      chat.requestManualChanceTime(memberId: idOf('Bea'));
      chat.acceptPendingChanceTime();
      expect(chat.chaosPendingFor(idOf('Bea')), isNotNull);
      await chat.setMemberChaosEnabled(idOf('Bea'), false);
      expect(chat.chaosSwitchFor(idOf('Bea')), isFalse);
      expect(
        chat.chaosPendingFor(idOf('Bea')),
        isNotNull,
        reason: 'off hides and holds, never erases',
      );
    });
  });
}
