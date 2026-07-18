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

/// Single source of truth converting a flat web JSON map ↔ [FrontPorchExtensions].
///
/// Mirrors the character creator's inline seed build but **complete** — it
/// round-trips every Realism Engine, Needs Simulation, verifier and scene-time
/// field. Reused by character create/update (and group per-member seeding) so a
/// character written from a 1:1 wizard and the same character seeded inside a
/// group end up with byte-identical extensions — the 1:1↔group parity contract.
///
/// Keys are camelCase and match the React form field names verbatim so the same
/// payload flows straight from the web wizard into [frontPorchFromFields] and
/// back out through [frontPorchToJson] without an intermediate mapping layer.

/// Build (or update) a [FrontPorchExtensions] from a flat web JSON [fields] map.
///
/// When [base] is provided, any key absent from [fields] keeps the base value,
/// so a partial edit (e.g. a save that only touches realism) never wipes
/// unrelated state (chat-appearance colors, font, avatar lock, tier). A
/// [stableId] is always ensured so library dbId + chat history survive PNG
/// rewrites.
FrontPorchExtensions frontPorchFromFields(
  Map<String, dynamic> fields, {
  FrontPorchExtensions? base,
}) {
  final b = base ?? FrontPorchExtensions();

  int asInt(String key, int fallback) {
    final v = fields[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  bool asBool(String key, bool fallback) =>
      fields[key] is bool ? fields[key] as bool : fallback;

  String asStr(String key, String fallback) =>
      fields.containsKey(key) && fields[key] != null
      ? fields[key].toString()
      : fallback;

  return FrontPorchExtensions(
    // Preserved identity / non-form state (carried from base, never wiped).
    stableId: b.stableId,
    tier: b.tier,
    avatarLocked: b.avatarLocked,
    userBubbleColor: b.userBubbleColor,
    userTextColor: b.userTextColor,
    aiBubbleColor: b.aiBubbleColor,
    aiTextColor: b.aiTextColor,
    dialogueColor: b.dialogueColor,
    actionColor: b.actionColor,
    chatFontFamily: b.chatFontFamily,

    // Realism Engine core.
    realismEnabled: asBool('realismEnabled', b.realismEnabled),
    shortTermBond: asInt('shortTermBond', b.shortTermBond),
    longTermBond: asInt('longTermBond', b.longTermBond),
    trustLevel: asInt('trustLevel', b.trustLevel),
    dayCount: asInt('dayCount', b.dayCount),
    timeOfDay: asStr('timeOfDay', b.timeOfDay),
    characterEmotion: asStr('characterEmotion', b.characterEmotion),
    emotionIntensity: asStr('emotionIntensity', b.emotionIntensity),
    nsfwCooldownEnabled: asBool('nsfwCooldownEnabled', b.nsfwCooldownEnabled),
    passageOfTimeEnabled: asBool(
      'passageOfTimeEnabled',
      b.passageOfTimeEnabled,
    ),
    chaosModeEnabled: asBool('chaosModeEnabled', b.chaosModeEnabled),
    currentTask: asStr('currentTask', b.currentTask),

    // Realism verification (Director/Verifier).
    realismVerificationEnabled: asBool(
      'realismVerificationEnabled',
      b.realismVerificationEnabled,
    ),
    realismVerificationMaxReprocesses: asInt(
      'realismVerificationMaxReprocesses',
      b.realismVerificationMaxReprocesses,
    ),
    realismVerificationStrictness: asInt(
      'realismVerificationStrictness',
      b.realismVerificationStrictness,
    ),
    realismNeedsDirectorAuthority: asBool(
      'realismNeedsDirectorAuthority',
      b.realismNeedsDirectorAuthority,
    ),

    // Needs Simulation.
    needsSimEnabled: asBool('needsSimEnabled', b.needsSimEnabled),
    enjoysLowHygiene: asBool('enjoysLowHygiene', b.enjoysLowHygiene),
    needsSimStrength: asInt('needsSimStrength', b.needsSimStrength),
    needsBaselineHunger: asInt('needsBaselineHunger', b.needsBaselineHunger),
    needsBaselineBladder: asInt('needsBaselineBladder', b.needsBaselineBladder),
    needsBaselineEnergy: asInt('needsBaselineEnergy', b.needsBaselineEnergy),
    needsBaselineSocial: asInt('needsBaselineSocial', b.needsBaselineSocial),
    needsBaselineFun: asInt('needsBaselineFun', b.needsBaselineFun),
    needsBaselineHygiene: asInt('needsBaselineHygiene', b.needsBaselineHygiene),
    needsBaselineComfort: asInt('needsBaselineComfort', b.needsBaselineComfort),
    needsDecayHunger: asInt('needsDecayHunger', b.needsDecayHunger),
    needsDecayBladder: asInt('needsDecayBladder', b.needsDecayBladder),
    needsDecayEnergy: asInt('needsDecayEnergy', b.needsDecayEnergy),
    needsDecaySocial: asInt('needsDecaySocial', b.needsDecaySocial),
    needsDecayFun: asInt('needsDecayFun', b.needsDecayFun),
    needsDecayHygiene: asInt('needsDecayHygiene', b.needsDecayHygiene),
    needsDecayComfort: asInt('needsDecayComfort', b.needsDecayComfort),
  )..ensureStableId();
}

/// Flatten a [FrontPorchExtensions] to the web JSON shape consumed by the
/// React Realism/Needs form sections (the inverse of [frontPorchFromFields]).
Map<String, dynamic> frontPorchToJson(FrontPorchExtensions e) => {
  'realismEnabled': e.realismEnabled,
  'shortTermBond': e.shortTermBond,
  'longTermBond': e.longTermBond,
  'trustLevel': e.trustLevel,
  'dayCount': e.dayCount,
  'timeOfDay': e.timeOfDay,
  'characterEmotion': e.characterEmotion,
  'emotionIntensity': e.emotionIntensity,
  'nsfwCooldownEnabled': e.nsfwCooldownEnabled,
  'passageOfTimeEnabled': e.passageOfTimeEnabled,
  'chaosModeEnabled': e.chaosModeEnabled,
  'currentTask': e.currentTask,
  'realismVerificationEnabled': e.realismVerificationEnabled,
  'realismVerificationMaxReprocesses': e.realismVerificationMaxReprocesses,
  'realismVerificationStrictness': e.realismVerificationStrictness,
  'realismNeedsDirectorAuthority': e.realismNeedsDirectorAuthority,
  'needsSimEnabled': e.needsSimEnabled,
  'enjoysLowHygiene': e.enjoysLowHygiene,
  'needsSimStrength': e.needsSimStrength,
  'needsBaselineHunger': e.needsBaselineHunger,
  'needsBaselineBladder': e.needsBaselineBladder,
  'needsBaselineEnergy': e.needsBaselineEnergy,
  'needsBaselineSocial': e.needsBaselineSocial,
  'needsBaselineFun': e.needsBaselineFun,
  'needsBaselineHygiene': e.needsBaselineHygiene,
  'needsBaselineComfort': e.needsBaselineComfort,
  'needsDecayHunger': e.needsDecayHunger,
  'needsDecayBladder': e.needsDecayBladder,
  'needsDecayEnergy': e.needsDecayEnergy,
  'needsDecaySocial': e.needsDecaySocial,
  'needsDecayFun': e.needsDecayFun,
  'needsDecayHygiene': e.needsDecayHygiene,
  'needsDecayComfort': e.needsDecayComfort,
};
