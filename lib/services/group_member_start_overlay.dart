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

/// The seeds a new chat of a group starts its members from: each member's
/// own copy ([memberCopyFromGroupSeed] moved an older group's stored start
/// onto it once; one with no extensions record at all keeps the stored seed).
/// Realism for the new chat follows whether any member's copy
/// has Realism on; a copy with Needs off starts without bars. Only the
/// hidden feelings still come from the group: its starting feelings
/// ([definitionJson]) over a seed's older `relationships` map.
Map<String, Map<String, dynamic>> memberStartSeeds(
  Map<String, Map<String, dynamic>> stored,
  Iterable<OverlayMember> members, {
  required String definitionJson,
}) {
  final out = <String, Map<String, dynamic>>{};
  final feelings = startingFeelingsIn(definitionJson);
  for (final m in members) {
    final ext = m.ext;
    if (ext == null) {
      // A copy with no extensions record at all (never saved by an editor,
      // never moved by the upgrade) has no start of its own: the group's
      // stored seed for them stands.
      final legacy = stored[m.mid];
      if (legacy != null) out[m.mid] = Map<String, dynamic>.of(legacy);
      continue;
    }
    if (!ext.realismEnabled) continue;
    final seed = groupMemberStartingSeed(ext);
    if (ext.needsSimChoice == false) seed.remove('needs');
    final rels = <String, int>{
      for (final r
          in ((stored[m.mid]?['relationships'] as Map?) ?? const {}).entries)
        if (r.value is num) '${r.key}': (r.value as num).toInt(),
      ...?feelings[m.mid],
    };
    if (rels.isNotEmpty) seed['relationships'] = rels;
    out[m.mid] = seed;
  }
  return out;
}
