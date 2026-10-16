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

// Phase 2 test gate, item 4: one-shot must be equivalent to the four-call path.
//
// This is the project's strictest written rule — CLAUDE.md says the one-shot
// evaluation "must produce 1:1 equivalent outputs for Bond/Trust/Emotion/
// Arousal/Fixation/Spatial Stance/Time/Needs" because it exists purely as a
// token/latency optimisation and must not change observable behaviour.
//
// Nothing tested it. The audit went looking and found the test literally named
// for this rule asserting `expect(true, true)`.
//
// The divergence that mattered: when an evaluation FAILS — backend down, empty
// reply, timeout — the four-call path still advances the story clock by
// StoryClock.failureDriftMinutes ("deterministic drift so time never freezes",
// in its own words), while one-shot returned early over a hundred lines before
// its clock call and left time frozen for the whole turn. A user on one-shot
// whose backend hiccupped got a story that silently stopped advancing.
//
// Both paths are driven here through their real public entry points on
// RealismEvals, over real RelationshipService / NsfwService / TimeService
// instances, with only the LLM call faked.
//
// SCOPE, stated plainly so this file is not mistaken for more than it is: it
// closes ONE divergence — the early return on a null reply. Other failure
// shapes (a thrown transport error, a mid-call cancel, the tools transport, the
// group per-speaker path) are not compared here. And because both paths are fed
// the same canned reply, the success group proves the APPLY layer parses and
// applies identically; it cannot prove two different prompts would draw
// equivalent answers from a real model. That is not testable without a model.
//
// The rule also names Needs, which this file does not cover — needs are
// applied by NeedsImpactEvaluator in the post-generation pass, not by either of
// these two evaluation paths, so there is nothing here to compare. Everything
// else the rule names (bond, trust, emotion, intensity, arousal, fixation,
// spatial stance, clock) is compared field by field.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/realism_evals.dart';
import 'package:front_porch_ai/services/chat/realism_prompt_builder.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';

/// One evaluation subject: the three services whose state the evals mutate,
/// plus the RealismEvals wired over them.
class _Rig {
  _Rig(this.reply) {
    rel = RelationshipService(
      onNotify: () {},
      onSaveChat: () async {},
      getIsGroupActive: () => false,
      getObserverMode: () => false,
      getGroupCharacterCount: () => 0,
      getShouldTrackInterCharacterRelationships: () => false,
      getCurrentSpeakerIdForRealism: () => '',
      getCurrentGroupMemberIds: () => const {},
      getOtherGroupMemberIds: (_) => const [],
      getOtherGroupMemberIdToLowerName: (_) => const {},
      getRecentExchangeLowerText: () => '',
      getMessageCount: () => 0,
      getIsGroupRealismActive: () => false,
      getGroupAffectionScore: (id, {int defaultValue = 0}) => defaultValue,
      setGroupAffectionScore: (_, _) {},
      getGroupLongTermScore: (id, {int defaultValue = 0}) => defaultValue,
      setGroupLongTermScore: (_, _) {},
      getGroupTrustLevel: (id, {int defaultValue = 0}) => defaultValue,
      setGroupTrustLevel: (_, _) {},
      getGroupFixation: (id, {String defaultValue = ''}) => defaultValue,
      setGroupFixation: (_, _) {},
      getGroupFixationLifespan: (id, {int defaultValue = 0}) => defaultValue,
      setGroupFixationLifespan: (_, _) {},
      getGroupRelationshipTier: (id, {int defaultValue = 0}) => defaultValue,
      setGroupRelationshipTier: (_, _) {},
      getGroupLongTermTier: (id, {int defaultValue = 0}) => defaultValue,
      setGroupLongTermTier: (_, _) {},
      getGroupSpatialStance: (id, {String defaultValue = ''}) => defaultValue,
      setGroupSpatialStance: (_, _) {},
      getGroupInterCharacterRelationships: (_) => const <String, int>{},
      setGroupInterCharacterRelationships: (_, _) {},
    );
    nsfw = NsfwService(
      getGroupInt: (_, _) => 0,
      getGroupValue: (_, _) => null,
      setGroupValue: (_, _, _) {},
    );
    time = TimeService(
      onNotify: () {},
      onSaveChat: () async {},
      onSetPendingRealismMetadata: (k, v) {},
      onPatchLastMessageRealismState: (tod, dc, iso) {},
    );

    evals = RealismEvals(
      // The ONLY fake: every eval in both paths gets the same answer.
      fireLLMEval: (p, {onChunk}) async {
        firedPrompts.add(p);
        return reply;
      },
      // Force the text transport so both paths take identical routes.
      fireToolEval: (p, t) async => null,
      probe: ToolTransportProbe(),
      getBackendIdentity: () => 'test-backend',
      isEvalCancelled: () => false,
      stripThinkBlocks: (t) => t,
      extractJsonInt: (t, k) {
        final m = RegExp('"$k"\\s*:\\s*(-?\\d+)').firstMatch(t);
        return m == null ? null : int.tryParse(m.group(1)!);
      },
      extractJsonBool: (t, k) {
        final m = RegExp('"$k"\\s*:\\s*(true|false)').firstMatch(t);
        return m == null ? null : m.group(1) == 'true';
      },
      getActiveCharacter: () => _char,
      getActiveGroup: () => null,
      getIsObserverMode: () => false,
      getUserName: () => 'User',
      getRealismEnabled: () => true,
      getMessages: () => _messages,
      getPendingRealismMetadata: () => _pending,
      setPendingRealismMetadata: (v) => _pending = v ?? {},
      captureRealismState: ({Map<String, int>? preTurn}) => {},
      getCharacterEmotion: () => emotion,
      setCharacterEmotion: (v) => emotion = v,
      getEmotionIntensity: () => intensity,
      setEmotionIntensity: (v) => intensity = v,
      relationshipService: rel,
      nsfwService: nsfw,
      timeService: time,
      getExpressionEnabled: () => false,
      getCharacterDossier: (card) => RealismPromptBuilder.characterDossier(
        name: card.name,
        personality: card.personality,
        description: card.description,
      ),
      getPrimaryObjective: () => null,
      getActiveObjectives: () => const <Objective>[],
      setObjective:
          (
            t, {
            isPrimary = false,
            autoGenerateTasks = false,
            servedAmbition,
          }) async {},
    );
  }

  /// null models a failed evaluation (backend down / empty reply / timeout).
  final String? reply;

  late final RelationshipService rel;
  late final NsfwService nsfw;
  late final TimeService time;
  late final RealismEvals evals;

  final List<String> firedPrompts = [];
  String emotion = '';
  String intensity = '';
  Map<String, dynamic> _pending = {};

  final _char = CharacterCard(name: 'Aerin', personality: 'warm');
  final _messages = <ChatMessage>[
    ChatMessage(text: 'hello there', isUser: true, sender: 'User'),
    ChatMessage(text: 'hello yourself', isUser: false, sender: 'Aerin'),
  ];

  /// Everything the rule says the two paths must agree on.
  Map<String, Object?> observable() => {
    'bond': rel.affectionScore,
    'trust': rel.trustLevel,
    'fixation': rel.activeFixation,
    'stance': rel.spatialStance,
    'emotion': emotion,
    'intensity': intensity,
    'arousal': nsfw.arousalLevel,
    'clockMinutes': time.clock.difference(_epoch).inMinutes,
    'dayCount': time.dayCount,
  };

  static final _epoch = DateTime(2000);

  Future<void> runFourCall() async {
    await evals.evaluateRelationshipCall();
    await evals.evaluateEmotionalStateCall();
    await evals.evaluateNarrativeCall();
  }

  Future<void> runOneShot() => evals.evaluateOneShotCall();
}

void main() {
  group('one-shot vs four-call: the failure case', () {
    test(
      'pre-generation judges must not move the story clock on either path',
      () async {
        // Clock decide is post-generation now. A failed (or successful)
        // judge pass that still nudged the clock would jump At work / Today
        // before she writes.
        final four = _Rig(null);
        final before = four.time.clock;
        await four.runFourCall();
        final fourAdvanced = four.time.clock.difference(before).inMinutes;

        final one = _Rig(null);
        final oneBefore = one.time.clock;
        await one.runOneShot();
        final oneAdvanced = one.time.clock.difference(oneBefore).inMinutes;

        expect(fourAdvanced, 0);
        expect(
          oneAdvanced,
          fourAdvanced,
          reason:
              'one-shot exists only to save tokens. The judges must leave '
              'the clock exactly where the three-call path would have.',
        );

        // The drift must come from oneShotMode's clock-math branch, NOT from
        // TimeService firing its own scene-time evaluation. Without this, passing
        // oneShotMode:false would still produce the right clock (that eval would
        // fail too and drift identically) while silently costing the extra call
        // the whole optimisation exists to avoid — the clock assertion above
        // would stay green through that regression.
        expect(
          one.firedPrompts.length,
          1,
          reason:
              'the recovery must not fire a second LLM call; only the original '
              'fused evaluation should appear',
        );
      },
    );

    test(
      'neither path invents relationship movement out of a failure',
      () async {
        final four = _Rig(null);
        await four.runFourCall();
        final one = _Rig(null);
        await one.runOneShot();

        expect(four.rel.affectionScore, 0);
        expect(one.rel.affectionScore, 0);
        expect(four.rel.trustLevel, 0);
        expect(one.rel.trustLevel, 0);
        expect(four.nsfw.arousalLevel, 0);
        expect(one.nsfw.arousalLevel, 0);
      },
    );
  });

  group('one-shot vs four-call: the success case', () {
    const reply =
        '{"relationship_delta":12,"trust_delta":-7,"bond_reason":"warmth",'
        '"trust_reason":"a slip","emotion":"joy","emotion_intensity":"strong",'
        '"arousal_delta":15,"posture":"close","fixation_topic":"her laugh",'
        '"proposed_objective":"none","minutes_elapsed":25,"new_day":false,'
        '"reason":"scene"}';

    test('identical input produces identical observable state', () async {
      final four = _Rig(reply);
      await four.runFourCall();

      final one = _Rig(reply);
      await one.runOneShot();

      final a = four.observable();
      final b = one.observable();
      for (final key in a.keys) {
        expect(
          b[key],
          a[key],
          reason:
              '"$key" diverges between the two paths — one-shot is a token '
              'optimisation and must not change what the user sees. '
              'fourCall=${a[key]} oneShot=${b[key]}',
        );
      }
    });

    test('one-shot really is one call, and the judge path is three', () async {
      // Guards the whole point of the optimisation: if one-shot ever started
      // firing extra evaluations it would still pass the equivalence test above
      // while quietly costing what it was built to save.
      final one = _Rig(reply);
      await one.runOneShot();
      expect(one.firedPrompts.length, 1);

      final four = _Rig(reply);
      await four.runFourCall();
      expect(
        four.firedPrompts.length,
        3,
        reason:
            'relationship, emotional and narrative. Scene-time is '
            'post-generation now. greaterThan(1) would let the path '
            'silently degrade to two.',
      );
    });

    // Mood with bite (docs/design/mood-with-bite.md): the judge's answer is
    // applied to the mood going in through ONE rule. Both paths must land on
    // the same label and intensity, or one-shot would be the only mode
    // whose feelings never hold.
    const stoked =
        '{"relationship_delta":0,"trust_delta":0,"bond_reason":"none",'
        '"trust_reason":"none","emotion":"furious","emotion_intensity":"moderate",'
        '"emotion_cause":"and now he denies it","emotion_change":"stoked",'
        '"fixation_topic":"none","proposed_objective":"none",'
        '"minutes_elapsed":5,"new_day":false,"reason":"scene"}';

    test('a stoked feeling keeps its label on both paths', () async {
      final four = _Rig(stoked)
        ..emotion = 'furious'
        ..intensity = 'strong';
      await four.runFourCall();
      final one = _Rig(stoked)
        ..emotion = 'furious'
        ..intensity = 'strong';
      await one.runOneShot();
      expect(four.emotion, 'furious');
      expect(four.intensity, 'moderate');
      expect(one.emotion, four.emotion);
      expect(one.intensity, four.intensity);
    });

    const sameFamily =
        '{"relationship_delta":0,"trust_delta":0,"bond_reason":"none",'
        '"trust_reason":"none","emotion":"prickly","emotion_intensity":"mild",'
        '"fixation_topic":"none","proposed_objective":"none",'
        '"minutes_elapsed":5,"new_day":false,"reason":"scene"}';

    test('a reworded same-family feeling with no change answer holds the '
        'stored label on both paths', () async {
      final four = _Rig(sameFamily)
        ..emotion = 'furious'
        ..intensity = 'strong';
      await four.runFourCall();
      final one = _Rig(sameFamily)
        ..emotion = 'furious'
        ..intensity = 'strong';
      await one.runOneShot();
      // "prickly" is anger, like "furious": held, not moved. A one-shot that
      // kept its own emotion regex would write "prickly" here.
      expect(four.emotion, 'furious');
      expect(one.emotion, 'furious');
      expect(four.intensity, 'mild', reason: 'the judge eased it faster');
      expect(one.intensity, four.intensity);
    });
  });
}
