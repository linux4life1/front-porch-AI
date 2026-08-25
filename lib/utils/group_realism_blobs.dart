// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:convert';

import 'package:front_porch_ai/models/greeting_realism_seed.dart';

/// Canonical (de)serialization for a group's per-member realism/needs/dynamics
/// seeds ↔ the two GroupChat blobs (`defaultMemberRealismState`,
/// `baselineRealismState`). Extracted verbatim from the group creator so that
/// the create wizard AND the post-creation group editor produce identical state
/// — one contract, one source of truth, and testable in isolation.
///
/// Shapes (the exact contract the realism engine reads):
/// - `defaultMemberRealismState` = `{ "perChar": { memberId: <full seed> } }`,
///   where the full seed carries `affection`/`trust`/`emotion`/`emotionIntensity`,
///   the `needs` map, the `relationships` map (intragroup feelings, targetId→int),
///   and the per-need baseline/decay fields.
/// - `baselineRealismState` = `{ memberId: {affection, trust, emotion,
///   emotionIntensity, timeOfDay, dayCount} }` — scalars only (no needs/relationships).
class GroupRealismBlobs {
  /// JSON for `GroupChat.defaultMemberRealismState`.
  final String defaultMemberJson;

  /// JSON for `GroupChat.baselineRealismState`.
  final String baselineJson;

  const GroupRealismBlobs({
    required this.defaultMemberJson,
    required this.baselineJson,
  });
}

/// Serialize [seeds] (memberId → seed map) into the two group realism blobs,
/// exactly as the group creator does. When [needsEnabled] is false the `needs`
/// map is stripped from every member (both blobs) — relationships are always kept.
///
/// Group-wide scene time is written to TOP-LEVEL keys of the defaultMember
/// blob (`timeOfDay`/`dayCount` + the Story Calendar's `storyStartDate`/
/// `storyStartTime`) — the same spot the group settings dialog already wrote,
/// now the canonical one [parseGroupTimeSeed] reads to seed a fresh group
/// session's clock. The per-member baseline copies stay for older app
/// versions reading exported group cards.
GroupRealismBlobs buildGroupRealismBlobs({
  required Map<String, Map<String, dynamic>> seeds,
  required bool needsEnabled,
  required String timeOfDay,
  required int dayCount,
  String? storyStartDate,
  String? storyStartTime,
  List<String> alternateGreetings = const [],
  List<GreetingRealismSeed?> greetingSeeds = const [],
}) {
  final defaultMember = <String, dynamic>{
    'perChar': <String, dynamic>{},
    'timeOfDay': timeOfDay,
    'dayCount': dayCount,
    'storyStartDate': ?storyStartDate,
    'storyStartTime': ?storyStartTime,
    ..._groupOpeningAltsFragment(alternateGreetings, greetingSeeds),
  };
  final baseline = <String, dynamic>{};

  seeds.forEach((id, rawSeed) {
    var seed = rawSeed;
    if (!needsEnabled) {
      seed = Map<String, dynamic>.from(seed)..remove('needs');
    }
    (defaultMember['perChar'] as Map)[id] = seed;
    baseline[id] = {
      'affection': (seed['affection'] as num?)?.toInt() ?? 35,
      'trust': (seed['trust'] as num?)?.toInt() ?? 40,
      'emotion': (seed['emotion'] as String?) ?? 'neutral',
      'emotionIntensity': (seed['emotionIntensity'] as String?) ?? 'mild',
      'timeOfDay': timeOfDay,
      'dayCount': dayCount,
    };
  });

  return GroupRealismBlobs(
    defaultMemberJson: jsonEncode(defaultMember),
    baselineJson: jsonEncode(baseline),
  );
}

/// The neutral-but-alive starting seed for a group member's realism/needs. Shared
/// by the group creator (initial per-member seed) and the post-creation group
/// editor so both produce an identical default — one contract, no divergence.
/// The `relationships` map is filled in the Group Dynamics step for small groups.
Map<String, dynamic> defaultGroupMemberRealismSeed() => {
  'affection': 35,
  'trust': 40,
  'emotion': 'neutral',
  'emotionIntensity': 'mild',
  'timeOfDay': 'morning',
  'dayCount': 1,
  // Built FROM the engine's own map, not hand-copied from it. This used to
  // carry 'thirst' and 'rest', which exist nowhere else in the codebase, while
  // omitting 'energy', 'fun' and 'comfort', which are real — so a new group
  // member started with two needs the simulation ignores and three silently
  // filled from defaults, and the per-member baseline sliders in the group
  // wizard could not reach half of them.
  //
  // Kept as a literal rather than derived from NeedsSimulation.needDefaults on
  // purpose: utils must not depend on services/chat, and importing the engine
  // here to fix a data bug would invert the layer direction. Drift is prevented
  // instead by test/utils/group_needs_seed_test.dart, which compares this map
  // against the engine's key set AND values and fails loudly on any mismatch —
  // so changing needDefaults without changing this reddens CI.
  'needs': <String, int>{
    'hunger': 75,
    'bladder': 80,
    'energy': 80,
    'social': 65,
    'fun': 65,
    'hygiene': 75,
    'comfort': 70,
  },
  'enjoysLowHygiene': false,
  'verificationEnabled': false,
  'verificationMaxReprocesses': 1,
  'verificationStrictness': 3,
  'needsDirectorAuthority': false,
  'needsSimStrength': 1,
  'needsBaselineHunger': 80,
  'needsBaselineBladder': 80,
  'needsBaselineEnergy': 80,
  'needsBaselineSocial': 80,
  'needsBaselineFun': 80,
  'needsBaselineHygiene': 80,
  'needsBaselineComfort': 80,
  'needsDecayHunger': 5,
  'needsDecayBladder': 5,
  'needsDecayEnergy': 5,
  'needsDecaySocial': 5,
  'needsDecayFun': 5,
  'needsDecayHygiene': 5,
  'needsDecayComfort': 5,
  'relationships': <String, int>{},
};

/// Re-key member realism seeds from arbitrary *source* ids to the RUNTIME member
/// ids the realism engine actually reads.
///
/// The group creator builds its per-member seeds keyed by the SOURCE library
/// character's `stableGroupId` (an image-filename basename), but every runtime
/// read (`_groupRealism[id]`, baseline lookups, per-member system prompts) keys
/// off the group member's own UUID (`GroupMember.id` == the member avatar's
/// basename, a.k.a. `mid`). Those id-spaces differ, so seeds written under the
/// source id are never found at runtime — bond/trust/emotion/relationships and
/// starting-needs silently fall back to defaults. This closes that gap by
/// re-keying both the member entries AND their intragroup `relationships`
/// targets (which reference OTHER members by the same source id) to `mid`.
///
/// [idMap] maps each source id → its member `mid`. Ids (and relationship
/// targets) with no mapping pass through unchanged — defensive for already-`mid`
/// keys and for a relationship target that has since left the group. Works on a
/// copy; the caller's [seedsBySourceId] is never mutated.
Map<String, Map<String, dynamic>> remapSeedsToMemberIds(
  Map<String, Map<String, dynamic>> seedsBySourceId,
  Map<String, String> idMap,
) {
  String mapId(String id) => idMap[id] ?? id;
  final out = <String, Map<String, dynamic>>{};
  seedsBySourceId.forEach((sourceId, seed) {
    final copy = Map<String, dynamic>.from(seed);
    final rels = copy['relationships'];
    if (rels is Map) {
      final remapped = <String, dynamic>{};
      rels.forEach((target, v) => remapped[mapId(target.toString())] = v);
      copy['relationships'] = remapped;
    }
    out[mapId(sourceId)] = copy;
  });
  return out;
}

/// Inverse of [buildGroupRealismBlobs]: read the per-member seeds back out of a
/// group's `defaultMemberRealismState` (the `perChar` map holds the full seeds).
/// Returns an empty map for absent/blank state.
Map<String, Map<String, dynamic>> parseGroupRealismSeeds(
  String defaultMemberJson,
) {
  if (defaultMemberJson.isEmpty || defaultMemberJson == '{}') return {};
  final decoded = jsonDecode(defaultMemberJson);
  final perChar = decoded is Map ? decoded['perChar'] : null;
  if (perChar is! Map) return {};
  return perChar.map(
    (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
  );
}

/// The group-wide scene-time seed for a FRESH group session's clock
/// (story-calendar.md "As built": before this existed, the group creator's
/// time seed was editor-carried state that never reached the runtime clock).
///
/// Reads the canonical top-level keys of `defaultMemberRealismState` first
/// (what [buildGroupRealismBlobs] and the group settings dialog write), then
/// falls back to the first per-member baseline entry — where the pre-fix
/// wizard stored its only copy — so existing groups' authored time finally
/// applies too. Null when neither blob carries a time (realism-off groups).
({
  int dayCount,
  String timeOfDay,
  String? storyStartDate,
  String? storyStartTime,
})?
parseGroupTimeSeed(String defaultMemberJson, String baselineJson) {
  Map<String, dynamic>? source;
  try {
    if (defaultMemberJson.isNotEmpty && defaultMemberJson != '{}') {
      final decoded = jsonDecode(defaultMemberJson);
      if (decoded is Map && decoded['timeOfDay'] is String) {
        source = Map<String, dynamic>.from(decoded);
      }
    }
    if (source == null && baselineJson.isNotEmpty && baselineJson != '{}') {
      final decoded = jsonDecode(baselineJson);
      if (decoded is Map && decoded.isNotEmpty && decoded.values.first is Map) {
        final first = decoded.values.first as Map;
        if (first['timeOfDay'] is String) {
          source = Map<String, dynamic>.from(first);
        }
      }
    }
  } catch (_) {
    return null;
  }
  if (source == null) return null;
  return (
    dayCount: (source['dayCount'] as num?)?.toInt() ?? 1,
    timeOfDay: source['timeOfDay'] as String,
    storyStartDate: source['storyStartDate'] as String?,
    storyStartTime: source['storyStartTime'] as String?,
  );
}

Map<String, dynamic> _decodeGroupBlob(String json) {
  if (json.isEmpty || json == '{}') return <String, dynamic>{};
  try {
    final decoded = jsonDecode(json);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

Map<String, dynamic> _groupOpeningAltsFragment(
  List<String> alternateGreetings,
  List<GreetingRealismSeed?> greetingSeeds,
) {
  final paired = compactGreetingPairs(alternateGreetings, greetingSeeds);
  return {
    if (paired.greetings.isNotEmpty) 'alternateGreetings': paired.greetings,
    if (paired.seeds.isNotEmpty)
      'greetingSeeds': [for (final s in paired.seeds) s?.toJson()],
  };
}

/// Group-level alt openings (custom group first_message only). Stored next
/// to the scene-time seed on `defaultMemberRealismState` so Group Cards
/// round-trip without a schema bump — same home as timeOfDay/dayCount.
({List<String> greetings, List<GreetingRealismSeed?> seeds})
parseGroupOpeningPairs(String defaultMemberJson) {
  final map = _decodeGroupBlob(defaultMemberJson);
  final greets = greetingSlotsFromRaw(map['alternateGreetings']);
  return compactGreetingPairs(greets, parseGreetingSeeds(map['greetingSeeds']));
}

List<String> parseGroupAlternateGreetings(String defaultMemberJson) {
  return parseGroupOpeningPairs(defaultMemberJson).greetings;
}

List<GreetingRealismSeed?> parseGroupGreetingSeeds(String defaultMemberJson) {
  return parseGroupOpeningPairs(defaultMemberJson).seeds;
}

/// Patch alt greetings onto an existing group blob without touching perChar
/// or scene time. Used by the group editor / settings save.
String withGroupOpeningAlts(
  String defaultMemberJson, {
  required List<String> alternateGreetings,
  required List<GreetingRealismSeed?> greetingSeeds,
}) {
  final map = _decodeGroupBlob(defaultMemberJson);
  map.remove('alternateGreetings');
  map.remove('greetingSeeds');
  map.addAll(_groupOpeningAltsFragment(alternateGreetings, greetingSeeds));
  return jsonEncode(map);
}
