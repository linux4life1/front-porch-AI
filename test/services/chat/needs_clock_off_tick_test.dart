// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The maintainer's ruling of 2026-10-08, final: with the clock on, Needs
// work as version 2 does (the clock wears, the judge scores events); with
// the clock off, Needs work as version 1 did: the per-reply judge plus a
// behind-the-scenes tick for hunger, bathroom and energy on every reply.
// Version 2 had dropped that tick (clock off = events only), so a chat with
// Passage of Time off sat still between events. The tick goes through the
// same stamps as the clock's wear, so regen does not charge it twice and a
// delete gives it back; in a group only the speaker ticks, as version 1 did.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
import '../../helpers/chat_db_teardown.dart';
import '../../helpers/reprocess_needs_harness.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_needs_tick_').path;
        }
        return null;
      });
}

const _full = {
  'hunger': 80,
  'bladder': 80,
  'energy': 80,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

/// One reply's tick on a full body: hunger 2, bladder 3, energy 3.
const _ticked = {
  'hunger': 78,
  'bladder': 77,
  'energy': 77,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

/// Zeros from every judge, so only the tick can move a bar.
class _QuietJudgeLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": true}';
      return;
    }
    if (p.contains('hunger_delta')) {
      yield '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 0, '
          '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "none"}';
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
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 30, "new_day": false}';
      return;
    }
    if (params.systemPrompt != null) {
      yield '*Carmen leans on the rail.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'QuietJudge';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('1:1', () {
    AppDatabase? db;
    StorageService? storage;
    ChatService? chat;

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

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'needs_sim_default': true,
        'passage_of_time_default': false,
      });
      db = AppDatabase.forTesting();
      storage = StorageService();
      final repo = CharacterRepository(db!, storage!);
      chat =
          ChatService(
              KoboldService(storage!),
              UserPersonaService(db!),
              storage!,
              WorldRepository(storage!, db!),
            )
            ..setDatabase(db!)
            ..setCharacterRepository(repo)
            ..testLlmServiceOverride = _QuietJudgeLlm();
      await storage!.initialized;
      final carmen = CharacterCard(
        name: 'Carmen',
        firstMessage: 'Evening.',
        imagePath: '/tmp/carmen-needs-tick.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          needsBaselineHunger: 80,
          needsBaselineBladder: 80,
          needsBaselineEnergy: 80,
          needsBaselineSocial: 80,
          needsBaselineFun: 80,
          needsBaselineHygiene: 80,
          needsBaselineComfort: 80,
        ),
      );
      await repo.addCharacter(carmen);
      await chat!.setActiveCharacter(carmen);
      await chat!.setRealismEnabled(true);
      await chat!.setNeedsSimEnabled(true);
      chat!.needsSimulation.restoreFromSnapshot({'vector': _full});
      await drainTurn();
    });

    tearDown(() => disposeChatThenCloseDb(chat, db));

    Map<String, int> bars() =>
        Map<String, int>.from(chat!.needsSimulation.vector);

    ChatMessage lastBot() => chat!.messages.lastWhere((m) => !m.isUser);

    test('clock off: a reply ticks hunger, bladder and energy, and the chip '
        'says so', () async {
      await chat!.sendMessage('Evening, Carmen.');
      await drainTurn();
      expect(bars(), _ticked, reason: 'the judge gave zeros: the tick alone');
      final meta = lastBot().activeMetadata ?? const {};
      expect(meta.containsKey('time_passed'), isFalse, reason: 'no clock');
      final deltas = meta['needs_deltas'] as Map?;
      expect(deltas?.keys.toSet(), {'hunger', 'bladder', 'energy'});
      expect((deltas?['bladder'] as Map?)?['delta'], -3);
      expect((deltas?['bladder'] as Map?)?['reason'], 'Natural decay');
    });

    test('clock off: a regen charges the tick once, not twice', () async {
      await chat!.sendMessage('Evening, Carmen.');
      await drainTurn();
      expect(bars(), _ticked);
      await chat!.regenerateLastMessage();
      await drainTurn();
      expect(bars(), _ticked, reason: 'rewound to the stamp, then ticked');
    });

    test('clock off: a second reply ticks again, from where the first '
        'left the body', () async {
      await chat!.sendMessage('Evening, Carmen.');
      await drainTurn();
      await chat!.sendMessage('Still there?');
      await drainTurn();
      expect(bars()['hunger'], 76);
      expect(bars()['bladder'], 74);
      expect(bars()['energy'], 74);
      expect(bars()['social'], 80, reason: 'the other four are events only');
    });

    test('clock on: the tick is not added on top of the clock', () async {
      await storage!.realismSettings.setPassageOfTimeDefault(true);
      await chat!.sendMessage('Evening, Carmen.');
      await drainTurn();
      expect(lastBot().activeMetadata?['time_passed'], '30 min');
      expect(
        bars()['bladder'],
        73,
        reason: '15 an hour for 30 min, and no tick',
      );
      expect(bars()['hunger'], 77, reason: '6 an hour for 30 min');
      expect(bars()['energy'], 78, reason: '5 an hour for 30 min, rounded');
    });
  });

  group('group', () {
    setupReprocessPathProviderMock();
    late ReprocessHarness h;
    setUp(() async {
      h = ReprocessHarness();
      await h.boot();
    });
    tearDown(() => h.dispose());

    test('clock off: each reply ticks its own speaker, not the room', () async {
      // The harness boots with the clock off and a judge that moves every
      // need by 5 on each reply; the tick shows as the extra 2 / 3 / 3 on
      // the speaker alone. Ayla has social off; Bram has every need on.
      final seed = Map<String, int>.from(
        defaultGroupMemberRealismSeed()['needs'] as Map,
      );
      final (a, b) = await h.groupWithTwoReplies();
      final cardA = h.chat.groupCharacters.firstWhere((c) => c.name == 'Ayla');
      final cardB = h.chat.groupCharacters.firstWhere((c) => c.name == 'Bram');
      final needsA = h.chat.getNeedsForGroupCharacter(cardA);
      final needsB = h.chat.getNeedsForGroupCharacter(cardB);
      expect(a, lessThan(b));
      for (final needs in [needsA, needsB]) {
        expect(needs['hunger'], seed['hunger']! - 5 - 2);
        expect(needs['bladder'], seed['bladder']! - 5 - 3);
        expect(needs['energy'], seed['energy']! - 5 - 3);
        expect(needs['fun'], seed['fun']! - 5, reason: 'fun is events only');
      }
      expect(needsA['social'], seed['social'], reason: "Ayla's social is off");
      expect(needsB['social'], seed['social']! - 5);
      // Each stamp names its own speaker only: the room did not tick.
      expect(
        (h.chat.messages[a].activeMetadata?['needs_worn_by_member'] as Map?)
            ?.keys
            .toList(),
        ['rn-mem-a'],
      );
      expect(
        (h.chat.messages[b].activeMetadata?['needs_worn_by_member'] as Map?)
            ?.keys
            .toList(),
        ['rn-mem-b'],
      );
    });
  });
}
