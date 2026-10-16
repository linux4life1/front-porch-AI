// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The autonomous proposal is the ONE place a realism eval creates an objective,
// so it must respect the Objectives switch (schema v45's per-chat flag ANDed
// with the Porch Life default). The four-call narrative path checks
// getObjectivesEnabled; the fused one-shot path did not — and one-shot is what
// OneShotMode.auto selects on any tool-capable remote backend, i.e. the default
// on the most common remote setup. With quests switched off, the character kept
// starting new ones and each proposal fired an extra, unrequested
// task-generation call.
//
// Both paths are driven here through their real public entry points with only
// the LLM call faked, and the four-call path is asserted alongside so the gate
// is proven to be parity rather than a one-sided guess.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_evals.dart';
import 'package:front_porch_ai/services/chat/realism_prompt_builder.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

/// A RealismEvals wired over real relationship/nsfw/time services, with the LLM
/// answer canned and every created objective recorded.
class _Rig {
  _Rig({
    required this.reply,
    required bool objectivesOn,
    List<Objective> active = const [],
    int? sideQuestCap,
  }) {
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
      fireLLMEval: (p, {onChunk}) async => reply,
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
      getObjectivesEnabled: () => objectivesOn,
      getPrimaryObjective: () => active.where((o) => o.isPrimary).firstOrNull,
      getActiveObjectives: () => active,
      getSideQuestCap: sideQuestCap == null ? null : () => sideQuestCap,
      setObjective:
          (
            t, {
            isPrimary = false,
            autoGenerateTasks = false,
            servedAmbition,
          }) async {
            created.add(t);
          },
    );
  }

  final String reply;

  late final RelationshipService rel;
  late final NsfwService nsfw;
  late final TimeService time;
  late final RealismEvals evals;

  /// Every objective the eval asked the god to create.
  final List<String> created = [];
  String emotion = '';
  String intensity = '';
  Map<String, dynamic> _pending = {};

  final _char = CharacterCard(name: 'Aerin', personality: 'warm');
  final _messages = <ChatMessage>[
    ChatMessage(
      text: 'want to help me find the key?',
      isUser: true,
      sender: 'User',
    ),
    ChatMessage(text: 'maybe.', isUser: false, sender: 'Aerin'),
  ];
}

void main() {
  // The fused reply proposes a goal; everything else is inert.
  const reply =
      '{"relationship_delta":0,"trust_delta":0,"emotion":"calm",'
      '"emotion_intensity":"mild","arousal_delta":0,"fixation_topic":"",'
      '"proposed_objective":"find the missing key","serves_ambition":"none",'
      '"minutes_elapsed":5,"new_day":false,"reason":"scene"}';

  group('autonomous objectives respect the Objectives switch', () {
    test('one-shot creates nothing when Objectives are off', () async {
      final rig = _Rig(reply: reply, objectivesOn: false);
      await rig.evals.evaluateOneShotCall();
      expect(
        rig.created,
        isEmpty,
        reason:
            'quests are switched off — the fused eval must not grow new ones '
            'behind the switch (and must not fire task generation)',
      );
    });

    test('one-shot still creates when Objectives are on', () async {
      final rig = _Rig(reply: reply, objectivesOn: true);
      await rig.evals.evaluateOneShotCall();
      expect(rig.created, ['find the missing key']);
    });

    test('the four-call path agrees, both ways', () async {
      final off = _Rig(reply: reply, objectivesOn: false);
      await off.evals.evaluateNarrativeCall();
      expect(off.created, isEmpty);

      final on = _Rig(reply: reply, objectivesOn: true);
      await on.evals.evaluateNarrativeCall();
      expect(
        on.created,
        ['find the missing key'],
        reason:
            'the two paths must make the identical decision — one-shot is a '
            'token optimisation, not a different feature',
      );
    });
  });

  // 2026-10-16, objectives that keep up: the character keeps proposing the
  // goal it already has in new words, and each one used to land as another
  // quest. Both transports share one decision, so both must refuse it.
  group('a proposed goal the character already has is not filed again', () {
    Objective open(String text, {bool primary = true}) => Objective(
      id: text,
      characterId: 'aerin',
      objective: text,
      tasks: '[]',
      active: true,
      isPrimary: primary,
      checkFrequency: 3,
      injectionDepth: 4,
      createdAt: DateTime(2026),
    );

    test('a rewording of an open goal is refused on both paths', () async {
      for (final oneShot in [true, false]) {
        final rig = _Rig(
          reply: reply,
          objectivesOn: true,
          active: [open('Find the key that went missing')],
        );
        oneShot
            ? await rig.evals.evaluateOneShotCall()
            : await rig.evals.evaluateNarrativeCall();
        expect(
          rig.created,
          isEmpty,
          reason:
              '"find the missing key" rewords the open goal '
              '(${oneShot ? "one-shot" : "four-call"})',
        );
      }
    });

    test('at the side-quest cap nothing new is filed or evicted', () async {
      for (final oneShot in [true, false]) {
        final rig = _Rig(
          reply: reply,
          objectivesOn: true,
          sideQuestCap: 1,
          active: [
            open('Win the harvest fair'),
            open('Mend the porch steps', primary: false),
          ],
        );
        oneShot
            ? await rig.evals.evaluateOneShotCall()
            : await rig.evals.evaluateNarrativeCall();
        expect(
          rig.created,
          isEmpty,
          reason: oneShot ? 'one-shot' : 'four-call',
        );
      }
    });

    test('a new want still lands in a side slot below the cap', () async {
      final rig = _Rig(
        reply: reply,
        objectivesOn: true,
        sideQuestCap: 2,
        active: [open('Win the harvest fair')],
      );
      await rig.evals.evaluateOneShotCall();
      expect(rig.created, ['find the missing key']);
    });
  });
}
