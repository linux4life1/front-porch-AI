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
import 'package:front_porch_ai/services/chat/presence_derive.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import '../../helpers/chat_db_teardown.dart';

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
  int inSceneFires = 0;
  final List<String> spoken = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    // Director Mode's scene question. Someone who just spoke in the scene,
    // or is only glanced at in it, is still there.
    if (p.contains('IN SCENE')) {
      inSceneFires++;
      yield '{"with_user": true}';
      return;
    }
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

  tearDown(() => disposeChatThenCloseDb(chat, db));

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

  test('Director Mode: a member who just spoke stays With you', () async {
    // The user directs from outside the scene. Asking "is she with the
    // user" was false for every speaker, so the whole cast went Away.
    await boot(anaQuiet: false, beaQuiet: false);
    await enterGroup(beaAtWork: false);
    for (final c in chat.groupCharacters) {
      chat.debugSetGroupWithUser(chat.characterIdFor(c), true);
    }
    chat.setObserverMode(true);

    await chat.triggerNextCharacter();
    await drainTurn();

    final last = chat.messages.last;
    expect(last.sender, isNot('System'));
    final speaker = chat.groupCharacters.firstWhere(
      (c) => c.name == last.sender,
    );
    expect(llm.inSceneFires, greaterThan(0));
    expect(
      chat.withUserForGroupCharacter(speaker),
      isTrue,
      reason: 'the glance must ask about the scene, not the absent user',
    );
  });

  test('Next with the whole cast Away glances them back', () async {
    // No user send: the pulse cadence only counts present speakers, so an
    // all-Away cast used to banner forever on Next / auto-chat.
    await boot(anaQuiet: true, beaQuiet: false);
    await enterGroup(beaAtWork: false);

    await chat.triggerNextCharacter();
    await drainTurn();

    expect(
      chat.messages.last.sender,
      'Ana',
      reason: 'all-Away must pulse on Next, not write another banner',
    );
  });

  test('the per-send return cap does not outlive its own send', () async {
    // A user send spends the one spoken return. Later Nexts are not that
    // send: an all-Away cast must still be glanced back, or Director Mode
    // (where every note is a send) piles up banners after the first note.
    await boot(anaQuiet: true, beaQuiet: false);
    await enterGroup(beaAtWork: false);
    final anaId = chat.characterIdFor(
      chat.groupCharacters.firstWhere((c) => c.name == 'Ana'),
    );

    await chat.sendMessage('Evening.');
    await drainTurn();
    expect(chat.messages.last.sender, 'Ana');

    chat.debugSetGroupWithUser(anaId, false);
    await chat.triggerNextCharacter();
    await drainTurn();

    expect(
      chat.messages.last.sender,
      'Ana',
      reason: 'a Next after the send must still bring one Away member back',
    );
  });

  test('@ or /speak of a member set Away by hand is their Back', () async {
    await boot(anaQuiet: true, beaQuiet: false);
    await enterGroup(beaAtWork: false);
    final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
    final anaId = chat.characterIdFor(ana);
    chat.debugSetGroupWithUser(
      chat.characterIdFor(
        chat.groupCharacters.firstWhere((c) => c.name == 'Bea'),
      ),
      true,
    );

    for (final line in ['@Ana you there?', '/speak Ana']) {
      expect(await chat.setGroupMemberAway(anaId, away: true), isTrue);
      await chat.sendMessage(line);
      await drainTurn();
      expect(chat.messages.last.sender, 'Ana', reason: line);
      expect(
        chat.groupMemberPresence(anaId),
        PresenceWhere.withYou,
        reason: '$line must bring a hand-set Away back, not talk from Away',
      );
    }
  });

  test(
    'manual Away beats the pulse and the glance; only Back returns',
    () async {
      await boot(anaQuiet: true, beaQuiet: false);
      await enterGroup(beaAtWork: false);
      final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
      final bea = chat.groupCharacters.firstWhere((c) => c.name == 'Bea');
      final anaId = chat.characterIdFor(ana);
      chat.debugSetGroupWithUser(anaId, true);
      chat.debugSetGroupWithUser(chat.characterIdFor(bea), true);

      expect(await chat.setGroupMemberAway(anaId, away: true), isTrue);
      expect(chat.groupMemberPresence(anaId), PresenceWhere.away);

      await chat.sendMessage('Evening.');
      await drainTurn();

      expect(
        chat.messages.last.sender,
        'Bea',
        reason: 'a hand-set Away is not pulsed back by the quiet glance',
      );
      expect(chat.withUserForGroupCharacter(ana), isFalse);

      expect(await chat.setGroupMemberAway(anaId, away: false), isTrue);
      expect(chat.groupMemberPresence(anaId), PresenceWhere.withYou);
      expect(
        await chat.setGroupMemberAway('not-in-scene', away: true),
        isFalse,
      );
    },
  );
}
