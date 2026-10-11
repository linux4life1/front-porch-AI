// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Evals score the user's message. In a group, a follow-up speaker's
// pre-gen judges run while the previous NPC's reply is already the tail;
// they must cut their window at the last user line (four messages for the
// three prefix-sharing judges, six for one-shot). Scene-time is post-gen and
// reads the reply just written, so it keeps the full six-message tail.
//
// Driven through the real RealismEvals leaf; the fire callback only records
// the prompt each eval actually sends.
//
// Proven red: swap a judge's recentExchangeThroughLastUser for
// recentExchange (the NPC tail leaks into bond/mood); swap scene-time to
// the through-last-user window (it loses the reply); change a take.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

const _lines = [
  'ZZALPHA',
  'ZZBRAVO',
  'ZZCHARLIE',
  'ZZDELTA',
  'ZZECHO',
  'ZZFOXTROT',
  'ZZGOLF',
  'ZZHOTEL',
];

/// User / Alex alternating, ending on a user line (ZZGOLF) followed by the
/// previous group speaker's reply (ZZHOTEL from Blake).
List<ChatMessage> _groupFollowUpTail() => [
  for (var i = 0; i < 7; i++)
    ChatMessage(
      text: 'line ${_lines[i]}',
      sender: i.isEven ? 'User' : 'Alex',
      isUser: i.isEven,
    ),
  ChatMessage(text: 'line ${_lines[7]}', sender: 'Blake', isUser: false),
];

RealismEvals _evals(List<String> prompts) {
  final rel = RelationshipService(
    onNotify: () {},
    onSaveChat: () async {},
    getIsGroupActive: () => false,
    getObserverMode: () => false,
    getGroupCharacterCount: () => 0,
    getShouldTrackInterCharacterRelationships: () => false,
    getCurrentSpeakerIdForRealism: () => '',
    getCurrentGroupMemberIds: () => {},
    getOtherGroupMemberIds: (_) => [],
    getOtherGroupMemberIdToLowerName: (_) => {},
    getRecentExchangeLowerText: () => '',
    getMessageCount: () => 0,
    getIsGroupRealismActive: () => false,
    getGroupAffectionScore: (id, {defaultValue = 0}) => defaultValue,
    setGroupAffectionScore: (_, _) {},
    getGroupLongTermScore: (id, {defaultValue = 0}) => defaultValue,
    setGroupLongTermScore: (_, _) {},
    getGroupTrustLevel: (id, {defaultValue = 0}) => defaultValue,
    setGroupTrustLevel: (_, _) {},
    getGroupFixation: (id, {defaultValue = ''}) => defaultValue,
    setGroupFixation: (_, _) {},
    getGroupFixationLifespan: (id, {defaultValue = 0}) => defaultValue,
    setGroupFixationLifespan: (_, _) {},
    getGroupRelationshipTier: (id, {defaultValue = 0}) => defaultValue,
    setGroupRelationshipTier: (_, _) {},
    getGroupLongTermTier: (id, {defaultValue = 0}) => defaultValue,
    setGroupLongTermTier: (_, _) {},
    getGroupSpatialStance: (id, {defaultValue = ''}) => defaultValue,
    setGroupSpatialStance: (_, _) {},
    getGroupInterCharacterRelationships: (_) => <String, int>{},
    setGroupInterCharacterRelationships: (_, _) {},
  );
  final time = TimeService(
    onNotify: () {},
    onSaveChat: () async {},
    onSetPendingRealismMetadata: (k, v) {},
    onPatchLastMessageRealismState: (tod, dc, iso) {},
    getPorchLifePassageOfTime: () => true,
  );
  final char = CharacterCard(name: 'Alex', personality: 'steady');
  final messages = _groupFollowUpTail();
  return RealismEvals(
    fireLLMEval: (p, {onChunk}) async {
      prompts.add(p);
      return '{}';
    },
    fireToolEval: (p, t) async => null,
    probe: ToolTransportProbe(),
    getBackendIdentity: () => 'test-backend',
    isEvalCancelled: () => false,
    stripThinkBlocks: (t) => t,
    extractJsonInt: (t, k) => null,
    extractJsonBool: (t, k) => null,
    getActiveCharacter: () => char,
    getActiveGroup: () => null,
    getIsObserverMode: () => false,
    getUserName: () => 'User',
    getRealismEnabled: () => true,
    getMessages: () => messages,
    getPendingRealismMetadata: () => <String, dynamic>{},
    setPendingRealismMetadata: (v) {},
    captureRealismState: ({Map<String, int>? preTurn}) => <String, dynamic>{},
    getCharacterEmotion: () => '',
    setCharacterEmotion: (_) {},
    getEmotionIntensity: () => '',
    setEmotionIntensity: (_) {},
    relationshipService: rel,
    nsfwService: NsfwService(
      getGroupInt: (_, _) => 0,
      getGroupValue: (_, _) => null,
      setGroupValue: (_, _, _) {},
    ),
    timeService: time,
    getExpressionEnabled: () => false,
    getCharacterDossier: (card) => card.personality,
    getPrimaryObjective: () => null,
    getActiveObjectives: () => [],
    setObjective:
        (
          text, {
          isPrimary = false,
          autoGenerateTasks = false,
          servedAmbition,
        }) async {},
  );
}

/// Which of the eight transcript lines the first prompt of [run] carried.
Future<List<String>> _seen(Future<void> Function(RealismEvals) run) async {
  final prompts = <String>[];
  await run(_evals(prompts));
  expect(prompts, isNotEmpty, reason: 'the eval never fired');
  return [
    for (final l in _lines)
      if (prompts.first.contains(l)) l,
  ];
}

void main() {
  const judgeWindow = ['ZZDELTA', 'ZZECHO', 'ZZFOXTROT', 'ZZGOLF'];

  test('bond judge reads four messages through the last user line', () async {
    expect(await _seen((e) => e.evaluateRelationshipCall()), judgeWindow);
  });

  test('mood judge reads four messages through the last user line', () async {
    expect(await _seen((e) => e.evaluateEmotionalStateCall()), judgeWindow);
  });

  test(
    'narrative judge reads four messages through the last user line',
    () async {
      expect(await _seen((e) => e.evaluateNarrativeCall()), judgeWindow);
    },
  );

  test('one-shot reads six messages through the last user line', () async {
    expect(await _seen((e) => e.evaluateOneShotCall()), [
      'ZZBRAVO',
      'ZZCHARLIE',
      'ZZDELTA',
      'ZZECHO',
      'ZZFOXTROT',
      'ZZGOLF',
    ]);
  });

  test('scene-time keeps the six-message tail with the reply', () async {
    expect(await _seen((e) => e.evaluatePhysicalStateCall(timeOnly: true)), [
      'ZZCHARLIE',
      'ZZDELTA',
      'ZZECHO',
      'ZZFOXTROT',
      'ZZGOLF',
      'ZZHOTEL',
    ]);
  });
}
