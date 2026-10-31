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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

/// The seven needs, as a seed's `needs` map and baseline keys name them.
const groupSeedNeeds = [
  'hunger',
  'bladder',
  'energy',
  'social',
  'fun',
  'hygiene',
  'comfort',
];

/// The seed key holding [need]'s baseline (`needsBaselineHunger`, ...).
String groupSeedBaselineKey(String need) =>
    'needsBaseline${need[0].toUpperCase()}${need.substring(1)}';

const _intensities = ['mild', 'moderate', 'strong'];

/// A new group member's starting seed (the keys of
/// [defaultGroupMemberRealismSeed]) read from their [card], the way a new
/// 1:1 chat with that card starts: Short-Term Bond, Long-Term Bond, Trust,
/// mood, each need's bar at the card's baseline, and the card's Needs,
/// verifier and Director-authority settings.
///
/// A card with no Front Porch extensions (a plain imported card) says
/// nothing about any of these, so it starts at the neutral seed, as every
/// member did before groups read the card.
Map<String, dynamic> groupMemberSeedFromCard(CharacterCard card) {
  final seed = defaultGroupMemberRealismSeed();
  final ext = card.frontPorchExtensions;
  if (ext == null) return seed;
  final baselines = <String, int>{
    'hunger': ext.needsBaselineHunger,
    'bladder': ext.needsBaselineBladder,
    'energy': ext.needsBaselineEnergy,
    'social': ext.needsBaselineSocial,
    'fun': ext.needsBaselineFun,
    'hygiene': ext.needsBaselineHygiene,
    'comfort': ext.needsBaselineComfort,
  };
  final emotion = ext.characterEmotion.trim();
  return seed..addAll({
    'affection': ext.shortTermBond.clamp(-300, 300),
    'longTermScore': ext.longTermBond.clamp(-300, 300),
    'trust': ext.trustLevel.clamp(-100, 100),
    'emotion': emotion.isEmpty ? 'neutral' : emotion,
    'emotionIntensity': _intensities.contains(ext.emotionIntensity)
        ? ext.emotionIntensity
        : 'mild',
    'needs': {for (final e in baselines.entries) e.key: e.value.clamp(0, 100)},
    for (final e in baselines.entries)
      groupSeedBaselineKey(e.key): e.value.clamp(0, 100),
    'enjoysLowHygiene': ext.enjoysLowHygiene,
    'verificationEnabled': ext.realismVerificationEnabled,
    'verificationMaxReprocesses': ext.realismVerificationMaxReprocesses,
    'verificationStrictness': ext.realismVerificationStrictness,
    'needsDirectorAuthority': ext.realismNeedsDirectorAuthority,
    'needsPace': ext.needsPace,
    'needsOff': List<String>.of(ext.needsOff),
  });
}

/// The seed a new group stores for [card]'s member: their card's seed
/// ([groupMemberSeedFromCard]) with what the new-group wizard set for them
/// ([edits], seed keys) laid over it. A need whose baseline the wizard
/// moved starts its bar at the new baseline, as a 1:1 chat starts each bar
/// at its baseline; the others keep the card's bar.
///
/// Shared by the desktop committer, the web relay's group create and the
/// group made from a 1:1 chat, so every way of making a group starts its
/// members alike. Only new groups call it: a saved group's seeds are never
/// rebuilt, so its new chats start as they always have.
Map<String, dynamic> groupMemberStartingSeed(
  CharacterCard card, [
  Map<String, dynamic> edits = const {},
]) {
  final fromCard = groupMemberSeedFromCard(card);
  final seed = <String, dynamic>{...fromCard, ...edits};
  final bars = <String, dynamic>{
    ...(fromCard['needs'] as Map<String, int>),
    if (edits['needs'] case final Map<dynamic, dynamic> posted)
      for (final e in posted.entries) e.key.toString(): e.value,
  };
  for (final need in groupSeedNeeds) {
    final key = groupSeedBaselineKey(need);
    if (seed[key] case final int moved when moved != fromCard[key]) {
      bars[need] = moved;
    }
  }
  seed['needs'] = bars;
  return seed;
}

/// A new group's settings for new chats with realism on, every member
/// ([membersById], runtime member id → that member's card) starting from
/// their card. What a group made from a 1:1 chat carries: a new chat starts
/// fresh, as New Chat does in a 1:1, so the current bond and mood are not
/// copied.
GroupRealismBlobs cardGroupRealismBlobs(
  Map<String, CharacterCard> membersById, {
  required bool needsEnabled,
}) => buildGroupRealismBlobs(
  seeds: {
    for (final e in membersById.entries)
      e.key: groupMemberStartingSeed(e.value),
  },
  needsEnabled: needsEnabled,
  timeOfDay: 'morning',
  dayCount: 1,
);
