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
import 'package:front_porch_ai/services/chat/mood_effects.dart';
import 'package:front_porch_ai/services/chat/mood_physics.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/refractory.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/realism_prompt_builder.dart';
import 'package:front_porch_ai/services/chat/realism_prompt_builder/realism_prompt_fragments.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/author_note_builder.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/relationship_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/emotion_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/behavioral_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/time_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/weather_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/ambition_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/inventory_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/preferences_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/promise_debt_injection.dart';
import 'package:front_porch_ai/services/chat/ambition_service.dart';
import 'package:front_porch_ai/services/chat/objective_fixation.dart';
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
  final time =
      TimeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
        onPatchLastMessageRealismState: (_, _, _) {},
      )..seedFromV2OrExt(
        dayCount: dayCount,
        timeOfDay: timeOfDay,
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
    // 2026-10-16 (objectives that keep up): the goals block speaks in two
    // voices instead of the depth tiers ("PRIMARY OBJECTIVE", "AUTONOMOUS
    // GOAL", "Current Task"): a goal the user set is story direction, a goal
    // the character chose is what they want. Same fixture; the words changed.
    test('author_note / objective: primary + secondary with tasks', () {
      final objs = [
        _mkObj('Main quest', depth: 1),
        {
          ..._mkObj('Side goal', depth: 5, primary: false),
          'origin': 'character',
        },
      ];
      final b = createTestAuthorNote(activeObjectives: objs);
      final txt = b.buildObjectiveInjection();
      expect(txt, contains('[Story direction: Main quest. Next:'));
      expect(txt, contains('{{char}} also wants: Side goal.'));
      expect(txt, contains("What they'd do next:"));
    });

    // 2026-10-16 (objectives that keep up): a goal set aside puts nothing in
    // the prompt, and a goal that came with the card is story direction even
    // though the character "has" it.
    test(
      'author_note / objective: set aside is silent, a card goal directs',
      () {
        final objs = <dynamic>[
          {..._mkObj('Open the bakery', depth: 1), 'origin': 'card'},
          {
            ..._mkObj('Learn the fiddle', depth: 5, primary: false),
            'origin': 'character',
            'status': 'dormant',
          },
          {
            ..._mkObj('Mend the porch', depth: 5, primary: false),
            'origin': 'character',
            'tasks': _mkTasks('paint it', completed: ['buy nails']),
          },
        ];
        final txt = createTestAuthorNote(
          activeObjectives: objs,
        ).buildObjectiveInjection();
        expect(
          txt,
          contains('[Story direction: Open the bakery. Next: step1.]'),
        );
        expect(txt, isNot(contains('Learn the fiddle')));
        expect(
          txt,
          contains(
            "{{char}} also wants: Mend the porch. Already done: buy nails. "
            "What they'd do next: paint it.",
          ),
        );
      },
    );

    // 2026-10-16 (objectives that keep up part 6): a run of goals that went
    // the same way reaches the model as one line in words, after the goals,
    // and even when no goal is open right now.
    test('author_note / objective: a streak is one line after the goals', () {
      AuthorNoteBuilder note(List<dynamic> objs, String? streak) =>
          AuthorNoteBuilder(
            getActiveObjectives: () => objs,
            getPrimaryObjective: () => objs.isEmpty ? null : objs.first,
            tasksForObjective: (_) => _mkTasks('step1'),
            getSecondaryObjectives: () => const [],
            getStreakLine: () => streak,
          );
      const line = 'Lately, {{char}}\'s plans keep falling through.';
      final withGoal = note([
        {..._mkObj('Open the bakery'), 'origin': 'character'},
      ], line).buildObjectiveInjection();
      expect(
        withGoal.indexOf('[$line]'),
        greaterThan(withGoal.indexOf('Open the bakery')),
      );
      expect(note(const [], line).buildObjectiveInjection(), '[$line]\n\n');
      expect(note(const [], null).buildObjectiveInjection(), isEmpty);
    });

    // Live run 2026-10-16: steps the task writer ends with a full stop read
    // "...neighborhood.." in the prompt.
    test(
      'author_note / objective: a goal or step ending in a stop reads once',
      () {
        final txt = createTestAuthorNote(
          activeObjectives: <dynamic>[
            {
              ..._mkObj('Open the bakery.'),
              'origin': 'character',
              'tasks': _mkTasks('Bake the bread.', completed: ['Buy flour.']),
            },
          ],
        ).buildObjectiveInjection();
        expect(txt, isNot(contains('..')));
        expect(
          txt,
          contains(
            'Most of all, {{char}} wants: Open the bakery. Already done: Buy '
            "flour. What they'd do next: Bake the bread.]",
          ),
        );
      },
    );

    // Issue #551: a step three goal checks have not moved is no longer named,
    // and a goal the character keeps pushing past the user is left out.
    test('author_note / objective: a stuck step is not named; a resting goal '
        'is left out', () {
      List<Map<String, dynamic>> tasks(int checks) => [
        {'description': 'buy flour', 'completed': true},
        {
          'description': 'bake the bread',
          'completed': false,
          kStuckChecksKey: checks,
        },
      ];
      String build(int checks, {bool resting = false}) => AuthorNoteBuilder(
        getActiveObjectives: () => [_mkObj('Open the bakery')],
        getPrimaryObjective: () => {
          ..._mkObj('Open the bakery'),
          'origin': 'character',
        },
        tasksForObjective: (_) => tasks(checks),
        getSecondaryObjectives: () => const [],
        isResting: (_) => resting,
      ).buildObjectiveInjection();
      expect(build(kStuckStepChecks - 1), contains('bake the bread'));
      final stuck = build(kStuckStepChecks);
      expect(stuck, contains('Most of all, {{char}} wants: Open the bakery'));
      expect(stuck, isNot(contains('bake the bread')));
      expect(build(0, resting: true), isEmpty);
    });

    test(
      'relationship 1:1: words only — no scores, tiers, or mechanic labels',
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
      },
    );

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
          groupChars: [
            CharacterCard(name: 'Vex'),
            CharacterCard(name: 'B'),
          ],
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
      expect(
        txt,
        contains('It is currently 6:30 in the evening on Thursday, July 2nd'),
      );
      expect(txt, contains('(day 3 of the story)'));
    });

    test('nsfw: refractory phase prose, no turn counts', () {
      final n = createTestNsfwSvc();
      n.setNsfwCooldownEnabled(true);
      // 2026-10-06: the refractory counts story minutes (5 judge turns =
      // 75 min, opening turn unspoken); the body line still has no numbers.
      n.setRefractory(Refractory.fromJudgeTurns(5));
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
        createTestNsfw(
          nsfwSvc: quiet,
          activeChar: CharacterCard(name: 'A'),
        ).buildNsfwCooldownInjection(),
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

    test(
      'behavioral: fixation + position fragments; trust anchors deleted',
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
      },
    );

    test('1:1 At work narrates from work', () {
      // Old copy said "not from the porch" — product name in her world.
      final b = BehavioralInjection(
        relationshipService: createTestRelSvc(),
        getRealismEnabled: () => true,
        getOccupation: () => 'clerk',
        getHours: () => '9-5',
        getClockMinutes: () => 14 * 60 + 30,
        getIsGroup: () => false,
      );
      final txt = b.buildPositionInjection();
      expect(txt, contains('At work as a clerk'));
      expect(txt, contains('Write from there.'));
      expect(txt.toLowerCase(), isNot(contains('porch')));
      expect(txt, isNot(contains('Position:')));
    });

    test('empty occupationBrief keeps today at-work line', () {
      final b = BehavioralInjection(
        relationshipService: createTestRelSvc(),
        getRealismEnabled: () => true,
        getOccupation: () => 'clerk',
        getHours: () => '9-5',
        getOccupationBrief: () => '',
        getClockMinutes: () => 14 * 60 + 30,
        getIsGroup: () => false,
      );
      expect(
        b.buildPositionInjection(),
        'At work as a clerk. Write from there.',
      );
    });

    test('1:1 at-work prompt injects brief beside the title', () {
      const brief = 'Keeps the diner grill and the late-night register';
      final b = BehavioralInjection(
        relationshipService: createTestRelSvc(),
        getRealismEnabled: () => true,
        getOccupation: () => 'clerk',
        getHours: () => '9-5',
        getOccupationBrief: () => brief,
        getClockMinutes: () => 14 * 60 + 30,
        getIsGroup: () => false,
      );
      final txt = b.buildPositionInjection();
      expect(txt, contains('At work as a clerk.'));
      expect(txt, contains(brief));
      expect(txt, contains('Write from there.'));
      expect(txt, isNot(contains('as a clerk $brief')));
      expect(txt, isNot(contains('as a $brief')));
    });

    test('off-shift brief is identity, not workplace staging', () {
      const brief = 'Keeps the diner grill and the late-night register';
      final b = BehavioralInjection(
        relationshipService: createTestRelSvc(),
        getRealismEnabled: () => true,
        getOccupation: () => 'clerk',
        getHours: () => '9-5',
        getOccupationBrief: () => brief,
        getClockMinutes: () => 20 * 60,
        getIsGroup: () => false,
      );
      final txt = b.buildPositionInjection();
      expect(txt, contains('Works as a clerk.'));
      expect(txt, contains(brief));
      expect(txt, isNot(contains('At work')));
      expect(txt, isNot(contains('Write from there.')));
    });

    test('1:1 Away narrates from the stance', () {
      final svc = createTestRelSvc();
      svc.loadScalars(
        affectionScore: 0,
        longTermScore: 0,
        trustLevel: 0,
        spatialStance: 'She left the kitchen',
      );
      final b = BehavioralInjection(
        relationshipService: svc,
        getRealismEnabled: () => true,
        getIsGroup: () => false,
      );
      final txt = b.buildPositionInjection();
      expect(txt, contains('Away from {{user}}'));
      expect(txt, contains('left the kitchen'));
      expect(txt, contains('Write from there.'));
      expect(txt.toLowerCase(), isNot(contains('porch')));
    });

    test('group Away keeps the Position line', () {
      final svc = createTestRelSvc();
      svc.loadScalars(
        affectionScore: 0,
        longTermScore: 0,
        trustLevel: 0,
        spatialStance: 'She left the kitchen',
      );
      final b = BehavioralInjection(
        relationshipService: svc,
        getRealismEnabled: () => true,
        getIsGroup: () => true,
      );
      expect(
        b.buildPositionInjection(),
        contains('Position: She left the kitchen'),
      );
      expect(b.buildPositionInjection(), isNot(contains('Away from')));
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

    // Needs v2 (2026-10-06): every need injects from the mild band (41-55)
    // with a line that says it is not pressing; above 55 nothing is said.
    // Hunger and bladder no longer wait a band longer than the others.
    test(
      'mild needs inject their not-pressing line; quiet ones stay silent',
      () {
        final mild = createTestNeeds(
          isGroupNonObs: true,
          speakerId: 'g1',
          groupChars: [CharacterCard(name: 'G1')],
          groupNeeds: {
            'g1': {...satedVector(), 'hunger': 54, 'bladder': 50},
          },
        );
        final mildTxt = mild.buildNeedsInjection();
        expect(mildTxt, contains('Hunger: Could eat.'));
        expect(
          mildTxt,
          contains('Bladder: Could use a bathroom at some point.'),
        );

        final quiet = createTestNeeds(
          isGroupNonObs: true,
          speakerId: 'g1',
          groupChars: [CharacterCard(name: 'G1')],
          groupNeeds: {
            'g1': {...satedVector(), 'hunger': 56, 'bladder': 60},
          },
        );
        expect(quiet.buildNeedsInjection(), isEmpty);

        final biting = createTestNeeds(
          isGroupNonObs: true,
          speakerId: 'g1',
          groupChars: [CharacterCard(name: 'G1')],
          groupNeeds: {
            'g1': {...satedVector(), 'hunger': 40},
          },
        );
        final txt = biting.buildNeedsInjection();
        expect(txt, contains('Hunger: Getting hungry'));
        expect(txt, isNot(contains('Could eat.')));
      },
    );

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

    test("PARITY: one member's enjoys-low-hygiene never leaks into another "
        "member's needs (regression: hygiene 88 shown catastrophic)", () {
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
    });

    test('enjoys-low-hygiene: HIGH hygiene renders the inverted too-clean text '
        'and ranks by effective urgency (selection fix)', () {
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
    });

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
        timeInjection: createTestTime(timeOfDay: timeOfDay, dayCount: dayCount),
        // Weather off in composer tests — the fragment contributes '' and the
        // block shape stays identical to pre-weather expectations. The
        // weather-on path is covered in weather_engine_test.dart.
        weatherInjection: WeatherInjection(
          getWeather: () => null,
          getPreviousSegment: () => null,
          getUpcoming: () => null,
        ),
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
        // Preferences off in composer tests — the active char carries no
        // likes/dislikes, so the fragment contributes '' and the block shape
        // stays identical (weather/ambition precedent). Preference-on paths
        // live in preferences_injection_test.dart.
        preferencesInjection: PreferencesInjection(
          getActiveCharacter: () => active,
          getIsGroupNonObserverMode: () => false,
          getCurrentSpeakerIdForRealism: () => '',
          getGroupCharacters: () => const [],
          getCharacterIdFromCard: (c) => c.name,
          getNsfwEnabled: () => false,
        ),
        // Pockets off in composer tests — no record for the active char, so
        // the fragment contributes '' and the block shape is unchanged
        // (weather/ambition/preferences precedent). Pockets-on paths live in
        // inventory_injection_test.dart.
        inventoryInjection: InventoryInjection(
          getActiveCharacter: () => active,
          getIsGroupNonObserverMode: () => false,
          getCurrentSpeakerIdForRealism: () => '',
          getGroupCharacters: () => const [],
          getCharacterIdFromCard: (c) => c.name,
          getCurrentDay: () => 0,
          getPockets: (_) => null,
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
            RegExp(r'It is currently .+ \(day \d+ of the story\)\.'),
            '<scene-time>',
          )
          .replaceAll('the promise Ben made last night', '<fixation>')
          .replaceAll('sitting beside Ben on the porch steps', '<stance>');
      expect(
        RegExp(r'\d').hasMatch(masked),
        isFalse,
        reason: 'simulation scalars must never reach the generation prompt',
      );
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
      expect(block, contains('It is currently 11:30 in the late morning'));
      expect(block, contains('merits of the moment'));
      expect(block, isNot(contains('Mood:')));
      expect(block, isNot(contains('Hunger:')));
      expect(block, isNot(contains('Body:')));
      // Neutral tiers carry no warmth to mis-express — the voice note gates off.
      expect(block, isNot(contains('generic sweetness')));
      // Well under the ~300 token ceiling — a quiet turn stays quiet.
      // (~130 est. tokens: header + time + bond/trust-0 fold + guard.)
      // "currently" added ~3 tokens to the time line (2026-08-18).
      expect(block.length / 4, lessThan(160));
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

    test(
      'fragments may carry {{user}} for the assembly-site macro resolve',
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
      },
    );
  });

  group('mood with bite (docs/design/mood-with-bite.md)', () {
    EmotionInjection mood({
      String emotion = 'furious',
      String intensity = 'strong',
      String cause = 'he lied about the money',
      int held = 0,
    }) => EmotionInjection(
      getRealismEnabled: () => true,
      getCharacterEmotion: () => emotion,
      getEmotionIntensity: () => intensity,
      getEmotionCause: () => cause,
      getEmotionHeldTurns: () => held,
    );

    test('the mood line scales with intensity and names the cause', () {
      expect(
        mood(intensity: 'mild').buildEmotionInjection(),
        startsWith(
          'Mood: Furious, mild, since he lied about the money — it '
          'colours tone',
        ),
      );
      expect(
        mood(intensity: 'moderate').buildEmotionInjection(),
        contains(
          'Mood: Furious, moderate, because he lied about the money — '
          'it shapes what they say and do this turn.',
        ),
      );
      expect(
        mood().buildEmotionInjection(),
        contains(
          'Mood: Furious, strong, because he lied about the money — it '
          'leads this reply: they act on it before anything else.',
        ),
      );
    });

    test('the hold is said in words, never as a count', () {
      expect(mood(held: 1).buildEmotionInjection(), isNot(contains('still')));
      expect(mood(held: 3).buildEmotionInjection(), contains(', still —'));
      expect(
        mood(held: 7).buildEmotionInjection(),
        contains(', for a while now —'),
      );
      expect(
        RegExp(r'\d').hasMatch(mood(held: 7).buildEmotionInjection()),
        isFalse,
      );
    });

    test(
      'the effects line speaks at moderate and strong, in their own way',
      () {
        final strong = mood().buildEmotionInjection();
        expect(
          strong,
          contains('\nIn their own way: the grievance comes first'),
        );
        expect(strong, contains('may refuse, argue, withdraw or leave'));
        expect(
          mood(intensity: 'moderate').buildEmotionInjection(),
          contains('\nIn their own way: less patience'),
        );
        expect(
          mood(intensity: 'mild').buildEmotionInjection(),
          isNot(contains('In their own way')),
        );
        expect(
          mood(emotion: 'undone').buildEmotionInjection(),
          isNot(contains('In their own way')),
          reason: 'a word the family map does not know gets no pull',
        );
      },
    );

    test('never an instruction to comply', () {
      for (final tone in MoodTone.values) {
        final (moderate, strong) = kMoodEffectsCopy[tone]!;
        for (final copy in [moderate, strong]) {
          expect(copy, isNot(contains('must')));
          expect(copy, isNot(contains('compl')));
          expect(copy, isNot(contains('obey')));
        }
      }
    });

    test('one fragment: no blank line between the two mood lines', () {
      final text = mood().buildEmotionInjection();
      expect('\n'.allMatches(text).length, 1);
      expect(text, isNot(contains('\n\n')));
    });

    test('no cause and no hold reads like the old line; neutral is silent', () {
      expect(
        mood(cause: '', intensity: 'mild').buildEmotionInjection(),
        'Mood: Furious, mild — it colours tone and word choice.',
      );
      expect(mood(emotion: 'neutral').buildEmotionInjection(), isEmpty);
      expect(mood(emotion: '').buildEmotionInjection(), isEmpty);
    });
  });

  // Recovery overhaul PR 3: the soft ladder. Hard rungs ship unchanged; a
  // soft body gets glow → tender → warm-again (decision 6, copy pinned to
  // the mockup), and the pronoun-free contract holds for EVERY rung — whole
  // words, case-insensitive, because a bare she|he|her|his matches inside
  // "the", "other" and "there" and would fail on the shipped ladder.
  group('soft-gate ladder (PR 3)', () {
    NsfwService softSvc(Refractory r, {int? arousal}) {
      final n = createTestNsfwSvc();
      n.setNsfwCooldownEnabled(true);
      n.setRefractory(r);
      if (arousal != null) n.setArousalLevel(arousal);
      return n;
    }

    String text(Refractory r, {int? arousal}) => createTestNsfw(
      nsfwSvc: softSvc(r, arousal: arousal),
      activeChar: CharacterCard(name: 'Nia'),
    ).buildNsfwCooldownInjection();

    test('the glow rung replaces incapacity with tender overwhelm', () {
      final t = text(Refractory.tenderness([0]));
      expect(t, contains('just climaxed — trembling and flushed'));
      expect(t, contains('oversensitive in the best way'));
      expect(t, contains('a flinch that turns into pulling closer'));
      expect(t, isNot(contains('cannot respond yet')));
    });

    test('the tender rung keeps closeness and halves stimulation', () {
      final t = text(
        const Refractory(
          minutes: 10,
          total: 15,
          opened: true,
          soft: true,
          peaks: [10, 0],
        ),
      );
      expect(t, contains('still humming from it'));
      expect(t, contains('a flinch that turns into leaning in'));
      expect(t, contains('lands at half weight'));
      expect(t, isNot(contains('cannot respond yet')));
      expect(t, isNot(contains('"not yet"')));
    });

    test(
      'warm-again holds the hour after the window — arousal band or not',
      () {
        // Window gone, a peak still counted: this beat outranks even the
        // "heavily aroused" rung, so cuddle time does not snap to chasing.
        final t = text(const Refractory(soft: true, peaks: [30]), arousal: 55);
        expect(t, contains('is warm again'));
        expect(t, contains('nothing is being chased yet'));
        expect(t, isNot(contains('chasing release')));
        // Past the hour the normal ladder returns.
        expect(
          text(const Refractory(soft: true), arousal: 55),
          contains('chasing release'),
        );
      },
    );

    test('a hard body keeps its ladder while old peak stamps age out', () {
      // Mid-window soft→hard flip (path-complete §5): the body still
      // carries peak stamps, but every reader branches on the mode — the
      // soft warmth words belong to a soft body only.
      final t = text(const Refractory(peaks: [10]), arousal: 55);
      expect(t, isNot(contains('is warm again')));
      expect(t, contains('chasing release'));
    });

    test('no rung of any ladder speaks a gendered pronoun', () {
      final genders = RegExp(
        r'\b(she|her|hers|herself|he|him|his|himself)\b',
        caseSensitive: false,
      );
      final ladders = [
        text(Refractory.fromJudgeTurns(5)), // hard opening
        text(const Refractory(minutes: 50, total: 60, opened: true)), // deep
        text(const Refractory(minutes: 10, total: 60, opened: true)), // late
        text(Refractory.none, arousal: -70),
        text(Refractory.none, arousal: -30),
        text(Refractory.none, arousal: 20),
        text(Refractory.none, arousal: 55),
        text(Refractory.none, arousal: 75),
        text(Refractory.none, arousal: 95),
        text(Refractory.tenderness([0])), // glow
        text(
          const Refractory(
            minutes: 10,
            total: 15,
            opened: true,
            soft: true,
            peaks: [10, 0],
          ),
        ), // tender
        text(const Refractory(soft: true, peaks: [30])), // warm-again
      ];
      for (final t in ladders) {
        expect(t, isNotEmpty);
        expect(
          genders.hasMatch(t),
          isFalse,
          reason:
              'the ladder interpolates \$name and speaks of the body — '
              'never a gendered pronoun: $t',
        );
      }
    });

    test('the eval refractory note branches on mode — and stops lying about '
        '"just climaxed" late in a lock', () {
      final hard = RealismPromptFragments.arousalSection(
        'Nia',
        'You',
        0,
        44,
        true,
      );
      expect(
        hard,
        contains(
          'is in the post-orgasm refractory (about 45 min '
          'left)',
        ),
      );
      expect(hard, contains('(-3 to +5)'));
      expect(
        hard,
        isNot(contains('just climaxed')),
        reason:
            'the note rides every turn of a three-hour lock; "just" '
            'read wrong after the first reply',
      );
      final soft = RealismPromptFragments.arousalSection(
        'Nia',
        'You',
        70,
        12,
        true,
        refractorySoft: true,
      );
      expect(soft, contains('oversensitive after climax'));
      expect(soft, contains('desire stays up'));
      expect(soft, contains('tenderness, not rejection'));
      expect(
        soft,
        contains('(-3 to +5)'),
        reason:
            'both modes keep the '
            'gentle band',
      );
      expect(soft, isNot(contains('low desire')));
      expect(
        RealismPromptFragments.arousalSection('Nia', 'You', 30, 0, true),
        isNot(contains('NOTE')),
      );
    });
  });

  group('warmth tail (PR 4)', () {
    NsfwService tailSvc({required Refractory r, int? arousal}) {
      final n = createTestNsfwSvc();
      n.setNsfwCooldownEnabled(true);
      n.setRefractory(r);
      if (arousal != null) n.setArousalLevel(arousal);
      return n;
    }

    String tailText(Refractory r, {int? arousal}) => createTestNsfw(
      nsfwSvc: tailSvc(r: r, arousal: arousal),
      activeChar: CharacterCard(name: 'Nia'),
    ).buildNsfwCooldownInjection();

    const cleared = Refractory(tail: Refractory(minutes: 45, total: 45));

    test('the tail rung replaces neutral silence — warmth words only', () {
      final t = tailText(cleared, arousal: 10);
      expect(t, contains('still riding a warm afterglow'));
      expect(t, contains('small kindnesses land harder'));
      expect(t, contains('any desire that has come back cools slowly'));
      expect(t, isNot(contains('chasing release')));
      // The same body with no tail says nothing at 10 — the tail rung is
      // the only difference.
      expect(
        tailText(Refractory.none, arousal: 10),
        isEmpty,
        reason: 'without the seeded warmth the ladder stays silent',
      );
    });

    test('the tail yields to strong desire and to a soured body', () {
      expect(
        tailText(cleared, arousal: 55),
        contains('chasing release'),
        reason: 'a body that is genuinely hungry again speaks the real rung',
      );
      expect(
        tailText(cleared, arousal: -30),
        contains('physically closed-off'),
        reason: 'the tail never overrules aversion',
      );
      expect(
        tailText(
          const Refractory(
            minutes: 30,
            total: 60,
            opened: true,
            tail: Refractory(minutes: 45, total: 45),
          ),
          arousal: 10,
        ),
        isNot(contains('still riding a warm afterglow')),
        reason: 'the lock rung speaks while the lock runs — tail is frozen',
      );
    });

    test('the tail rung speaks for a hard body too, and says no pronoun', () {
      final t = tailText(cleared, arousal: 0);
      expect(t, contains('still riding a warm afterglow'));
      final genders = RegExp(
        r'\b(she|her|hers|herself|he|him|his|himself)\b',
        caseSensitive: false,
      );
      final rungs = [
        tailText(cleared, arousal: -5),
        tailText(cleared, arousal: 5),
        tailText(cleared, arousal: 20),
        tailText(cleared, arousal: 35),
        for (final a in [-80, -40, 10, 30, 55, 80, 100])
          tailText(
            const Refractory(
              minutes: 40,
              total: 60,
              opened: true,
              tail: Refractory(minutes: 20, total: 20),
            ),
            arousal: a,
          ),
      ];
      for (final rung in rungs) {
        expect(genders.hasMatch(rung), isFalse, reason: 'sloppy: $rung');
      }
    });

    test('the eval note holds arousal through the tail instead of cooling', () {
      final tailed = RealismPromptFragments.arousalSection(
        'Nia',
        'You',
        20,
        0,
        true,
        warmthTailMinutes: 40,
      );
      expect(tailed, contains('still riding a warm afterglow after climax'));
      expect(tailed, contains('HOLD arousal where it is (return 0)'));
      expect(
        tailed,
        isNot(contains('post-orgasm refractory')),
        reason: 'the lock note belongs to the lock, the tail note to the tail',
      );
      final plain = RealismPromptFragments.arousalSection(
        'Nia',
        'You',
        20,
        0,
        true,
      );
      expect(
        plain,
        isNot(contains('still riding a warm afterglow')),
        reason: 'no tail, no note',
      );
    });
  });

  // Recovery overhaul PR 5: the mutual opening. One variant per mode,
  // replacing the partner-facing clause only while the beat's climax
  // verdict stamped {{user}} came too — everywhere else today's copy
  // ships verbatim, and the pronoun-free contract still holds.
  group('mutual opening (PR 5)', () {
    String mutualText(
      Refractory r, {
      required bool mutual,
      String name = 'Nia',
    }) {
      final n = createTestNsfwSvc();
      n.setNsfwCooldownEnabled(true);
      n.setRefractory(r);
      return NsfwInjection(
        nsfwService: n,
        getRealismEnabled: () => true,
        getActiveCharacter: () => CharacterCard(name: name),
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => 'c1',
        getGroupCharacters: () => const [],
        getCharacterIdFromCard: (c) => c.dbId?.toString() ?? c.name,
        getMutualOpening: () => mutual,
      ).buildNsfwCooldownInjection();
    }

    test('a mutual hard opening trades isolation for shared wreck', () {
      final t = mutualText(Refractory.fromJudgeTurns(6), mutual: true);
      expect(t, contains('just climaxed — still trembling, flushed'));
      expect(t, contains('came undone together'));
      expect(t, contains('neither willing to move first'));
      expect(t, isNot(contains('If {{user}} starts something sexual again')));
      expect(
        t,
        contains('cannot be answered'),
        reason: 'the hard lock stays true even when it is shared',
      );
    });

    test('the hard opening without the stamp ships today\'s copy verbatim', () {
      expect(
        mutualText(Refractory.fromJudgeTurns(6), mutual: false),
        contains('If {{user}} starts something sexual again'),
      );
    });

    test('a mutual soft opening shares the wind-down', () {
      final t = mutualText(Refractory.tenderness([0]), mutual: true);
      expect(t, contains('oversensitive in the best way'));
      expect(t, contains('came undone together'));
      expect(t, contains('the wind-down is shared'));
      expect(t, isNot(contains('a flinch that turns into pulling closer')));
    });

    test('the soft opening without the stamp ships today\'s copy verbatim', () {
      expect(
        mutualText(Refractory.tenderness([0]), mutual: false),
        contains('a flinch that turns into pulling closer'),
      );
    });

    test('a mid-window body never speaks the mutual opening', () {
      // The stamp is opening-turn-only: past the first reply the normal
      // tender rung ships even if the closure wrongly says mutual.
      final t = mutualText(
        const Refractory(
          minutes: 10,
          total: 15,
          opened: true,
          soft: true,
          peaks: [10, 0],
        ),
        mutual: true,
      );
      expect(t, contains('still humming from it'));
      expect(t, isNot(contains('came undone together')));
    });

    test('the mutual rungs speak no gendered pronoun', () {
      final genders = RegExp(
        r'\b(she|her|hers|herself|he|him|his|himself)\b',
        caseSensitive: false,
      );
      for (final t in [
        mutualText(Refractory.fromJudgeTurns(6), mutual: true),
        mutualText(Refractory.tenderness([0]), mutual: true),
      ]) {
        expect(
          t,
          isNot(contains(genders)),
          reason:
              'the mutual rungs interpolate \$name and speak of the '
              'body — never a gendered pronoun: $t',
        );
      }
    });

    test('the refractory note colors shared wind-down only when told', () {
      final mutual = RealismPromptFragments.arousalSection(
        'Nia',
        'You',
        30,
        45,
        true,
        mutualOpening: true,
      );
      expect(mutual, contains('came undone together'));
      expect(mutual, contains('shared recovery, not distance'));
      expect(
        mutual,
        contains('(-3 to +5)'),
        reason:
            'the sentence colors how low desire reads — the band is '
            'the same law',
      );
      final plain = RealismPromptFragments.arousalSection(
        'Nia',
        'You',
        30,
        45,
        true,
      );
      expect(plain, isNot(contains('came undone together')));
      final softMutual = RealismPromptFragments.arousalSection(
        'Nia',
        'You',
        30,
        45,
        true,
        refractorySoft: true,
        mutualOpening: true,
      );
      expect(softMutual, contains('came undone together'));
      expect(softMutual, contains('oversensitive after climax'));
    });

    test('the prompt-builder chain carries the flag to the note', () {
      // The eval call sites reach the fragment through the builder —
      // silently dropping the param mid-chain must fail something.
      final p = RealismPromptBuilder.emotionalEvalPrompt(
        charName: 'Nia',
        userName: 'You',
        dossier: '',
        standing: '',
        recent: '',
        arousalEnabled: true,
        arousalLevel: 30,
        refractoryMinutesLeft: 45,
        mutualOpening: true,
      );
      expect(p, contains('came undone together'));
    });
  });

  // Recovery overhaul PR 7: the bonding surge is ONE conditional clause
  // speaking through every afterglow window (hard note, soft note, tail
  // note, bond section) — conditioned on wanted intimacy plus warmth, with
  // the duty clause (the dissociation pin) every time.
  group('the bond surge is one conditional (PR 7)', () {
    const duty =
        'if it was duty, transaction, or skill on autopilot, the body '
        'cools on schedule and the heart may not follow — a flat or '
        'dipped bond is the honest score there';

    String hardNote() => RealismPromptFragments.arousalSection(
      'Nia',
      'You',
      30,
      45,
      true,
      bondScoredHere: true,
    );
    String softNote() => RealismPromptFragments.arousalSection(
      'Nia',
      'You',
      30,
      45,
      true,
      refractorySoft: true,
      bondScoredHere: true,
    );
    String tailNote() => RealismPromptFragments.arousalSection(
      'Nia',
      'You',
      20,
      0,
      true,
      warmthTailMinutes: 40,
      bondScoredHere: true,
    );
    String bond() => RealismPromptFragments.bondSection('Nia', 'You');

    test('every window speaks the conditional', () {
      for (final (name, text) in [
        ('hard refractory note', hardNote()),
        ('soft refractory note', softNote()),
        ('warmth tail note', tailNote()),
        ('bond section', bond()),
      ]) {
        expect(
          text,
          contains(
            'If the climax was wanted and Nia holds real warmth toward '
            'You, affectionate contact during the afterglow counts more '
            'toward short-term bond',
          ),
          reason: '$name lost the surge — the copy drifted',
        );
        expect(
          text,
          contains(duty),
          reason:
              '$name lost the duty clause — the dissociation archetype '
              'must have a legal "the heart did not follow" reading',
        );
        expect(
          text,
          isNot(contains('{{user}}')),
          reason: 'judge lanes resolve no macros — $name leaks the token',
        );
        // Notes join the clause after a single space; the bond rubric
        // indents it two like its siblings. The artifact is one extra
        // space MORE than that (clause keeps no leading space itself).
        expect(
          text,
          isNot(
            contains(
              name == 'bond section' ? '   If the climax' : '  If the climax',
            ),
          ),
          reason: '$name double-spaces before the clause',
        );
      }
    });

    test('one copy: all four emit the identical sentence', () {
      // The drift pin, structural: extract the clause each surface
      // actually emitted and require byte equality. A paraphrase in any
      // one window fails here even if a loose contains() would pass.
      String? extracted;
      for (final (name, text) in [
        ('hard', hardNote()),
        ('soft', softNote()),
        ('tail', tailNote()),
        ('bond', bond()),
      ]) {
        final start = text.indexOf('If the climax was wanted');
        expect(start, greaterThan(-1), reason: '$name lacks the clause');
        final end = text.indexOf('.', start + duty.length) + 1;
        final clause = text.substring(start, end);
        extracted ??= clause;
        expect(clause, extracted, reason: '$name paraphrased the surge');
      }
    });

    test('no windows off, no clause on the bare arousal path', () {
      // The clause rides afterglow surfaces, not every arousal line: a
      // plain turn with no refractory and no tail must not read about
      // someone else's afterglow. (The bond section keeps it always —
      // it is conditional prose, inert outside a scene.)
      final bare = RealismPromptFragments.arousalSection(
        'Nia',
        'You',
        10,
        0,
        true,
      );
      expect(bare, isNot(contains('the climax was wanted')));
    });

    test('the emotional judge gets no dangling surge (review M1)', () {
      // The multi-call lane serves every local backend, and its emotional
      // judge scores emotion + arousal_delta only — bond advice on that
      // prompt has no field, and small models pour it into the number
      // that IS there. The notes carry the clause only when the same
      // prompt scores bond; the trio's advice rides bondSection instead.
      final emotional = RealismPromptBuilder.emotionalEvalPrompt(
        charName: 'Nia',
        userName: 'You',
        dossier: '',
        standing: '',
        recent: '',
        arousalEnabled: true,
        arousalLevel: 30,
        refractoryMinutesLeft: 45,
      );
      expect(emotional, isNot(contains('the climax was wanted')));
      expect(emotional, contains('post-orgasm refractory'));
      final relationship = RealismPromptFragments.bondSection('Nia', 'You');
      expect(
        relationship,
        contains('the climax was wanted'),
        reason: 'the trio must still get the surge where the field lives',
      );
    });

    test('the fused prompt speaks the surge twice — bond line + note', () {
      final fused = RealismPromptBuilder.oneShotEvalPrompt(
        charName: 'Nia',
        userName: 'You',
        dossier: '',
        standing: '',
        recent: '',
        arousalEnabled: true,
        arousalLevel: 30,
        refractoryMinutesLeft: 45,
      );
      expect(
        RegExp('the climax was wanted').allMatches(fused).length,
        2,
        reason:
            'bond section line + the refractory note, one copy each '
            '(double-emphasis is accepted cost, path-complete §2)',
      );
      expect(fused, contains(duty));
    });
  });

  // Recovery overhaul PR 8: the grey drift. Opt-in per card, stamped at
  // the first reading, and every surface it touches keeps the old copy
  // verbatim when the window is closed.
  group('grey-drift opening (PR 8)', () {
    String pcdText(
      Refractory r, {
      required bool pcd,
      bool mutual = false,
      String name = 'Nia',
    }) {
      final n = createTestNsfwSvc();
      n.setNsfwCooldownEnabled(true);
      n.setRefractory(r);
      return NsfwInjection(
        nsfwService: n,
        getRealismEnabled: () => true,
        getActiveCharacter: () => CharacterCard(name: name),
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => 'c1',
        getGroupCharacters: () => const [],
        getCharacterIdFromCard: (c) => c.dbId?.toString() ?? c.name,
        getMutualOpening: () => mutual,
        getPcdActive: () => pcd,
      ).buildNsfwCooldownInjection();
    }

    test('a grey hard opening keeps the lock truth and names the drift', () {
      final t = pcdText(Refractory.fromJudgeTurns(6), pcd: true);
      expect(t, contains('just climaxed — still trembling, flushed'));
      expect(t, contains('sudden grey drift'));
      expect(t, contains('not sad about anything, and nothing {{user}} did'));
      expect(
        t,
        contains('cannot be answered'),
        reason: 'the drift is mood — the hard lock stays a hard lock',
      );
    });

    test('a grey soft opening lets the drift pass through', () {
      final t = pcdText(Refractory.tenderness([0]), pcd: true);
      expect(t, contains('sudden grey drift'));
      expect(t, contains('closeness is still wanted'));
      expect(t, contains('passes through on its own'));
    });

    test('the grey drift outranks the mutual clause on the opening', () {
      final t = pcdText(Refractory.fromJudgeTurns(6), pcd: true, mutual: true);
      expect(t, contains('sudden grey drift'));
      expect(
        t,
        isNot(contains('came undone together')),
        reason: 'one rung per beat — the opt-in specific mood wins the slot',
      );
    });

    test('the grey drift outranks the mutual clause on the SOFT rung too', () {
      // The hard rung's ordering has a guard; a refactor that flips only
      // the soft branch's order must trip one as well.
      final t = pcdText(Refractory.tenderness([0]), pcd: true, mutual: true);
      expect(t, contains('sudden grey drift'));
      expect(t, isNot(contains('the wind-down is shared')));
    });

    test('a closed window ships the mutual and default copy untouched', () {
      expect(
        pcdText(Refractory.fromJudgeTurns(6), pcd: false, mutual: true),
        contains('came undone together'),
      );
      final plain = pcdText(Refractory.fromJudgeTurns(6), pcd: false);
      expect(plain, isNot(contains('grey drift')));
      expect(
        plain,
        contains('the body simply cannot respond yet'),
        reason: 'the PR 3 hard rung, byte for byte',
      );
    });

    test('a mid-window body never speaks the grey opening', () {
      // The rung is opening-turn-only even while the window runs — the
      // window's later turns color the EMOTION eval, not the ladder.
      final t = pcdText(
        const Refractory(
          minutes: 10,
          total: 15,
          opened: true,
          soft: true,
          peaks: [10, 0],
        ),
        pcd: true,
      );
      expect(t, contains('still humming from it'));
      expect(t, isNot(contains('grey drift')));
    });

    test('the grey rungs speak no gendered pronoun', () {
      final genders = RegExp(
        r'\b(she|her|hers|herself|he|him|his|himself)\b',
        caseSensitive: false,
      );
      for (final t in [
        pcdText(Refractory.fromJudgeTurns(6), pcd: true),
        pcdText(Refractory.tenderness([0]), pcd: true),
      ]) {
        expect(
          t,
          isNot(contains(genders)),
          reason:
              'the grey rungs interpolate \$name and speak of the '
              'body — never a gendered pronoun: $t',
        );
      }
    });

    test('the emotion note invites the grey read and pins bond untouched', () {
      final note = RealismPromptFragments.emotionSection(
        'Nia',
        const [],
        userName: 'You',
        pcdActive: true,
      );
      expect(note, contains('"wistful" or "tearful" is an honest read'));
      expect(note, contains('something unnameable after the peak'));
      expect(note, contains('NOT a reaction to You'));
      expect(
        note,
        contains('bond and trust stay exactly as they were'),
        reason:
            'the hard guard: dysphoria is weather, not a verdict on '
            'the bond — and the fused prompt must say so',
      );
      expect(
        RealismPromptFragments.emotionSection('Nia', const []),
        isNot(contains('grey')),
        reason: 'default reads are today\'s emotion rubric verbatim',
      );
    });

    test('both eval lanes carry the note only when the window is open', () {
      final emotional = RealismPromptBuilder.emotionalEvalPrompt(
        charName: 'Nia',
        userName: 'You',
        dossier: '',
        standing: '',
        recent: '',
        arousalEnabled: true,
        arousalLevel: 30,
        refractoryMinutesLeft: 45,
        pcdActive: true,
      );
      expect(emotional, contains('something unnameable after the peak'));
      expect(
        RealismPromptBuilder.emotionalEvalPrompt(
          charName: 'Nia',
          userName: 'You',
          dossier: '',
          standing: '',
          recent: '',
          arousalEnabled: true,
          arousalLevel: 30,
          refractoryMinutesLeft: 45,
        ),
        isNot(contains('unnameable after the peak')),
      );
      final fused = RealismPromptBuilder.oneShotEvalPrompt(
        charName: 'Nia',
        userName: 'You',
        dossier: '',
        standing: '',
        recent: '',
        arousalEnabled: true,
        arousalLevel: 30,
        pcdActive: true,
      );
      expect(fused, contains('bond and trust stay exactly as they were'));
      expect(
        RealismPromptBuilder.oneShotEvalPrompt(
          charName: 'Nia',
          userName: 'You',
          dossier: '',
          standing: '',
          recent: '',
          arousalEnabled: true,
          arousalLevel: 30,
        ),
        isNot(contains('unnameable after the peak')),
      );
    });
  });
}
