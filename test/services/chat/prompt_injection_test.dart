// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the words-only prompt_injection fragment builders + the
// RealismStateInjection composer (docs/design/prompt-state-injection.md).
//
// The load-bearing invariants:
//  * NO simulation scalars in any generation-facing fragment (no x/100, no
//    points, no turn counts; the only digit allowed in the composed block is
//    the scene-time "day N").
//  * Salience gating: sated/neutral/inactive systems emit NOTHING.
//  * 1:1 ↔ group parity: ONE tension ladder for both modes (group hostility
//    regression), per-speaker hygiene-inversion selection in groups.
//  * The calm house register (no ALL-CAPS instruction walls — chaos included).
//  * Trust tier 0 folds into the bond line instead of vanishing.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/chaos_mode_service.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/author_note_builder.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/relationship_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/emotion_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/behavioral_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/time_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/weather_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/ambition_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/promise_debt_injection.dart';
import 'package:front_porch_ai/services/chat/ambition_service.dart';
import 'package:front_porch_ai/services/chat/promise_debt_service.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/nsfw_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/chaos_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/needs_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/realism_state_injection.dart';
import 'package:front_porch_ai/models/needs_impact.dart';

// ── Shared factories ────────────────────────────────────────────────────────

dynamic _mkObj(String goal, {int depth = 3, bool primary = true}) => {
  'objective': goal,
  'injectionDepth': depth,
  'isPrimary': primary,
};

List<Map<String, dynamic>> _mkTasks(
  String current, {
  List<String> completed = const [],
}) => [
  ...completed.map((c) => {'description': c, 'completed': true}),
  if (current.isNotEmpty) {'description': current, 'completed': false},
];

AuthorNoteBuilder createTestAuthorNote({List<dynamic>? activeObjectives}) {
  final objs = activeObjectives ?? [];
  return AuthorNoteBuilder(
    getActiveObjectives: () => objs,
    getPrimaryObjective: () => objs.firstWhere(
      (o) => (o['isPrimary'] ?? true) == true,
      orElse: () => null,
    ),
    tasksForObjective: (o) =>
        (o is Map ? (o['tasks'] as List<Map<String, dynamic>>?) : null) ??
        _mkTasks('step1'),
    getSecondaryObjectives: () =>
        objs.where((o) => (o['isPrimary'] ?? true) == false).toList(),
  );
}

RelationshipService createTestRelSvc({
  Map<String, Map<String, dynamic>>? groupRealism,
  bool isGroupNonObs = false,
  String speakerId = 'c1',
  List<CharacterCard> chars = const [],
  bool trackInter = true,
}) {
  final g = groupRealism ?? {};
  return RelationshipService(
    onNotify: () {},
    onSaveChat: () async {},
    getIsGroupActive: () => isGroupNonObs,
    getObserverMode: () => !isGroupNonObs,
    getGroupCharacterCount: () => chars.length,
    getShouldTrackInterCharacterRelationships: () => trackInter,
    getCurrentSpeakerIdForRealism: () => speakerId,
    getCurrentGroupMemberIds: () => chars.map((c) => c.name).toSet(),
    getOtherGroupMemberIds: (s) =>
        chars.where((c) => c.name != s).map((c) => c.name).toList(),
    getOtherGroupMemberIdToLowerName: (s) => {},
    getRecentExchangeLowerText: () => '',
    getMessageCount: () => 0,
    getIsGroupRealismActive: () => true,
    getGroupAffectionScore: (id, {defaultValue = 0}) =>
        (g[id]?['affectionScore'] as num?)?.toInt() ?? defaultValue,
    getGroupRelationshipTier: (id, {defaultValue = 0}) =>
        (g[id]?['relationshipTier'] as num?)?.toInt() ?? defaultValue,
    setGroupRelationshipTier: (id, v) {},
    getGroupLongTermTier: (id, {defaultValue = 0}) =>
        (g[id]?['longTermTier'] as num?)?.toInt() ?? defaultValue,
    setGroupLongTermTier: (id, v) {},
    getGroupSpatialStance: (id, {defaultValue = ''}) =>
        (g[id]?['spatialStance'] as String?) ?? defaultValue,
    setGroupSpatialStance: (id, v) {},
    getGroupInterCharacterRelationships: (id) =>
        (g[id]?['relationships'] as Map<String, int>?) ?? {},
    setGroupInterCharacterRelationships: (id, m) {},
    setGroupAffectionScore: (id, v) {},
    getGroupLongTermScore: (id, {defaultValue = 0}) =>
        (g[id]?['longTermScore'] as num?)?.toInt() ?? defaultValue,
    setGroupLongTermScore: (id, v) {},
    getGroupTrustLevel: (id, {defaultValue = 0}) =>
        (g[id]?['trustLevel'] as num?)?.toInt() ?? defaultValue,
    setGroupTrustLevel: (id, v) {},
    getGroupFixation: (id, {defaultValue = ''}) => defaultValue,
    setGroupFixation: (id, v) {},
    getGroupFixationLifespan: (id, {defaultValue = 0}) => defaultValue,
    setGroupFixationLifespan: (id, v) {},
  );
}

RelationshipInjection createTestRelationship({
  RelationshipService? relSvc,
  Map<String, Map<String, dynamic>>? groupRealism,
  bool realism = true,
  bool isGroupNonObs = false,
  String speakerId = 'c1',
  List<CharacterCard>? groupChars,
  CharacterCard? activeChar,
  bool trackInter = true,
}) {
  final g = groupRealism ?? {};
  final chars = groupChars ?? [];
  final svc =
      relSvc ??
      createTestRelSvc(
        groupRealism: g,
        isGroupNonObs: isGroupNonObs,
        speakerId: speakerId,
        chars: chars,
        trackInter: trackInter,
      );
  return RelationshipInjection(
    relationshipService: svc,
    getRealismEnabled: () => realism,
    getIsGroupNonObserverMode: () => isGroupNonObs,
    getCurrentSpeakerIdForRealism: () => speakerId,
    getGroupCharacters: () => chars,
    getActiveCharacter: () => activeChar,
    getShouldTrackInterCharacterRelationships: () => trackInter,
    getGroupInt: (id, key, {defaultValue = 0}) =>
        (g[id]?[key] as num?)?.toInt() ?? defaultValue,
    getCharacterIdFromCard: (c) => c.name,
    getInterCharacterRelationships: (id) =>
        (g[id]?['relationships'] as Map<String, int>?) ?? {},
  );
}

EmotionInjection createTestEmotion({
  bool realism = true,
  String emotion = '',
  String intensity = 'mild',
}) {
  return EmotionInjection(
    getRealismEnabled: () => realism,
    getCharacterEmotion: () => emotion,
    getEmotionIntensity: () => intensity,
  );
}

BehavioralInjection createTestBehavioral({
  RelationshipService? relSvc,
  bool realism = true,
}) {
  return BehavioralInjection(
    relationshipService: relSvc ?? createTestRelSvc(),
    getRealismEnabled: () => realism,
  );
}

TimeInjection createTestTime({
  String timeOfDay = 'morning',
  int dayCount = 1,
  String storyStartDate = '2026-06-30', // a Tuesday — deterministic weekday
}) {
  final time = TimeService(
    onNotify: () {},
    onSaveChat: () async {},
    onSetPendingRealismMetadata: (_, _) {},
    onPatchLastMessageRealismState: (_, _, _) {},
  )..seedFromV2OrExt(
      dayCount: dayCount,
      timeOfDay: timeOfDay,
      passageOfTimeEnabled: true,
      storyStartDate: storyStartDate,
    );
  return TimeInjection(timeService: time);
}

NsfwService createTestNsfwSvc() => NsfwService(
  getGroupInt: (_, _) => 0,
  getGroupValue: (_, _) => null,
  setGroupValue: (_, _, _) {},
);

NsfwInjection createTestNsfw({
  NsfwService? nsfwSvc,
  bool realism = true,
  CharacterCard? activeChar,
  bool isGroupNonObs = false,
  String speakerId = 'c1',
  List<CharacterCard>? groupChars,
}) {
  return NsfwInjection(
    nsfwService: nsfwSvc ?? createTestNsfwSvc(),
    getRealismEnabled: () => realism,
    getActiveCharacter: () => activeChar,
    getIsGroupNonObserverMode: () => isGroupNonObs,
    getCurrentSpeakerIdForRealism: () => speakerId,
    getGroupCharacters: () => groupChars ?? [],
    getCharacterIdFromCard: (c) => c.dbId?.toString() ?? c.name,
  );
}

ChaosInjection createTestChaos({
  ChaosModeService? chaosSvc,
  CharacterCard? activeChar,
}) {
  final c =
      chaosSvc ??
      ChaosModeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
      );
  return ChaosInjection(
    chaosModeService: c,
    getActiveCharacter: () => activeChar,
  );
}

NeedsSimulation createTestNeedsSim({
  bool realism = true,
  bool isGroupNonObs = false,
  String speakerId = '',
  Map<String, Map<String, int>>? groupNeeds,
  bool enjoys = false,
  bool needsEnabled = true,
}) {
  return NeedsSimulation(
    onNotify: () {},
    onSaveChat: () async {},
    getTimeOfDay: () => 'morning',
    getRealismEnabled: () => realism,
    getObserverMode: () => false,
    getCurrentSpeakerIdForRealism: () => speakerId,
    getIsGroupNonObserverMode: () => isGroupNonObs,
    getGroupNeeds: (id) => groupNeeds?[id] ?? {},
    setGroupNeeds: (_, _) {},
    getEnjoysLowHygiene: () => enjoys,
    getNeedsSimEnabled: () => needsEnabled,
  );
}

NeedsInjection createTestNeeds({
  NeedsSimulation? needsSvc,
  bool needsEnabled = true,
  bool realism = true,
  bool isGroupNonObs = false,
  String speakerId = 'c1',
  List<CharacterCard>? groupChars,
  bool enjoys = false,
  Map<String, Map<String, int>>? groupNeeds,
}) {
  final ne =
      needsSvc ??
      createTestNeedsSim(
        realism: realism,
        isGroupNonObs: isGroupNonObs,
        speakerId: speakerId,
        groupNeeds: groupNeeds,
        enjoys: enjoys,
        needsEnabled: needsEnabled,
      );
  return NeedsInjection(
    needsSimulation: ne,
    getNeedsSimEnabled: () => needsEnabled,
    getRealismEnabled: () => realism,
    getIsGroupNonObserverMode: () => isGroupNonObs,
    getCurrentSpeakerIdForRealism: () => speakerId,
    getGroupCharacters: () => groupChars ?? [],
    getEnjoysLowHygiene: () => enjoys,
    getGroupNeeds: (id) => groupNeeds?[id] ?? {},
    getCharacterIdFromCard: (c) => c.dbId?.toString() ?? c.name,
  );
}

/// A sated vector — every need comfortably high (all steps >= 5).
Map<String, int> satedVector() => {
  for (final k in NeedsSimulation.needKeys) k: 90,
};

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('fragment builders (words-only)', () {
    test('author_note / objective: primary + secondary with tasks', () {
      final objs = [
        _mkObj('Main quest', depth: 1),
        _mkObj('Side goal', depth: 5, primary: false),
      ];
      final b = createTestAuthorNote(activeObjectives: objs);
      final txt = b.buildObjectiveInjection();
      expect(txt, contains('PRIMARY OBJECTIVE'));
      expect(txt, contains('AUTONOMOUS GOAL'));
      expect(txt, contains('Current Task'));
    });

    test('relationship 1:1: words only — no scores, tiers, or mechanic labels',
        () {
      final svc = createTestRelSvc();
      svc.loadScalars(
        affectionScore: 250, // tier 9 → deeply attached
        longTermScore: 250, // tier 9 → unbreakable commitment
        trustLevel: 60, // tier 4 → genuinely trusts
      );
      final b = createTestRelationship(
        relSvc: svc,
        activeChar: CharacterCard(name: 'Alice'),
      );
      final rel = b.buildRelationshipInjection();
      expect(rel, contains('soulmate or life partner'));
      expect(rel, contains('deeply attached'));
      expect(rel, contains('never as generic sweetness')); // voice note
      expect(rel, isNot(contains('points')));
      expect(rel, isNot(contains('Tension is')));
      expect(RegExp(r'\d').hasMatch(rel), isFalse);

      final trust = b.buildTrustBehaviorInjection();
      expect(trust, contains('genuinely trusts'));
      expect(trust, contains('never the baseline temperament')); // tail
      expect(RegExp(r'\d').hasMatch(trust), isFalse);
    });

    test(
      'PARITY: group hostile tiers render real hostility (old group ladder '
      'collapsed everything below Warm into "neutral to slightly distant")',
      () {
        final g = {
          'Vex': {
            'relationshipTier': -6,
            'longTermTier': -4,
            // 'trust' is the REAL _groupRealism key (not 'trustLevel') — this
            // test guards the production key name.
            'trust': -85, // tier -5 → deeply distrustful
          },
        };
        final b = createTestRelationship(
          groupRealism: g,
          isGroupNonObs: true,
          speakerId: 'Vex',
          groupChars: [CharacterCard(name: 'Vex'), CharacterCard(name: 'B')],
        );
        final rel = b.buildRelationshipInjection();
        expect(rel, contains('Vex is openly antagonistic'));
        expect(rel, contains('deep-seated resentment'));
        expect(rel, isNot(contains('neutral to slightly distant')));

        // And the group trust ladder resolves from the group trustLevel.
        final trust = b.buildTrustBehaviorInjection();
        expect(trust, contains('deeply distrustful'));
      },
    );

    test('trust tier 0 folds into the bond line and the trust fragment gates '
        'off', () {
      final b = createTestRelationship(
        activeChar: CharacterCard(name: 'Alice'),
      ); // all scalars default 0
      expect(b.buildTrustBehaviorInjection(), isEmpty);
      final rel = b.buildRelationshipInjection();
      expect(rel, contains('merits of the moment'));
      expect(rel, contains('developing normally'));
    });

    test('inter-character feelings: words only, neutral entries silent', () {
      final g = {
        'c1': {
          'relationships': {'Bob': -30, 'Cara': 70, 'Dee': 2},
        },
      };
      final b = createTestRelationship(
        groupRealism: g,
        isGroupNonObs: true,
        speakerId: 'c1',
        groupChars: [
          CharacterCard(name: 'c1'),
          CharacterCard(name: 'Bob'),
          CharacterCard(name: 'Cara'),
          CharacterCard(name: 'Dee'),
        ],
      );
      final txt = b.buildInterCharacterFeelingsInjection();
      expect(txt, contains('wary and negative toward Bob'));
      expect(txt, contains('deeply fond of and protective toward Cara'));
      expect(txt, isNot(contains('Dee'))); // neutral → silent
      expect(RegExp(r'\d').hasMatch(txt), isFalse); // no (+42) deltas
    });

    test('emotion: mood line; neutral and empty are silent', () {
      expect(
        createTestEmotion(emotion: 'flustered').buildEmotionInjection(),
        contains('Mood: Flustered, mild'),
      );
      expect(
        createTestEmotion(emotion: 'neutral').buildEmotionInjection(),
        isEmpty,
      );
      expect(createTestEmotion(emotion: '').buildEmotionInjection(), isEmpty);
    });

    test('time: one line with clock, weekday, and day count', () {
      // Start Tue 2026-06-30; Day 3 = Thu 2026-07-02, evening rep = 6:30 PM.
      final t = createTestTime(timeOfDay: 'evening', dayCount: 3);
      final txt = t.buildTimeInjection();
      expect(txt, contains('It is 6:30 in the evening on Thursday, July 2nd'));
      expect(txt, contains('(day 3 of the story)'));
    });

    test('nsfw: refractory phase prose, no turn counts', () {
      final n = createTestNsfwSvc();
      n.setNsfwCooldownEnabled(true);
      n.setCooldownTurnsRemaining(5);
      n.setCooldownTurnsTotal(5);
      final b = createTestNsfw(
        nsfwSvc: n,
        activeChar: CharacterCard(name: 'Nia'),
      );
      final txt = b.buildNsfwCooldownInjection();
      expect(txt, contains('just climaxed'));
      expect(txt, isNot(contains('turns')));
      expect(RegExp(r'\d').hasMatch(txt), isFalse);
    });

    test('nsfw: neutral arousal band is silent; peak keeps the desire-meter '
        'rule', () {
      final quiet = createTestNsfwSvc();
      quiet.setNsfwCooldownEnabled(true);
      quiet.setArousalLevel(10);
      expect(
        createTestNsfw(nsfwSvc: quiet, activeChar: CharacterCard(name: 'A'))
            .buildNsfwCooldownInjection(),
        isEmpty,
      );

      final peak = createTestNsfwSvc();
      peak.setNsfwCooldownEnabled(true);
      peak.setArousalLevel(95);
      final txt = createTestNsfw(
        nsfwSvc: peak,
        activeChar: CharacterCard(name: 'Ada'),
      ).buildNsfwCooldownInjection();
      expect(txt, contains('tip over into climax'));
      expect(txt, contains('never produces an orgasm on its own'));
    });

    test('behavioral: fixation + position fragments; trust anchors deleted',
        () {
      final svc = createTestRelSvc();
      svc.loadScalars(
        affectionScore: 0,
        longTermScore: 0,
        trustLevel: 90, // would have fired old BLIND TRUST anchor
        activeFixation: 'the promise from 2 nights ago',
        fixationLifespan: 3,
        spatialStance: 'sitting on the porch steps',
      );
      final b = createTestBehavioral(relSvc: svc);
      final txt = b.buildBehavioralMechanicsInjection();
      expect(txt, contains('On the mind lately'));
      expect(txt, contains('the promise from 2 nights ago'));
      expect(txt, contains('Position: sitting on the porch steps'));
      expect(txt.toUpperCase(), isNot(contains('BLIND TRUST')));
      expect(txt.toUpperCase(), isNot(contains('MISTRUST')));
    });

    test('chaos: calm house register — no ALL-CAPS wall, event intact', () {
      final c = ChaosModeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
      );
      c.setPendingChaosInjection('A bird lands on the windowsill.');
      final b = createTestChaos(
        chaosSvc: c,
        activeChar: CharacterCard(name: 'C'),
      );
      final txt = b.buildChanceTimeInjection();
      expect(txt, contains('SCENE EVENT — CANON'));
      expect(txt, contains('A bird lands'));
      expect(txt, isNot(contains('MANDATORY')));
      expect(txt, isNot(contains('React NOW')));
      expect(txt, contains('Never mention "Chance Time"'));
      expect(c.chaosEventDelivered, isTrue);
    });
  });

  group('needs fragments (salience + parity)', () {
    test('all needs sated → completely silent', () {
      final gneeds = {'g1': satedVector()};
      final b = createTestNeeds(
        isGroupNonObs: true,
        speakerId: 'g1',
        groupChars: [CharacterCard(name: 'G1')],
        groupNeeds: gneeds,
      );
      expect(b.buildNeedsInjection(), isEmpty);
    });

    test('worst-3 cap and words-only lines', () {
      final gneeds = {
        'g1': {
          ...satedVector(),
          'hunger': 10,
          'energy': 20,
          'fun': 30,
          'comfort': 35,
        },
      };
      final b = createTestNeeds(
        isGroupNonObs: true,
        speakerId: 'g1',
        groupChars: [CharacterCard(name: 'G1')],
        groupNeeds: gneeds,
      );
      final lines = b
          .buildNeedsInjection()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines.length, 3); // cap
      expect(lines.first, startsWith('Hunger:')); // worst first
      expect(RegExp(r'\d').hasMatch(lines.join()), isFalse);
    });

    test(
      "PARITY: one member's enjoys-low-hygiene never leaks into another "
      "member's needs (regression: hygiene 88 shown catastrophic)",
      () {
        final seraphine = CharacterCard(
          name: 'Seraphine',
          frontPorchExtensions: FrontPorchExtensions(enjoysLowHygiene: false),
        );
        final iris = CharacterCard(
          name: 'Iris',
          frontPorchExtensions: FrontPorchExtensions(enjoysLowHygiene: true),
        );
        final gneeds = {
          'Seraphine': {...satedVector(), 'hygiene': 88, 'hunger': 54},
        };
        final b = createTestNeeds(
          isGroupNonObs: true,
          speakerId: 'Seraphine',
          groupChars: [seraphine, iris],
          groupNeeds: gneeds,
          enjoys: true, // the LEAKED global (Iris) — must be ignored
        );
        final txt = b.buildNeedsInjection();
        // Seraphine's 88 hygiene is sated for HER — with the words-only
        // salience gate that means NO hygiene line at all (and certainly not
        // the inverted too-clean distress text).
        expect(txt, isNot(contains('Hygiene:')));
        expect(txt.toLowerCase(), isNot(contains('scrubbed')));
        expect(txt.toLowerCase(), isNot(contains('filthy')));
      },
    );

    test(
      'enjoys-low-hygiene: HIGH hygiene renders the inverted too-clean text '
      'and ranks by effective urgency (selection fix)',
      () {
        final jenny = CharacterCard(
          name: 'Jenny',
          frontPorchExtensions: FrontPorchExtensions(enjoysLowHygiene: true),
        );
        final gneeds = {
          'Jenny': {...satedVector(), 'hygiene': 95},
        };
        final b = createTestNeeds(
          isGroupNonObs: true,
          speakerId: 'Jenny',
          groupChars: [jenny],
          groupNeeds: gneeds,
          enjoys: false, // her OWN card flag is what matters, not the global
        );
        final txt = b.buildNeedsInjection();
        // 95 inverts to a distressed step for her → the too-clean text shows
        // (a raw-value sort would have ranked 95 as her LEAST urgent need).
        expect(txt, contains('Hygiene:'));
        expect(txt.toLowerCase(), anyOf(contains('scrubbed'), contains('too')));
        expect(txt.toLowerCase(), isNot(contains('filthy')));
        expect(RegExp(r'\d').hasMatch(txt), isFalse);
      },
    );

    test('needs sim disabled → silent', () {
      expect(
        createTestNeeds(needsEnabled: false).buildNeedsInjection(),
        isEmpty,
      );
    });
  });

  group('RealismStateInjection composer', () {
    RealismStateInjection createComposer({
      required RelationshipService relSvc,
      required NsfwService nsfwSvc,
      required NeedsSimulation needsSim,
      String emotion = '',
      String timeOfDay = 'evening',
      int dayCount = 3,
      bool realism = true,
      CharacterCard? activeChar,
    }) {
      final active = activeChar ?? CharacterCard(name: 'Alice');
      return RealismStateInjection(
        relationshipInjection: createTestRelationship(
          relSvc: relSvc,
          activeChar: active,
        ),
        emotionInjection: createTestEmotion(
          emotion: emotion,
          intensity: 'moderate',
        ),
        timeInjection: createTestTime(
          timeOfDay: timeOfDay,
          dayCount: dayCount,
        ),
        // Weather off in composer tests — the fragment contributes '' and the
        // block shape stays identical to pre-weather expectations. The
        // weather-on path is covered in weather_engine_test.dart.
        weatherInjection: WeatherInjection(getWeather: () => null),
        // Ambitions off in composer tests — active char has none, so the
        // fragment contributes '' (weather-off precedent). Ambition-on paths
        // are covered in ambition_service_test.dart.
        ambitionInjection: AmbitionInjection(
          ambitionService: AmbitionService(
            journalStore: JournalStore(getDb: () => null),
            growthStore: GrowthStore(getDb: () => null),
            fireEval: (_) async => null,
            getMaxCards: () => 30,
          ),
          getSessionId: () => null,
          getActiveCharacter: () => active,
          getIsGroupNonObserverMode: () => false,
          getCurrentSpeakerIdForRealism: () => '',
          getGroupCharacters: () => const [],
          getCharacterIdFromCard: (c) => c.name,
        ),
        // Promises off in composer tests — null session → '' (ambition/weather
        // precedent). Promise-on paths live in promise_debt_service_test.dart.
        promiseDebtInjection: PromiseDebtInjection(
          promiseDebtService: PromiseDebtService(
            journalStore: JournalStore(getDb: () => null),
            fireEval: (_) async => null,
            getMaxCards: () => 30,
            applyTrustDelta: (_) {},
            applyBondDelta: (_) {},
          ),
          getSessionId: () => null,
          getActiveCharacter: () => active,
          getIsGroupNonObserverMode: () => false,
          getCurrentSpeakerIdForRealism: () => '',
          getGroupCharacters: () => const [],
          getCharacterIdFromCard: (c) => c.name,
          getUserName: () => 'Ben',
        ),
        behavioralInjection: createTestBehavioral(relSvc: relSvc),
        nsfwInjection: createTestNsfw(nsfwSvc: nsfwSvc, activeChar: active),
        needsInjection: createTestNeeds(needsSvc: needsSim),
        getRealismEnabled: () => realism,
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getGroupCharacters: () => const [],
        getActiveCharacter: () => active,
        getCharacterIdFromCard: (c) => c.name,
      );
    }

    test('INVARIANT: busy block carries no simulation scalars — the only '
        'digit is the day count', () {
      final relSvc = createTestRelSvc();
      relSvc.loadScalars(
        affectionScore: 120,
        longTermScore: 90,
        trustLevel: 55,
        activeFixation: 'the promise Ben made last night',
        fixationLifespan: 3,
        spatialStance: 'sitting beside Ben on the porch steps',
      );
      final nsfwSvc = createTestNsfwSvc();
      nsfwSvc.setNsfwCooldownEnabled(true);
      nsfwSvc.setArousalLevel(30);
      final needsSim = createTestNeedsSim();
      needsSim.initializeFresh();
      needsSim.applySceneImpact(
        NeedsImpact(deltas: {'hunger': -60, 'energy': -45}),
      );

      final composer = createComposer(
        relSvc: relSvc,
        nsfwSvc: nsfwSvc,
        needsSim: needsSim,
        emotion: 'happy',
      );
      final block = composer.buildRealismStateInjection();

      expect(block, startsWith('[How Alice is right now:'));
      expect(block, contains('never quote meters'));
      expect(block, contains('Mood: Happy'));
      expect(block, contains('Hunger:'));
      expect(block, contains('Position:'));

      // The scalar invariant. Free-text fields are masked (they may carry
      // legitimate digits); the scene-time sentence is the one allowed digit
      // carrier (clock digits and dates are normal fiction, unlike meters —
      // story-calendar.md §7).
      var masked = block
          .replaceAll(
            RegExp(r'It is .+ \(day \d+ of the story\)\.'),
            '<scene-time>',
          )
          .replaceAll('the promise Ben made last night', '<fixation>')
          .replaceAll('sitting beside Ben on the porch steps', '<stance>');
      expect(RegExp(r'\d').hasMatch(masked), isFalse,
          reason: 'simulation scalars must never reach the generation prompt');
      expect(block, isNot(contains('/100')));
      expect(block, isNot(contains('points')));
      expect(block, isNot(contains('turns remaining')));
    });

    test('quiet turn: tiny block — no mood/needs/body/voice-note lines', () {
      final needsSim = createTestNeedsSim();
      needsSim.initializeFreshWithDefaults(satedVector());
      final composer = createComposer(
        relSvc: createTestRelSvc(), // all zeros
        nsfwSvc: createTestNsfwSvc(), // cooldown disabled
        needsSim: needsSim,
        emotion: 'neutral',
        timeOfDay: 'late_morning',
        dayCount: 1,
      );
      final block = composer.buildRealismStateInjection();
      // Start Tue 2026-06-30, Day 1, late-morning rep 11:30.
      expect(block, contains('It is 11:30 in the late morning'));
      expect(block, contains('merits of the moment'));
      expect(block, isNot(contains('Mood:')));
      expect(block, isNot(contains('Hunger:')));
      expect(block, isNot(contains('Body:')));
      // Neutral tiers carry no warmth to mis-express — the voice note gates off.
      expect(block, isNot(contains('generic sweetness')));
      // Well under the ~300 token ceiling — a quiet turn stays quiet.
      // (~130 est. tokens: header + time + bond/trust-0 fold + guard.)
      expect(block.length / 4, lessThan(150));
    });

    test('realism off → empty', () {
      final composer = createComposer(
        relSvc: createTestRelSvc(),
        nsfwSvc: createTestNsfwSvc(),
        needsSim: createTestNeedsSim(),
        realism: false,
      );
      expect(composer.buildRealismStateInjection(), isEmpty);
    });

    test('fragments may carry {{user}} for the assembly-site macro resolve',
        () {
      final relSvc = createTestRelSvc();
      relSvc.loadScalars(
        affectionScore: 120,
        longTermScore: 90,
        trustLevel: 55,
      );
      final composer = createComposer(
        relSvc: relSvc,
        nsfwSvc: createTestNsfwSvc(),
        needsSim: createTestNeedsSim()..initializeFresh(),
      );
      // The composer's output is macro-resolved by chat_service_generation —
      // {{user}} present here proves the builders stayed name-agnostic.
      expect(composer.buildRealismStateInjection(), contains('{{user}}'));
    });
  });
}
