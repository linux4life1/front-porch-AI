// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// HOLD K1: a lite/guest reply still moves the chat clock and stamps
// the time chip. HOLD K2: soft slots must not be invented/persisted —
// promote then seeds a real vector only because the slot stayed empty.
// The clock is not a board-wide body tax on present full members.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
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
          return Directory.systemTemp.createTempSync('fpai_lite_wear_').path;
        }
        return null;
      });
}

const _full = '{"version":"2.5","realism_engine":{"realism_enabled":true}}';
const _lite = '{"version":"2.5","realism_engine":{"tier":"lite"}}';

const _floraNeeds = {
  'hunger': 40,
  'bladder': 80,
  'energy': 80,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": true}';
      return;
    }
    if (params.systemPrompt != null) {
      yield '*They stay on the porch with you.*';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLiteWear';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  ChatService? chat;
  _ScriptedLlm? llm;
  DebugPrintCallback? previousPrint;

  CharacterCard named(String name) =>
      chat!.groupCharacters.firstWhere((c) => c.name == name);

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 400 && (chat!.isGenerating || chat!.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> boot() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(CharacterRepository(db!, storage!))
          ..setGroupChatRepository(GroupChatRepository(storage!, db!))
          ..testLlmServiceOverride = llm;
    await storage!.initialized;

    await db!.insertGroup(
      GroupsCompanion.insert(id: 'grp-lite-wear', name: 'The Porch'),
    );
    await db!.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-flora',
        groupId: 'grp-lite-wear',
        name: 'Flora',
        firstMessage: const Value('Evening.'),
        avatarFilename: const Value('mem-flora.png'),
        frontPorchExtensions: const Value(_full),
      ),
    );
    await db!.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-guestpoke',
        groupId: 'grp-lite-wear',
        name: 'GuestPoke',
        firstMessage: const Value('Hi.'),
        avatarFilename: const Value('mem-guestpoke.png'),
        frontPorchExtensions: const Value(_lite),
      ),
    );
    await chat!.setActiveGroup(
      GroupChat(id: 'grp-lite-wear', name: 'The Porch'),
      groupRepo: GroupChatRepository(storage!, db!),
    );
    await chat!.setRealismEnabled(true);
    await chat!.setNeedsSimEnabled(true);
    await chat!.setPassageOfTimeEnabled(true);
    chat!.debugSeedGroupSpeakerState(
      named('Flora').stableGroupId,
      needs: _floraNeeds,
    );
    // Greeting seed must not hide the wear-invent bug: start the soft
    // slot empty so promote can still seed after the turn.
    chat!.debugSeedGroupSpeakerState(
      named('GuestPoke').stableGroupId,
      needs: const {},
    );
    chat!.debugReloadFirstGroupSpeakerScalars();
  }

  Map<String, int> floraNeeds() =>
      chat!.debugGroupNeeds(named('Flora').stableGroupId);

  Map<String, int> guestNeeds() =>
      chat!.debugGroupNeeds(named('GuestPoke').stableGroupId);

  setUp(() {
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    await disposeChatThenCloseDb(chat, db);
  });

  test(
    'GuestPoke clock tick wears Flora and stamps time; GuestPoke stays empty',
    () async {
      await boot();
      expect(named('GuestPoke').isLite, isTrue);
      expect(floraNeeds()['hunger'], 40);
      expect(guestNeeds(), isEmpty);

      chat!.setNextCharacter(named('GuestPoke'));
      await chat!.sendMessage('Say hello.');
      await drainTurn();

      final reply = chat!.messages.lastWhere((m) => !m.isUser);
      expect(reply.sender, 'GuestPoke');
      expect(
        floraNeeds()['hunger'],
        40,
        reason:
            'lite/guest clock advance stamps time — it does not '
            'tax Flora\'s hunger from the clock',
      );
      expect(
        guestNeeds(),
        isEmpty,
        reason: 'soft/lite must not invent or persist Needs via present wear',
      );
      expect(
        reply.activeMetadata?['time_passed'],
        '30 min',
        reason: 'live fail: lite clock minutes must still stamp the time chip',
      );

      await chat!.promoteGuestToFull(named('GuestPoke'));
      expect(named('GuestPoke').isLite, isFalse);
      final seeded = guestNeeds();
      expect(
        seeded,
        isNotEmpty,
        reason: 'promote seeds a real vector only when the slot stayed empty',
      );
      expect(
        seeded['hunger'],
        80,
        reason:
            'a worn invented baseline (78) would stick after promote; '
            'empty-then-seed is the card baseline',
      );
    },
  );

  test('full-member clock tick does not invent Needs on a soft slot', () async {
    await boot();
    expect(guestNeeds(), isEmpty);

    chat!.setNextCharacter(named('Flora'));
    await chat!.sendMessage('How are you?');
    await drainTurn();

    expect(floraNeeds()['hunger'], 40);
    expect(
      guestNeeds(),
      isEmpty,
      reason: 'soft must stay empty when a full member takes a beat',
    );

    await chat!.promoteGuestToFull(named('GuestPoke'));
    expect(guestNeeds()['hunger'], 80);
  });

  test('lite Continue does not wear Flora a second time', () async {
    await boot();
    chat!.setNextCharacter(named('GuestPoke'));
    await chat!.sendMessage('Say hello.');
    await drainTurn();
    expect(floraNeeds()['hunger'], 40);

    await chat!.continueGeneration();
    await drainTurn();
    expect(
      floraNeeds()['hunger'],
      40,
      reason: 'Continue is the same beat — no clock tax, no second wear',
    );
    expect(guestNeeds(), isEmpty);
  });
}
