// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group soft members skip Realism/Needs but still write withUser so
// Away / With you can move. Proven red: skip `_runLiteGroupGlancePass`
// and the leave-scene case stays With you (fail-open).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_lite_wu_').path;
        }
        return null;
      });
}

const _off = '{"realism_engine":{"realism_enabled":false}}';
const _lite = '{"version":"2.5","realism_engine":{"tier":"lite"}}';

class _ScriptedLlm extends LLMService {
  _ScriptedLlm({required this.softWithUser});

  final bool softWithUser;
  final List<String> kinds = [];

  void _note(String p) {
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      kinds.add('with_user');
    } else if (p.contains('relationship_delta')) {
      kinds.add('relationship');
    } else if (p.contains('needs_impact') || p.contains('hunger')) {
      kinds.add('needs');
    } else if (p.contains('"is_climax"')) {
      kinds.add('climax');
    } else if (p.contains('current physical position and stance')) {
      kinds.add('posture');
    } else if (p.contains('emotion_intensity')) {
      kinds.add('emotion');
    }
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    _note(p);
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": $softWithUser}';
      return;
    }
    if (params.systemPrompt != null) {
      yield softWithUser
          ? '*Misty stays on the porch with you.*'
          : '*Misty walks down the lane and is gone.*';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLiteGlance';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  ChatService? chat;
  _ScriptedLlm? llm;

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

  Future<void> boot({required bool softWithUser}) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm(softWithUser: softWithUser);
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
      GroupsCompanion.insert(id: 'grp-lite-wu', name: 'The Porch'),
    );
    await db!.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-full-0',
        groupId: 'grp-lite-wu',
        name: 'Flora',
        firstMessage: const Value('Evening.'),
        avatarFilename: const Value('mem-full-0.png'),
        frontPorchExtensions: const Value(_off),
      ),
    );
    await db!.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-soft-0',
        groupId: 'grp-lite-wu',
        name: 'Misty',
        firstMessage: const Value('Hi.'),
        avatarFilename: const Value('mem-soft-0.png'),
        frontPorchExtensions: const Value(_lite),
      ),
    );
    await chat!.setActiveGroup(
      GroupChat(id: 'grp-lite-wu', name: 'The Porch'),
      groupRepo: GroupChatRepository(storage!, db!),
    );
    await chat!.setRealismEnabled(true);
    await chat!.setNeedsSimEnabled(false);
  }

  CharacterCard named(String name) =>
      chat!.groupCharacters.firstWhere((c) => c.name == name);

  PresenceWhere glance(CharacterCard card) => derivePresence(
    occupation: '',
    hours: '',
    clockMinutes: 0,
    weekday: DateTime.tuesday,
    inScene: inSceneForPresence(
      stance: chat!.spatialStanceForGroupCharacter(card),
      withUser: chat!.withUserForGroupCharacter(card),
    ),
  );

  void expectNoRealismDance() {
    expect(llm!.kinds, contains('with_user'));
    expect(llm!.kinds, isNot(contains('needs')));
    expect(llm!.kinds, isNot(contains('relationship')));
    expect(llm!.kinds, isNot(contains('climax')));
    expect(llm!.kinds, isNot(contains('posture')));
    expect(llm!.kinds, isNot(contains('emotion')));
  }

  tearDown(() async {
    chat?.dispose();
    await db?.close();
  });

  test('quiet pulse includes a soft Away member', () {
    final misty = CharacterCard(
      name: 'Misty',
      frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
    );
    final flora = CharacterCard(name: 'Flora');
    final targets = AwayPulse.quietPulseTargets(
      roster: [flora, misty],
      userText: 'anyone there?',
      presenceOf: (c) =>
          c.name == 'Misty' ? PresenceWhere.away : PresenceWhere.withYou,
    );
    expect(targets.map((c) => c.name), ['Misty']);
  });

  test(
    'soft leave-scene reply sets Away without Needs/Realism dance',
    () async {
      await boot(softWithUser: false);
      chat!.debugSetGroupWithUser(named('Flora').stableGroupId, true);
      chat!.setNextCharacter(named('Misty'));
      await chat!.sendMessage('Go check the mailbox.');
      await drainTurn();

      expect(chat!.withUserForGroupCharacter(named('Misty')), isFalse);
      expect(glance(named('Misty')), PresenceWhere.away);
      expect(
        chat!.withUserForGroupCharacter(named('Flora')),
        isTrue,
        reason: 'full-member glance must not move on a soft turn',
      );
      expectNoRealismDance();
    },
  );

  test('soft stay-scene reply keeps With you', () async {
    await boot(softWithUser: true);
    chat!.setNextCharacter(named('Misty'));
    await chat!.sendMessage('Stay on the porch.');
    await drainTurn();

    expect(chat!.withUserForGroupCharacter(named('Misty')), isTrue);
    expect(glance(named('Misty')), PresenceWhere.withYou);
    expectNoRealismDance();
  });
}
