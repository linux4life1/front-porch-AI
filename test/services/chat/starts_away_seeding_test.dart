// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Started Away at the door: a group member whose card asks to start
// arrives held in every chat the group CREATES — first open, and every
// new chat after. A restore of an existing chat never re-seeds: only
// the member's Back (or an @Name) lifts the hold, and the greeting is
// never special-cased by it (docs/design/group-initial-presence.md).

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
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
          return Directory.systemTemp.createTempSync('fpai_starts_away_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  _ScriptedLlm();

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('IN SCENE')) {
      yield '{"with_user": true}';
      return;
    }
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": false}';
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
  late GroupRealismBlobs blobs;

  Future<void> boot({bool realismDefault = true}) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': realismDefault,
      'needs_sim_default': false,
    });
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
          ..testLlmServiceOverride = _ScriptedLlm();
    await storage.initialized;
  }

  Future<void> seedGroup({
    required bool anaStartsAway,
    bool beaStartsAway = false,
    bool realismOn = true,
  }) async {
    final seed = defaultGroupMemberRealismSeed();
    blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-ana': {...seed},
        'mem-bea': {...seed},
      },
      needsEnabled: false,
      timeOfDay: 'evening',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-start',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    Future<void> member(
      String id,
      String name,
      String firstMessage, {
      required bool startsAway,
    }) => db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: id,
        groupId: 'grp-start',
        name: name,
        firstMessage: Value(firstMessage),
        frontPorchExtensions: Value(
          jsonEncode(
            FrontPorchExtensions(
              realismEnabled: realismOn,
              needsSimEnabled: false,
              chaosModeEnabled: false,
              startsAway: startsAway,
            ).toJson(),
          ),
        ),
      ),
    );
    await member('mem-ana', 'Ana', 'Evening.', startsAway: anaStartsAway);
    await member(
      'mem-bea',
      'Bea',
      'The grill is already hot.',
      startsAway: beaStartsAway,
    );
  }

  Future<void> openGroup() async {
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-start',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.timeService.setClockDirect(DateTime.utc(2026, 1, 6, 19, 30));
  }

  CharacterCard ana() =>
      chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
  CharacterCard bea() =>
      chat.groupCharacters.firstWhere((c) => c.name == 'Bea');

  /// The card field is identity: creation CONSUMES (seeds a runtime hold),
  /// it never rewrites the member row, so every later chat can seed again.
  Future<bool?> memberStartsAwayStored() async {
    final row = await db
        .customSelect(
          'SELECT front_porch_extensions FROM group_members WHERE id = ?',
          variables: [Variable('mem-ana')],
        )
        .getSingle();
    final ext = jsonDecode(row.data.values.first as String? ?? '');
    if (ext is! Map<String, dynamic>) return null;
    final engine = ext['realism_engine'];
    return engine is Map<String, dynamic>
        ? engine['startsAway'] as bool?
        : null;
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('a member who starts away arrives held at the first open', () async {
    await boot();
    await seedGroup(anaStartsAway: true, beaStartsAway: false);
    await openGroup();

    expect(chat.awayHeldForGroupCharacter(ana()), isTrue);
    expect(
      chat.withUserForGroupCharacter(ana()),
      isFalse,
      reason: 'the hold latches withUser off exactly as a hand-set Away does',
    );
    expect(
      chat.groupMemberPresence(chat.characterIdFor(ana())),
      PresenceWhere.away,
      reason: 'the seeded hold reads Away through the one derivation',
    );
    expect(chat.awayHeldForGroupCharacter(bea()), isFalse);
    expect(
      chat.groupMemberPresence(chat.characterIdFor(bea())),
      isNot(PresenceWhere.away),
    );
    expect(
      await memberStartsAwayStored(),
      isTrue,
      reason: 'seed at creation consumes the card field, never erases it',
    );
  });

  test('the greeting is not special-cased by the away seed', () async {
    await boot();
    await seedGroup(anaStartsAway: true);
    await openGroup();

    expect(chat.messages, isNotEmpty);
    expect(
      chat.messages.first.sender,
      'Ana',
      reason: 'her chat still opens on her own authored message',
    );
    expect(chat.messages.first.text, 'Evening.');
    expect(
      chat.awayHeldForGroupCharacter(ana()),
      isTrue,
      reason: 'held at the door does not swap the opener',
    );
  });

  test('restore never re-seeds: a reopened chat keeps the Back', () async {
    await boot();
    await seedGroup(anaStartsAway: true);
    await openGroup();
    expect(chat.awayHeldForGroupCharacter(ana()), isTrue);

    final anaId = chat.characterIdFor(ana());
    expect(await chat.setGroupMemberAway(anaId, away: false), isTrue);
    expect(chat.awayHeldForGroupCharacter(ana()), isFalse);

    // Re-open the group: the last session restores (messages exist), so
    // this is a restore, never a creation — the card's switch must not
    // reach through and hold her again.
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-start',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );

    expect(
      chat.awayHeldForGroupCharacter(ana()),
      isFalse,
      reason: 'only Back opens the door; a restore does not seed',
    );
    expect(chat.withUserForGroupCharacter(ana()), isTrue);
  });

  test('a new chat in the group seeds the hold again', () async {
    await boot();
    await seedGroup(anaStartsAway: true);
    await openGroup();
    final anaId = chat.characterIdFor(ana());
    expect(await chat.setGroupMemberAway(anaId, away: false), isTrue);
    expect(chat.awayHeldForGroupCharacter(ana()), isFalse);

    await chat.startNewChat();

    expect(chat.currentSessionId, isNotNull);
    expect(
      chat.awayHeldForGroupCharacter(ana()),
      isTrue,
      reason:
          'every chat creation seeds the hold: her Back held only '
          'for the chat she gave it in',
    );
    expect(chat.withUserForGroupCharacter(ana()), isFalse);
    expect(chat.awayHeldForGroupCharacter(bea()), isFalse);
  });

  test('the hold seeds even with the Realism Engine off', () async {
    await boot(realismDefault: false);
    await seedGroup(anaStartsAway: true, realismOn: false);
    await openGroup();

    expect(
      chat.awayHeldForGroupCharacter(ana()),
      isTrue,
      reason: 'the hold is the door latch, not a realism scalar',
    );
    expect(chat.withUserForGroupCharacter(ana()), isFalse);
  });
}
