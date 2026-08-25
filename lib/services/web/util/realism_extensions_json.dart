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

import 'package:front_porch_ai/models/models.dart';

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

  /// Defensive list-of-strings read: a hand-edited or older client may send a
  /// scalar, a null, or entries that are not strings. Anything unusable is
  /// dropped rather than throwing, matching how every other field here fails
  /// soft.
  List<String> asStrList(String key, List<String> fallback) {
    final v = fields[key];
    if (v is! List) return fallback;
    return [
      for (final e in v)
        if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
  }

  String asStr(String key, String fallback) =>
      fields.containsKey(key) && fields[key] != null
      ? fields[key].toString()
      : fallback;

  /// Missing key keeps [fallback]. Present `[]` is never-at-work. Junk →
  /// fallback rather than throwing, same as [asStrList].
  List<int>? asWorkDays(String key, List<int>? fallback) {
    if (!fields.containsKey(key) || fields[key] == null) return fallback;
    final v = fields[key];
    if (v is! List) return fallback;
    if (v.isEmpty) return const [];
    final days = <int>{};
    for (final e in v) {
      final n = e is int
          ? e
          : e is num
          ? e.toInt()
          : e is String
          ? int.tryParse(e.trim())
          : null;
      if (n != null && n >= DateTime.monday && n <= DateTime.sunday) {
        days.add(n);
      }
    }
    if (days.isEmpty) return fallback;
    final list = days.toList()..sort();
    return list;
  }

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
    // Same class of bug as `inventory` below, and missed when that one was
    // fixed: the web editor has no control for any of these three, so they were
    // absent from this constructor entirely and silently took their `null`
    // default on every web save. Editing a description from a phone erased the
    // authored Story Begins date/time (new chats then opened at "the day the
    // chat starts") and un-starred the canonical avatar. The desktop twin
    // (edit_character_page.dart, via copyWith) preserves them, so carrying them
    // from the base is also what restores desktop↔web parity.
    storyStartDate: b.storyStartDate,
    storyStartTime: b.storyStartTime,
    favoriteAvatarId: b.favoriteAvatarId,
    // Same class of bug as inventory/storyStart: the React editor used to
    // omit greetingSeeds, and rebuilding without carrying the base wiped
    // per-alt opening state on every phone save. If the POST *does* rewrite
    // alts but omits seeds, do not keep unpaired base leftovers — compact
    // against empty/null so leftover furious cannot land on Get out.
    greetingSeeds: () {
      final altsPresent = fields['alternateGreetings'] is List;
      if (!fields.containsKey('greetingSeeds')) {
        if (!altsPresent) return b.greetingSeeds;
        return compactGreetingPairs(
          greetingSlotsFromRaw(fields['alternateGreetings']),
          const [],
        ).seeds;
      }
      final parsed = parseGreetingSeeds(fields['greetingSeeds']);
      if (!altsPresent) return parsed;
      return compactGreetingPairs(
        greetingSlotsFromRaw(fields['alternateGreetings']),
        parsed,
      ).seeds;
    }(),

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
    ambitions: asStrList('ambitions', b.ambitions),
    planLines: asStrList('planLines', b.planLines),
    occupation: asStr('occupation', b.occupation),
    hours: asStr('hours', b.hours),
    occupationBrief: asStr('occupationBrief', b.occupationBrief),
    workDays: asWorkDays('workDays', b.workDays),
    likes: asStrList('likes', b.likes),
    dislikes: asStrList('dislikes', b.dislikes),
    // The 18+ pair travels FLAT over this bridge (`intimateInto` /
    // `intimateNotInto`) even though the CARD nests it under
    // `intimate_preferences`. This bridge is the web editor's own wire format,
    // not the portable card JSON — every other field here is flat camelCase,
    // and nesting one pair would earn a special case in asStrList for nothing.
    // CharacterCard.toJson still emits the nested object, so what ships to The
    // Stoop is unchanged.
    intimateInto: asStrList('intimateInto', b.intimateInto),
    intimateNotInto: asStrList('intimateNotInto', b.intimateNotInto),
    // Starting Pockets & Wardrobe. Nested (`{worn: [...], carrying: [...]}`)
    // rather than flat, because unlike the 18+ pair above this is not two lists
    // of strings — entries can be `{name, state}` — and flattening it would
    // lose the condition half of every item.
    //
    // Read with the same shallow, shape-tolerant cast CharacterCard.fromJson
    // uses for this field, deliberately: two readers of one field that disagree
    // about what counts as valid is its own bug. Anything unusable falls back
    // to the base rather than throwing, and Pockets.fromJson (the only consumer)
    // already tolerates both entry shapes.
    //
    // Falling back to `b.inventory` is the actual fix here: the field was absent
    // from this constructor entirely, so it silently took its `const {}` default
    // on every web save. Editing a character from a phone wiped whatever
    // starting inventory its author had written, with nothing on screen to
    // suggest the edit had touched it.
    inventory: fields['inventory'] is Map
        ? Map<String, dynamic>.from(fields['inventory'] as Map)
        : b.inventory,

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
  'ambitions': e.ambitions,
  'planLines': e.planLines,
  'occupation': e.occupation,
  'hours': e.hours,
  'occupationBrief': e.occupationBrief,
  'workDays': e.workDays,
  'likes': e.likes,
  'dislikes': e.dislikes,
  'intimateInto': e.intimateInto,
  'intimateNotInto': e.intimateNotInto,
  'inventory': e.inventory,
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
  'greetingSeeds': [for (final s in e.greetingSeeds) s?.toFields()],
};
