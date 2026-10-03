// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared harness for the Reprocess Needs "enabled needs only" pins.
// Real ChatService + in-memory drift DB + a scripted LLM that RECORDS every
// prompt (pattern: needs_sidebar_gate_mismatch_test.dart:202-233). The
// scripted model is the only fake; every assertion reads real service,
// widget, or facade output.

export 'package:front_porch_ai/models/models.dart';
export 'package:front_porch_ai/services/services.dart';

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

const kAllNeeds = [
  'hunger',
  'bladder',
  'bowels',
  'energy',
  'social',
  'fun',
  'hygiene',
  'comfort',
];

/// Every `"<need>_delta"` key the prompt asks for (quoted form only, so
/// prose like "hygiene +50" in the shared MAGNITUDE guidance is ignored).
Set<String> askedDeltaKeys(String prompt) => {
  for (final m in RegExp(r'"([a-z]+)_delta"').allMatches(prompt))
    if (kAllNeeds.contains(m.group(1))) m.group(1)!,
};

bool isReprocessPrompt(String p) => p.contains('USER CRITIQUE');

class RecordingLlm extends LLMService {
  /// Prompts of every reprocess (critique) eval, in call order.
  final List<String> reprocessPrompts = [];

  /// Prompts of every live (per-turn) needs eval, in call order.
  final List<String> liveNeedsPrompts = [];

  /// Reply for a reprocess eval. Default: a non-zero delta for all eight.
  String reprocessReply =
      '{"hunger_delta": 9, "bladder_delta": 9, "energy_delta": 9, '
      '"social_delta": 9, "fun_delta": 9, "hygiene_delta": 9, '
      '"comfort_delta": 9, "reason": "per critique"}';

  /// Reply for the live (post-send) needs eval.
  String liveNeedsReply =
      '{"hunger_delta": -5, "bladder_delta": -5, "energy_delta": -5, '
      '"social_delta": -5, "fun_delta": -5, "hygiene_delta": -5, '
      '"comfort_delta": -5, "reason": "a long walk"}';

  String mouth = '*She leans on the porch rail and stretches.*';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (isReprocessPrompt(p)) {
      reprocessPrompts.add(p);
      yield reprocessReply;
      return;
    }
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": true}';
      return;
    }
    if (p.contains('hunger_delta') || p.contains('_delta": <int>')) {
      liveNeedsPrompts.add(p);
      yield liveNeedsReply;
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":1,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    if (params.systemPrompt != null) {
      yield mouth;
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedReprocessNeeds';
}

void setupReprocessPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_rn_pins_').path;
        }
        return null;
      });
}

Future<void> drainMicrotasks([int n = 50]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

String realismJson({List<String> needsOff = const []}) => jsonEncode({
  'realism_engine': {
    'realism_enabled': true,
    'needs_sim_enabled': true,
    'passage_of_time_enabled': false,
    'needs_off': ?(needsOff.isEmpty ? null : needsOff),
    for (final n in kAllNeeds) 'needs_baseline_$n': 80,
  },
});

CharacterCard needsCard(
  String name, {
  List<String> needsOff = const [],
  String? id,
  int hungerBaseline = 80,
}) {
  final slug = name.toLowerCase();
  return CharacterCard(
    name: name,
    firstMessage: 'Evening.',
    personality: '$name is calm.',
    imagePath: '/tmp/rn-$slug.png',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: true,
      needsSimEnabled: true,
      passageOfTimeEnabled: false,
      needsOff: List<String>.of(needsOff),
      needsBaselineHunger: hungerBaseline,
      needsBaselineBladder: 80,
      needsBaselineEnergy: 80,
      needsBaselineSocial: 80,
      needsBaselineFun: 80,
      needsBaselineHygiene: 80,
      needsBaselineComfort: 80,
    ),
  )..dbId = id ?? 'rn-$slug';
}

/// One real ChatService per test.
class ReprocessHarness {
  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late ChatService chat;
  late RecordingLlm llm;
  DebugPrintCallback? _previousPrint;

  Future<void> boot({bool quiet = true}) async {
    if (quiet) {
      _previousPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
    }
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'needs_sim_default': true,
      'realism_default': true,
      'passage_of_time_default': false,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    repo = CharacterRepository(db, storage);
    llm = RecordingLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = llm;
    await storage.initialized;
  }

  Future<void> dispose() async {
    if (_previousPrint != null) debugPrint = _previousPrint!;
    chat.dispose();
    await drainMicrotasks();
    await db.close();
    await drainMicrotasks();
  }

  Future<void> settleTurn() async {
    for (
      var i = 0;
      i < 600 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    await drainMicrotasks(30);
  }

  /// 1:1 chat with [card] and one real send, so the last bot message carries
  /// a live-stamped realism_state.needs (what the chip keys off today).
  Future<int> oneToOneWithStampedReply(CharacterCard card) async {
    await chat.setActiveCharacter(card);
    await settleTurn();
    await chat.sendMessage('Long day. How are you holding up?');
    await settleTurn();
    return chat.messages.length - 1;
  }

  /// Group with two members (A = [aOff] needs off, B = [bOff]) and one
  /// real reply from each, A first then B. Returns (aIndex, bIndex).
  Future<(int, int)> groupWithTwoReplies({
    List<String> aOff = const ['social'],
    List<String> bOff = const [],
    String aName = 'Ayla',
    String bName = 'Bram',
  }) async {
    final blobs = buildGroupRealismBlobs(
      seeds: {
        'rn-mem-a': {
          ...defaultGroupMemberRealismSeed(),
          'needsOff': List<String>.of(aOff),
        },
        'rn-mem-b': {
          ...defaultGroupMemberRealismSeed(),
          'needsOff': List<String>.of(bOff),
        },
      },
      needsEnabled: true,
      timeOfDay: 'evening',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'rn-grp',
        name: 'Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (final (id, name, off) in [
      ('rn-mem-a', aName, aOff),
      ('rn-mem-b', bName, bOff),
    ]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'rn-grp',
          name: name,
          firstMessage: const Value('Evening.'),
          personality: Value('$name is calm.'),
          avatarFilename: Value('${name.toLowerCase()}.png'),
          frontPorchExtensions: Value(realismJson(needsOff: off)),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(
        id: 'rn-grp',
        name: 'Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );
    await settleTurn();
    if (!chat.needsSimEnabled) await chat.setNeedsSimEnabled(true);
    CharacterCard member(String n) =>
        chat.groupCharacters.firstWhere((c) => c.name == n);
    chat.setNextCharacter(member(aName));
    await chat.sendMessage('Ayla, how was the market?');
    await settleTurn();
    final aIndex = chat.messages.lastIndexWhere((m) => m.sender == aName);
    chat.setNextCharacter(member(bName));
    await chat.sendMessage('Bram, and you?');
    await settleTurn();
    final bIndex = chat.messages.lastIndexWhere((m) => m.sender == bName);
    return (aIndex, bIndex);
  }

  /// Canonical JSON of what the message stores for needs, so "wrote
  /// nothing" can be checked byte-for-byte.
  String storedNeedsFingerprint(int index) {
    final md = chat.messages[index].activeMetadata ?? const {};
    return jsonEncode({
      'needs_deltas': md['needs_deltas'],
      'needs_pre_impact': md['needs_pre_impact'],
      'needs_deltas_pre_reprocess': md['needs_deltas_pre_reprocess'],
      'realism_needs': (md['realism_state'] as Map?)?['needs'],
      'live_vector': chat.needsSimulation.vector,
    });
  }
}
