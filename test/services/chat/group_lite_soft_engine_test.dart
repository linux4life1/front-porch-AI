// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Soft group speakers must not enter Realism:Unified / Needs impact,
// and their reply must not inherit a leftover needs_pre_turn_vector.
// Proven red: attach `_pendingRealismMetadata` on lite turns (old
// guestSpeaker-only gate) and GuestPoke's bubble carries Flora's vector.

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
          return Directory.systemTemp.createTempSync('fpai_lite_eng_').path;
        }
        return null;
      });
}

const _off = '{"realism_engine":{"realism_enabled":false}}';
const _lite = '{"version":"2.5","realism_engine":{"tier":"lite"}}';

class _ScriptedLlm extends LLMService {
  final List<String> kinds = [];

  void _note(String p) {
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      kinds.add('with_user');
    } else if (p.contains('relationship_delta')) {
      kinds.add('relationship');
    } else if (p.contains('needs_impact') || p.contains('report_needs')) {
      kinds.add('needs');
    } else if (p.contains('report_realism') ||
        p.contains('relationship_delta')) {
      kinds.add('realism');
    }
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    _note(p);
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": true}';
      return;
    }
    if (params.systemPrompt != null) {
      yield '*GuestPoke stays on the porch with you.*';
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
  String get backendName => 'ScriptedLiteEngine';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  ChatService? chat;
  _ScriptedLlm? llm;
  final logs = <String>[];
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
      GroupsCompanion.insert(id: 'grp-lite-eng', name: 'The Porch'),
    );
    await db!.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-flora',
        groupId: 'grp-lite-eng',
        name: 'Flora',
        firstMessage: const Value('Evening.'),
        avatarFilename: const Value('mem-flora.png'),
        frontPorchExtensions: const Value(_off),
      ),
    );
    await db!.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-guestpoke',
        groupId: 'grp-lite-eng',
        name: 'GuestPoke',
        firstMessage: const Value('Hi.'),
        avatarFilename: const Value('mem-guestpoke.png'),
        frontPorchExtensions: const Value(_lite),
      ),
    );
    await chat!.setActiveGroup(
      GroupChat(id: 'grp-lite-eng', name: 'The Porch'),
      groupRepo: GroupChatRepository(storage!, db!),
    );
    await chat!.setRealismEnabled(true);
    await chat!.setNeedsSimEnabled(true);
    chat!.debugSeedGroupSpeakerState(
      named('Flora').stableGroupId,
      needs: {
        'hunger': 40,
        'bladder': 80,
        'energy': 80,
        'social': 80,
        'fun': 80,
        'hygiene': 80,
        'comfort': 80,
      },
    );
    chat!.debugReloadFirstGroupSpeakerScalars();
  }

  setUp(() {
    logs.clear();
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    await disposeChatThenCloseDb(chat, db);
  });

  test('lite-glance log is wired after the glance pass', () {
    final src = File(
      'lib/services/chat/chat_service_generation_postgen_engine.dart',
    ).readAsStringSync();
    final pass = src.indexOf('await _runWithUserPass(scoredReply)');
    expect(pass, greaterThanOrEqualTo(0));
    final glance = src.indexOf("[Presence] lite-glance", pass);
    expect(
      glance,
      greaterThan(pass),
      reason: 'live logs must name the soft glance after the verdict',
    );
  });

  test(
    'GuestPoke soft turn skips Realism/Needs and has no needs_pre_turn_vector',
    () async {
      await boot();
      expect(named('GuestPoke').isLite, isTrue);
      chat!.setNextCharacter(named('GuestPoke'));
      await chat!.sendMessage('Say hello.');
      await drainTurn();

      expect(
        logs.where((l) => l.contains('Pre-turn eval for upcoming speaker:')),
        isEmpty,
        reason: 'soft upcoming speaker must not enter Realism:Unified',
      );
      expect(
        logs.any((l) => l.contains('[Presence] lite-glance GuestPoke=')),
        isTrue,
      );
      expect(llm!.kinds, isNot(contains('needs')));
      expect(llm!.kinds, isNot(contains('relationship')));

      final reply = chat!.messages.lastWhere((m) => !m.isUser);
      expect(reply.sender, 'GuestPoke');
      expect(
        reply.activeMetadata?.containsKey('needs_pre_turn_vector'),
        isNot(isTrue),
        reason: 'soft reply must not attach Needs pre-turn vectors',
      );
    },
  );
}
