// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Away latch: quiet pulse can recover via a spoken return; @Name
// of an Away member forces a check-in; vocative without @ does not;
// mid-sentence name does not; At work is untouched; all-Away is no
// longer a permanent skip-banner dead-end.

import 'dart:convert';
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
          return Directory.systemTemp.createTempSync('fpai_away_ret_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  _ScriptedLlm({
    this.anaQuiet = false,
    this.beaQuiet = false,
    this.speak = '*She steps back onto the porch.*',
  });

  bool anaQuiet;
  bool beaQuiet;
  String speak;
  int quietFires = 0;
  int beaQuietFires = 0;
  final List<String> spoken = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      final quiet = p.contains('they have not spoken this turn');
      final forBea = p.contains('about Bea');
      final forAna = p.contains('about Ana');
      if (quiet) {
        quietFires++;
        if (forBea) beaQuietFires++;
      }
      if (forBea) {
        yield '{"with_user": ${beaQuiet ? 'true' : 'false'}}';
        return;
      }
      if (forAna) {
        yield '{"with_user": ${anaQuiet ? 'true' : 'false'}}';
        return;
      }
      yield '{"with_user": false}';
      return;
    }
    if (params.systemPrompt != null) {
      spoken.add(speak);
      yield speak;
      return;
    }
    if (p.contains('current physical position and stance')) {
      yield '{"posture": "none"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('fixation_topic')) {
      yield '{"fixation_topic":"none","proposed_objective":"none"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;
  late GroupRealismBlobs blobs;

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 400 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  CharacterCard _ext({
    required String name,
    String occupation = '',
    String hours = '',
  }) => CharacterCard(
    name: name,
    description: 'Exists only inside the away-return integration test.',
    firstMessage: 'Evening.',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: true,
      needsSimEnabled: false,
      chaosModeEnabled: false,
      occupation: occupation,
      hours: hours,
    ),
  );

  Future<void> boot({
    bool anaQuiet = true,
    bool beaQuiet = false,
    String speak = '*She steps back onto the porch.*',
  }) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm(anaQuiet: anaQuiet, beaQuiet: beaQuiet, speak: speak);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
  }

  Future<void> seedGroup({required bool beaAtWork}) async {
    final anaSeed = defaultGroupMemberRealismSeed()..['withUser'] = false;
    final beaSeed = defaultGroupMemberRealismSeed()..['withUser'] = false;
    blobs = buildGroupRealismBlobs(
      seeds: {'mem-ana': anaSeed, 'mem-bea': beaSeed},
      needsEnabled: false,
      timeOfDay: beaAtWork ? 'afternoon' : 'evening',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-away',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-ana',
        groupId: 'grp-away',
        name: 'Ana',
        firstMessage: const Value('Evening.'),
        avatarFilename: const Value('mem-ana.png'),
        frontPorchExtensions: Value(
          jsonEncode(
            FrontPorchExtensions(
              realismEnabled: true,
              needsSimEnabled: false,
              chaosModeEnabled: false,
            ).toJson(),
          ),
        ),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-bea',
        groupId: 'grp-away',
        name: 'Bea',
        firstMessage: const Value('The grill is already hot.'),
        avatarFilename: const Value('mem-bea.png'),
        frontPorchExtensions: Value(
          jsonEncode(
            FrontPorchExtensions(
              realismEnabled: true,
              needsSimEnabled: false,
              chaosModeEnabled: false,
              occupation: beaAtWork ? 'clerk' : '',
              hours: beaAtWork ? '9-5' : '',
            ).toJson(),
          ),
        ),
      ),
    );
  }

  Future<void> enterGroup({required bool beaAtWork}) async {
    await seedGroup(beaAtWork: beaAtWork);
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-away',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.timeService.setClockDirect(
      DateTime.utc(2026, 1, 6, beaAtWork ? 14 : 19, 30),
    );
    for (final c in chat.groupCharacters) {
      chat.debugSetGroupWithUser(c.stableGroupId, false);
    }
  }

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  test(
    'quiet flip schedules a spoken return instead of a skip banner',
    () async {
      await boot(anaQuiet: true);
      await enterGroup(beaAtWork: true);

      await chat.sendMessage('Evening, porch.');
      await drainTurn();

      final last = chat.messages.last;
      expect(last.sender, isNot('System'));
      expect(last.sender, 'Ana');
      expect(last.text, contains('porch'));
      expect(llm.quietFires, greaterThan(0));
      expect(
        llm.beaQuietFires,
        0,
        reason: 'At work must not be entered into the Away pulse',
      );
      expect(
        chat.withUserForGroupCharacter(
          chat.groupCharacters.firstWhere((c) => c.name == 'Bea'),
        ),
        isFalse,
        reason: 'At work must not be entered into the Away pulse',
      );
    },
  );

  test('vocative without @ does not force an Away member to speak', () async {
    await boot(anaQuiet: false);
    await enterGroup(beaAtWork: true);

    await chat.sendMessage('Ana, you coming back?');
    await drainTurn();

    expect(
      chat.messages.last.sender,
      isNot('Ana'),
      reason:
          'soft address: vocative may raise quiet priority, never force speak',
    );
    expect(chat.messages.last.sender, 'System');
    expect(chat.messages.last.text.toLowerCase(), contains('away'));
  });

  test('@ of an Away member still forces a spoken check-in', () async {
    await boot(anaQuiet: false);
    await enterGroup(beaAtWork: true);

    await chat.sendMessage('@Ana you coming back?');
    await drainTurn();

    expect(
      chat.messages.last.sender,
      'Ana',
      reason: 'hard address: @Name of Away still forces this turn\'s check-in',
    );
    expect(chat.messages.last.sender, isNot('System'));
  });

  test('mid-sentence name does not force a spoken return', () async {
    await boot(anaQuiet: false);
    await enterGroup(beaAtWork: true);

    await chat.sendMessage('I told Ana about dinner.');
    await drainTurn();

    expect(chat.messages.last.sender, 'System');
    expect(chat.messages.last.text.toLowerCase(), contains('away'));
    expect(
      chat.withUserForGroupCharacter(
        chat.groupCharacters.firstWhere((c) => c.name == 'Ana'),
      ),
      isFalse,
    );
  });

  test(
    'all-Away skip after a failed pulse is not a permanent dead-end',
    () async {
      await boot(anaQuiet: false, beaQuiet: false);
      await enterGroup(beaAtWork: false);

      await chat.sendMessage('Hello?');
      await drainTurn();
      expect(chat.messages.last.sender, 'System');

      llm.anaQuiet = true;
      await chat.sendMessage('Anyone?');
      await drainTurn();

      expect(
        chat.messages.last.sender,
        'Ana',
        reason:
            'a later user send must pulse again — the skip banner is not forever',
      );
    },
  );

  test('1:1 never skips when the glance bit is Away', () async {
    await boot();
    final card = _ext(name: 'Nia')..dbId = 'char-away-11';
    await chat.setActiveCharacter(card);
    chat.relationshipService.setWithUser(false);

    await chat.sendMessage('Evening.');
    await drainTurn();

    expect(chat.messages.last.sender, 'Nia');
    expect(chat.messages.last.sender, isNot('System'));
  });

  test('empty return speak does not leave them With you', () async {
    await boot(anaQuiet: true, speak: '');
    await enterGroup(beaAtWork: true);

    await chat.sendMessage('Evening, porch.');
    await drainTurn();

    expect(
      chat.withUserForGroupCharacter(
        chat.groupCharacters.firstWhere((c) => c.name == 'Ana'),
      ),
      isFalse,
      reason: 'quiet true must not persist if they never actually spoke',
    );
  });

  test('@ of a present member wins over a quiet Away flip', () async {
    await boot(anaQuiet: true, beaQuiet: false);
    await enterGroup(beaAtWork: false);
    final bea = chat.groupCharacters.firstWhere((c) => c.name == 'Bea');
    final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
    chat.debugSetGroupWithUser(bea.stableGroupId, true);
    chat.debugSetGroupWithUser(ana.stableGroupId, false);

    await chat.sendMessage('@Bea hey — stay with me');
    await drainTurn();

    expect(
      chat.messages.last.sender,
      'Bea',
      reason:
          'HOLD 1: quiet return must not steal @ of a member who is With you',
    );
    expect(chat.messages.last.sender, isNot('Ana'));
    expect(chat.messages.last.sender, isNot('System'));
  });

  test(
    '@ return does not stick skip-banner off for the next Away turn',
    () async {
      await boot(anaQuiet: false, beaQuiet: false);
      await enterGroup(beaAtWork: false);

      await chat.sendMessage('@Ana you coming?');
      await drainTurn();
      expect(
        chat.messages.last.sender,
        'Ana',
        reason: '@ of Away still forces the spoken check-in',
      );

      await chat.triggerNextCharacter();
      await drainTurn();

      expect(
        chat.messages.last.sender,
        'System',
        reason:
            'HOLD 2: after an @ return that leaves withUser false, '
            'the next auto-play/skip path must still banner',
      );
      expect(chat.messages.last.text.toLowerCase(), contains('away'));
    },
  );
}
