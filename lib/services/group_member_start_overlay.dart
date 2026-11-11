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

import 'dart:convert';

import 'package:front_porch_ai/models/character/front_porch_extensions.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show GroupRealismKeys;
import 'package:front_porch_ai/utils/group_member_card_seed.dart';

/// The top-level key of a group's definition blob holding the starting
/// feelings between members: `{from: {to: score}}` (Edit group → Realism
/// Engine, and each member's "In The Porch Trio" section). One store; a
/// member's own `relationships` map in an older seed is read as a fallback.
const kGroupStartingFeelingsKey = 'startingFeelings';

/// A member the overlay reads: their id in the group, and the extensions of
/// their copy in the group.
typedef OverlayMember = ({String mid, FrontPorchExtensions? ext});

bool _startUntouched(FrontPorchExtensions e) {
  final fresh = FrontPorchExtensions();
  return e.shortTermBond == fresh.shortTermBond &&
      e.longTermBond == fresh.longTermBond &&
      e.trustLevel == fresh.trustLevel &&
      e.characterEmotion.trim() == fresh.characterEmotion.trim() &&
      e.emotionIntensity == fresh.emotionIntensity;
}

bool _hasBonds(Map<String, dynamic> seed) =>
    seed.containsKey(GroupRealismKeys.affection) ||
    seed.containsKey(GroupRealismKeys.longTermScore) ||
    seed.containsKey(GroupRealismKeys.trust);

/// The starting feelings [definitionJson] holds, `{from: {to: score}}`.
Map<String, Map<String, int>> startingFeelingsIn(String definitionJson) {
  try {
    final raw = jsonDecode(definitionJson);
    final feelings = raw is Map ? raw[kGroupStartingFeelingsKey] : null;
    if (feelings is! Map) return {};
    return {
      for (final e in feelings.entries)
        if (e.value is Map)
          '${e.key}': {
            for (final r in (e.value as Map).entries)
              if (r.value is num) '${r.key}': (r.value as num).toInt(),
          },
    };
  } catch (_) {
    return {};
  }
}

/// [definitionJson] with [from]'s feeling toward [to] set to [score].
/// Nothing else in the blob moves, and no member seed is created: a feeling
/// never switches Realism on for a group.
String withStartingFeeling(
  String definitionJson, {
  required String from,
  required String to,
  required int score,
}) {
  Map<String, dynamic> map;
  try {
    final raw = jsonDecode(definitionJson);
    map = raw is Map ? Map<String, dynamic>.from(raw) : {};
  } catch (_) {
    map = {};
  }
  final all = startingFeelingsIn(definitionJson);
  all[from] = {...?all[from], to: score.clamp(-300, 300)};
  map[kGroupStartingFeelingsKey] = all;
  return jsonEncode(map);
}

/// The seeds a new chat of a group starts its members from: the group's
/// stored seeds ([stored], the definition's `perChar`) with each member's
/// own copy laid over them. A member whose copy holds a start of its own
/// (bonds or mood moved off the defaults, edited with the 1:1 controls in
/// their card) starts there; one whose copy is untouched keeps the start an
/// older group saved for them, when it saved one. A member whose copy has
/// Realism on and no stored seed gets the seed their copy starts them at, so
/// Realism for new chats follows each member's own switch. A copy with
/// Needs off starts without bars. The group's starting feelings
/// ([definitionJson]) join each seed's `relationships`.
Map<String, Map<String, dynamic>> memberStartSeeds(
  Map<String, Map<String, dynamic>> stored,
  Iterable<OverlayMember> members, {
  required String definitionJson,
}) {
  final out = {
    for (final e in stored.entries) e.key: Map<String, dynamic>.from(e.value),
  };
  final feelings = startingFeelingsIn(definitionJson);
  for (final m in members) {
    final ext = m.ext;
    final legacy = out[m.mid];
    if (ext == null) continue;
    if (legacy == null && !ext.realismEnabled) continue;
    final copy = groupMemberStartingSeed(ext);
    final seed = <String, dynamic>{...copy, ...?legacy};
    if (legacy != null && _hasBonds(legacy) && _startUntouched(ext)) {
      // The older group's start stands: nothing of the copy's start moves it.
    } else {
      for (final k in const [
        GroupRealismKeys.affection,
        GroupRealismKeys.longTermScore,
        GroupRealismKeys.trust,
        GroupRealismKeys.emotion,
        GroupRealismKeys.emotionIntensity,
      ]) {
        seed[k] = copy[k];
      }
    }
    if (legacy == null && ext.needsSimChoice == false) seed.remove('needs');
    final mine = feelings[m.mid];
    if (mine != null && mine.isNotEmpty) {
      seed['relationships'] = <String, int>{
        for (final r in ((seed['relationships'] as Map?) ?? const {}).entries)
          '${r.key}': (r.value as num).toInt(),
        ...mine,
      };
    }
    out[m.mid] = seed;
  }
  return out;
}
