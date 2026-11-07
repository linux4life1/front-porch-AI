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
/// [defaultGroupMemberRealismSeed]) read from their card's extensions
/// [ext], the way New Chat starts a 1:1 with that card: Short-Term Bond,
/// Long-Term Bond, Trust, mood, each need's bar at the card's baseline, and
/// the card's Needs, verifier and Director-authority settings.
///
/// A card with no Front Porch extensions (a plain imported card) reads as
/// `FrontPorchExtensions()`, as New Chat reads it in a 1:1, so a character
/// starts a group where it starts a 1:1.
Map<String, dynamic> groupMemberSeedFromExtensions(FrontPorchExtensions? ext) {
  final e = ext ?? FrontPorchExtensions();
  final baselines = <String, int>{
    'hunger': e.needsBaselineHunger.clamp(0, 100),
    'bladder': e.needsBaselineBladder.clamp(0, 100),
    'energy': e.needsBaselineEnergy.clamp(0, 100),
    'social': e.needsBaselineSocial.clamp(0, 100),
    'fun': e.needsBaselineFun.clamp(0, 100),
    'hygiene': e.needsBaselineHygiene.clamp(0, 100),
    'comfort': e.needsBaselineComfort.clamp(0, 100),
  };
  final emotion = e.characterEmotion.trim();
  return defaultGroupMemberRealismSeed()..addAll({
    'affection': e.shortTermBond.clamp(-300, 300),
    'longTermScore': e.longTermBond.clamp(-300, 300),
    'trust': e.trustLevel.clamp(-100, 100),
    'emotion': emotion.isEmpty ? 'neutral' : emotion,
    'emotionIntensity': _intensities.contains(e.emotionIntensity)
        ? e.emotionIntensity
        : 'mild',
    'needs': Map<String, int>.of(baselines),
    for (final b in baselines.entries) groupSeedBaselineKey(b.key): b.value,
    'enjoysLowHygiene': e.enjoysLowHygiene,
    'verificationEnabled': e.realismVerificationEnabled,
    'verificationMaxReprocesses': e.realismVerificationMaxReprocesses,
    'verificationStrictness': e.realismVerificationStrictness,
    'needsDirectorAuthority': e.realismNeedsDirectorAuthority,
    'needsPace': e.needsPace,
    'needsOff': List<String>.of(e.needsOff),
  });
}

/// [groupMemberSeedFromExtensions] for [card]'s extensions.
Map<String, dynamic> groupMemberSeedFromCard(CharacterCard card) =>
    groupMemberSeedFromExtensions(card.frontPorchExtensions);

/// The seed a group stores for a member whose card has extensions [ext]:
/// the card's seed ([groupMemberSeedFromExtensions]) with what the wizard
/// set for them ([edits], seed keys) laid over it. A need whose baseline
/// the wizard moved starts its bar at the new baseline, as a 1:1 chat
/// starts each bar at its baseline; the others keep the card's bar.
///
/// Shared by the desktop committer, the web relay's group create, the group
/// made from a 1:1 chat, and a group's Realism for new chats coming on for a
/// member with no seed, so every way a member gets a first seed starts them
/// alike. A seed a group already saved is never rebuilt with it.
Map<String, dynamic> groupMemberStartingSeed(
  FrontPorchExtensions? ext, [
  Map<String, dynamic> edits = const {},
]) {
  final fromCard = groupMemberSeedFromExtensions(ext);
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
/// ([membersById], runtime member id → the extensions of the card they were
/// made from) starting from that card. What a group made from a 1:1 chat
/// carries: a new chat starts fresh, as New Chat does in a 1:1, so the
/// current bond and mood are not copied.
GroupRealismBlobs cardGroupRealismBlobs(
  Map<String, FrontPorchExtensions?> membersById, {
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
