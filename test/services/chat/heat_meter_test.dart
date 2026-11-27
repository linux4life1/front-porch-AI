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

// Heat, a release meter beside Lust (#770, docs/design/heat-meter.md).
//
// The scripted judge below only FEEDS the code under test (a `contact` word
// in, Heat maths and rewinds out); no test here claims a model reads a scene
// right. How a real model reads contact is the live run's job.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/nsfw_injection.dart';
import 'package:front_porch_ai/services/chat/realism_evals/heat_apply.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';
import '../../helpers/refractory_judges.dart';

final Directory _root = Directory.systemTemp.createTempSync('fpai_heat_');

NsfwService _nsfw({
  Map<String, Map<String, dynamic>>? group,
  bool heatOn = true,
}) {
  final g = group ?? <String, Map<String, dynamic>>{};
  return NsfwService(
    getGroupInt: (id, k) => (g[id]?[k] as num?)?.toInt() ?? 0,
    getGroupValue: (id, k) => g[id]?[k],
    setGroupValue: (id, k, v) => (g[id] ??= {})[k] = v,
    heatOn: () => heatOn,
  );
}

String _body(NsfwService n, {String name = 'Mara'}) => NsfwInjection(
  nsfwService: n,
  getRealismEnabled: () => true,
  getActiveCharacter: () => CharacterCard(name: name),
  getIsGroupNonObserverMode: () => false,
  getCurrentSpeakerIdForRealism: () => 'c1',
  getGroupCharacters: () => const [],
  getCharacterIdFromCard: (c) => c.name,
).buildNsfwCooldownInjection();

/// The refractory judges, plus a scripted desire answer: the emotional and
/// one-shot judges answer with [arousal] and [contact] whenever the prompt
/// asks for `contact` (it does only while Afterglow runs).
class _HeatJudges extends RefractoryJudges {
  String contact = 'none';
  int arousal = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt == null && params.prompt.contains('"contact"')) {
      judgePrompts.add(params.prompt);
      yield jsonEncode({
        'relationship_delta': 0,
        'trust_delta': 0,
        'bond_reason': 'steady',
        'trust_reason': 'steady',
        'emotion': 'content',
        'emotion_intensity': 'mild',
        'emotion_cause': 'none',
        'emotion_change': 'held',
        'arousal_delta': arousal,
        'arousal_reason': 'none',
        'contact': contact,
        'proposed_objective': 'none',
        'fixation_topic': 'none',
        'reason': 'none',
      });
      return;
    }
    yield* super.generateStream(params);
  }
}

void main() {
  group('HeatMeter maths', () {
    test('one touch after a flirt-built Lust is nowhere near the edge', () {
      // The #770 scene: Lust past 80 from talk alone, then a first touch.
      final first = HeatMeter.next(
        heat: 0,
        contact: HeatContact.teasing,
        lust: 88,
        lustDelta: 5,
        hardLock: false,
      );
      expect(first, 6);
      expect(HeatMeter.tierName(first), 'Warming');
      expect(HeatMeter.bodyLine('Mara', first), contains('Do not narrate'));
    });

    test('the edge is at least four turns of the most intense contact', () {
      var heat = 0;
      for (var turn = 1; turn <= 3; turn++) {
        heat = HeatMeter.next(
          heat: heat,
          contact: HeatContact.intense,
          lust: 100,
          lustDelta: 10,
          hardLock: false,
        );
        expect(heat, lessThan(HeatMeter.edge), reason: 'turn $turn');
      }
      expect(heat, 72);
      heat = HeatMeter.next(
        heat: heat,
        contact: HeatContact.intense,
        lust: 100,
        lustDelta: 10,
        hardLock: false,
      );
      expect(heat, 96);
      expect(HeatMeter.tierName(heat), 'On the edge');
    });

    test('Lust sets the pace', () {
      int gain(int lust) => HeatMeter.next(
        heat: 0,
        contact: HeatContact.intimate,
        lust: lust,
        lustDelta: 0,
        hardLock: false,
      );
      expect(gain(10), 5); // ×0.5
      expect(gain(30), 10); // ×1
      expect(gain(50), 12); // ×1.25, floored
      expect(gain(90), 15); // ×1.5
    });

    test('an unwanted touch, a closed-off body or a hard lock add nothing', () {
      int after({int lust = 60, int lustDelta = 0, bool lock = false}) =>
          HeatMeter.next(
            heat: 30,
            contact: HeatContact.intense,
            lust: lust,
            lustDelta: lustDelta,
            hardLock: lock,
          );
      expect(after(lustDelta: -3), 30);
      expect(after(lust: -20), 30);
      expect(after(lock: true), 30);
      expect(after(), greaterThan(30));
    });

    test('no contact halves Heat, and under 5 it is gone', () {
      int cool(int heat) => HeatMeter.next(
        heat: heat,
        contact: HeatContact.none,
        lust: 80,
        lustDelta: 0,
        hardLock: false,
      );
      expect(cool(60), 30);
      expect(cool(9), 0);
    });

    test('a climax: a hard body starts over, a soft one keeps up to 50', () {
      expect(HeatMeter.afterClimax(heat: 96, soft: false), 0);
      expect(HeatMeter.afterClimax(heat: 96, soft: true), 50);
      expect(HeatMeter.afterClimax(heat: 20, soft: true), 20);
    });

    test('the judge word is read leniently', () {
      expect(HeatMeter.parseContact(null), isNull);
      expect(HeatMeter.parseContact(' '), isNull);
      expect(HeatMeter.parseContact(' Intimate '), HeatContact.intimate);
      expect(HeatMeter.parseContact('light'), HeatContact.none);
    });

    test('the bands (ruling: On the edge is 85–100)', () {
      expect(HeatMeter.tierName(0), 'Cool');
      expect(HeatMeter.tierName(19), 'Warming');
      expect(HeatMeter.tierName(39), 'Building');
      expect(HeatMeter.tierName(69), 'Climbing');
      expect(HeatMeter.tierName(84), 'Close');
      expect(HeatMeter.tierName(85), 'On the edge');
    });
  });

  group('the body line', () {
    test('peak Lust with no Heat says nothing about finishing', () {
      final n = _nsfw()
        ..setNsfwCooldownEnabled(true)
        ..setArousalLevel(95);
      final line = _body(n);
      expect(line, isNot(contains('tip over')));
      expect(line, isNot(contains('release is close')));
      expect(line, isNot(contains('release is near')));
      expect(line, isNot(contains('Heat')));
    });

    test('Heat rides after Lust and forbids the orgasm below the edge', () {
      final n = _nsfw()
        ..setNsfwCooldownEnabled(true)
        ..setArousalLevel(95)
        ..setHeatLevel(84);
      final line = _body(n);
      expect(line, startsWith('Body: Mara is at the absolute peak of desire'));
      expect(line, contains('Mara is close'));
      expect(line, isNot(contains('tip over')));
      n.setHeatLevel(30);
      expect(_body(n), contains("Do not narrate Mara's orgasm this reply"));
    });

    test('at the edge the tip-over clause speaks, without a pronoun', () {
      final n = _nsfw()
        ..setNsfwCooldownEnabled(true)
        ..setArousalLevel(10) // Lust's own line is silent here
        ..setHeatLevel(HeatMeter.edge);
      final line = _body(n);
      expect(line, contains('let Mara tip over naturally'));
      expect(line, startsWith('Body: Mara is on the edge'));
      for (var h = 1; h <= 100; h += 11) {
        expect(
          RegExp(
            r'\b(she|her|he|him|his|hers)\b',
          ).hasMatch(HeatMeter.bodyLine('Mara', h)),
          isFalse,
          reason: 'Heat $h',
        );
      }
    });
  });

  group('NsfwService carries Heat beside Lust', () {
    test('a hard lock adds nothing; a soft window still builds', () {
      final hard = _nsfw()
        ..setArousalLevel(80)
        ..setRefractory(Refractory.fromJudgeTurns(4));
      expect(hard.applyHeatContact(HeatContact.intense, lustDelta: 2), 0);
      final soft = _nsfw()
        ..setArousalLevel(80)
        ..setRefractory(Refractory.tenderness(const [0]));
      expect(soft.applyHeatContact(HeatContact.intense, lustDelta: 2), 24);
    });

    test('a climax lands Heat by the body kind', () {
      final hard = _nsfw()..setHeatLevel(96);
      hard.applyClimaxEffects(turns: 4);
      expect(hard.heatLevel, 0);
      final soft = _nsfw()
        ..setArousalLevel(90)
        ..setHeatLevel(96);
      soft.applyClimaxEffects(turns: 4, soft: true);
      expect(soft.heatLevel, 50);
    });

    test('a group member keeps their own Heat under the heat key', () {
      final store = <String, Map<String, dynamic>>{};
      final n = _nsfw(group: store)..setHeatLevel(40);
      n.saveNsfwScalarsToGroup('m1');
      expect(store['m1']![GroupRealismKeys.heat], 40);
      n.setHeatLevel(0);
      n.loadNsfwScalarsForSpeaker('m1');
      expect(n.heatLevel, 40);
    });

    test('a snapshot restores Heat; one from before Heat keeps it', () {
      final n = _nsfw()
        ..setNsfwCooldownEnabled(true)
        ..setHeatLevel(30);
      n.restoreNsfwFromRealismState({'arousalLevel': 10, 'heatLevel': 12});
      expect(n.heatLevel, 12);
      n.restoreNsfwFromRealismState({'arousalLevel': 10});
      expect(n.heatLevel, 12);
    });

    test('the judge read records what landed as heat_delta', () {
      final n = _nsfw()..setArousalLevel(50);
      final pending = <String, dynamic>{};
      applyJudgedHeat(
        n,
        '{"emotion":"warm","contact":"intimate"}',
        lustDelta: 0,
        pending: pending,
      );
      expect(pending['heat_delta'], 12);
      final none = <String, dynamic>{};
      applyJudgedHeat(n, '{"emotion":"warm"}', lustDelta: 0, pending: none);
      expect(none, isEmpty, reason: 'a missing contact moves nothing');
    });
  });

  group('the judge is asked for contact', () {
    test('both judge tools carry contact as a free string, not required', () {
      for (final tools in [kEmotionalEvalTools, kOneShotEvalTools]) {
        final params = (tools.single['function'] as Map)['parameters'] as Map;
        final contact = (params['properties'] as Map)['contact'] as Map;
        expect(contact['type'], 'string');
        expect(contact.containsKey('enum'), isFalse);
        expect(params['required'] as List, isNot(contains('contact')));
      }
    });

    test('only while Lust is scored', () {
      String emotional(bool on) => RealismPromptBuilder.emotionalEvalPrompt(
        charName: 'Mara',
        userName: 'Sam',
        dossier: '',
        standing: '',
        recent: 'Sam: hi',
        arousalEnabled: on,
        arousalLevel: 40,
      );
      String oneShot(bool on) => RealismPromptBuilder.oneShotEvalPrompt(
        charName: 'Mara',
        userName: 'Sam',
        dossier: '',
        standing: '',
        recent: 'Sam: hi',
        arousalEnabled: on,
        arousalLevel: 40,
      );
      expect(emotional(true), contains('"contact"'));
      expect(oneShot(true), contains('"contact"'));
      expect(emotional(false), isNot(contains('"contact"')));
      expect(oneShot(false), isNot(contains('"contact"')));
    });
  });

  group('in a chat', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async =>
              call.method == 'getApplicationDocumentsDirectory'
              ? _root.path
              : null,
        );

    late AppDatabase db;
    late StorageService storage;
    late ChatService chat;
    late _HeatJudges judges;
    DebugPrintCallback? previousPrint;

    Future<void> settle() async {
      for (
        var i = 0;
        i < 500 && (chat.isGenerating || chat.isSettlingTurn);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() async {
      previousPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': false,
        'needs_sim_default': false,
        'pockets_enabled': false,
        'journal_enabled': false,
      });
      db = AppDatabase.forTesting(sameIsolate: true);
      storage = StorageService();
      judges = _HeatJudges();
      chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(CharacterRepository(db, storage))
            ..setGroupChatRepository(GroupChatRepository(storage, db))
            ..testLlmServiceOverride = judges;
      await storage.initialized;
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Mara',
          description: 'Exists only inside the Heat test.',
          firstMessage: 'The porch light hums.',
          frontPorchExtensions: FrontPorchExtensions(
            afterglowEnabled: true,
            realismEnabled: true,
          ),
        )..dbId = 'char-heat-mara',
      );
    });

    tearDown(() async {
      debugPrint = previousPrint ?? debugPrint;
      await disposeChatThenCloseDb(chat, db);
    });

    test(
      'contact raises Heat, a regenerate rewinds it, a reopen keeps it',
      () async {
        chat.nsfwService.setArousalLevel(50);
        await chat.sendMessage('Evening.');
        await settle();
        judges.contact = 'intimate';
        await chat.sendMessage('Come here.');
        await settle();
        expect(chat.nsfwService.heatLevel, 12, reason: '10 × 1.25 at Lust 50');
        expect(chat.messages.last.activeMetadata?['heat_delta'], 12);

        // Same turn, judged again as no contact: the rewind must land on the
        // turn's start (0), not halve the 12 it left.
        judges.contact = 'none';
        await chat.regenerateLastMessage();
        await settle();
        expect(chat.nsfwService.heatLevel, 0);

        judges.contact = 'intense';
        await chat.regenerateLastMessage();
        await settle();
        expect(chat.nsfwService.heatLevel, 20, reason: '16 × 1.25 at Lust 50');

        final sid = chat.currentSessionId!;
        await chat.startNewChat();
        expect(
          chat.nsfwService.heatLevel,
          0,
          reason: 'a fresh chat starts cool',
        );
        await chat.loadSession(sid);
        expect(chat.nsfwService.heatLevel, 20);
      },
    );

    test('a climax counts whatever Heat reads, and resets it', () async {
      chat.nsfwService.setArousalLevel(50);
      await chat.sendMessage('Evening.');
      await settle();
      judges
        ..contact = 'teasing'
        ..climax = true;
      await chat.sendMessage('Kiss me.');
      await settle();
      final meta = chat.messages.last.activeMetadata!;
      expect(meta['climax_triggered'], isTrue);
      expect(meta['pre_climax_heat'], 5, reason: '4 × 1.25, floored');
      expect(chat.nsfwService.heatLevel, 0);
      expect(chat.nsfwService.refractoryMinutesRemaining, greaterThan(0));
    });

    test('Porch Life Classic Lust bar: no contact asked, Heat held, the old '
        'Lust line speaks', () async {
      await storage.realismSettings.setClassicLustEnabled(true);
      chat.nsfwService.setHeatLevel(30);
      chat.nsfwService.setArousalLevel(95);
      judges.contact = 'intense';
      await chat.sendMessage('Come here.');
      await settle();
      expect(chat.nsfwService.heatLevel, 30, reason: 'held, never erased');
      expect(chat.messages.last.activeMetadata?['heat_delta'], isNull);
      expect(
        judges.judgePrompts.where((p) => p.contains('"contact"')),
        isEmpty,
        reason: 'the judge is not asked about contact',
      );
      expect(judges.replyPrompts.last, contains('tip over into climax'));
      expect(judges.replyPrompts.last, isNot(contains('Do not narrate')));

      // Off again: Heat picks up from where it was held.
      await storage.realismSettings.setClassicLustEnabled(false);
      chat.nsfwService.setArousalLevel(95);
      await chat.sendMessage('Stay.');
      await settle();
      expect(chat.nsfwService.heatLevel, 54, reason: '30 + 16 × 1.5');
    });
  });

  group('Classic Lust bar (Porch Life)', () {
    test('defaults off: Heat runs', () {
      expect(_nsfw().heatOn, isTrue);
    });

    test('on: the judge read moves nothing', () {
      final n = _nsfw(heatOn: false)
        ..setArousalLevel(80)
        ..setHeatLevel(30);
      final pending = <String, dynamic>{};
      expect(
        applyJudgedHeat(
          n,
          '{"contact":"intense"}',
          lustDelta: 5,
          pending: pending,
        ),
        0,
      );
      expect(n.heatLevel, 30);
      expect(pending, isEmpty);
    });

    test('on: the pre-Heat Lust lines, and no Heat line', () {
      final n = _nsfw(heatOn: false)
        ..setNsfwCooldownEnabled(true)
        ..setArousalLevel(95)
        ..setHeatLevel(90);
      final line = _body(n);
      expect(line, contains('at the absolute peak of arousal'));
      expect(line, contains('tip over into climax'));
      expect(line, isNot(contains('on the edge')));
      n.setArousalLevel(70);
      expect(_body(n), contains('In an active sexual scene release is close'));
    });

    test('on: the judge prompts drop contact and say the old Lust line', () {
      final emotional = RealismPromptBuilder.emotionalEvalPrompt(
        charName: 'Mara',
        userName: 'Sam',
        dossier: '',
        standing: '',
        recent: 'Sam: hi',
        arousalEnabled: true,
        arousalLevel: 40,
        heatEnabled: false,
      );
      final oneShot = RealismPromptBuilder.oneShotEvalPrompt(
        charName: 'Mara',
        userName: 'Sam',
        dossier: '',
        standing: '',
        recent: 'Sam: hi',
        arousalEnabled: true,
        arousalLevel: 40,
        heatEnabled: false,
      );
      for (final p in [emotional, oneShot]) {
        expect(p, isNot(contains('"contact"')));
        expect(
          p,
          contains(
            'climax only happens during active sexual contact at high arousal',
          ),
        );
      }
    });
  });
}
