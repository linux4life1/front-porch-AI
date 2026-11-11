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

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character/front_porch_extensions.dart';
import 'package:front_porch_ai/models/group_member.dart';
import 'package:front_porch_ai/services/chat/group_lite.dart'
    show encodeMemberFrontPorch;
import 'package:front_porch_ai/services/group_member_start.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

/// The member copy [ext] with what group [definitionJson] stored for member
/// [mid] (their `perChar` seed, under [mid] or their origin key
/// [originId]) written onto it: Realism on only when they had a seed, their
/// bonds and mood, Needs on only when the seed held bars (and the bars'
/// baselines), and the group-wide Afterglow and Pockets defaults when those
/// were off. A group that stored nothing for them leaves them with Realism
/// off, as its new chats started them. Running it again changes nothing.
FrontPorchExtensions memberCopyFromGroupSeed(
  FrontPorchExtensions? ext,
  String definitionJson,
  String mid, {
  String? originId,
}) {
  final base = ext ?? FrontPorchExtensions();
  final seeds = parseGroupRealismSeeds(definitionJson);
  final seed = seeds[mid] ?? (originId == null ? null : seeds[originId]);
  var out = base.copyWith(realismEnabled: seed != null);
  if (!groupAfterglowIn(definitionJson)) {
    out = out.copyWith(afterglowEnabled: false);
  }
  if (!groupPocketsIn(definitionJson)) {
    out = out.copyWith(pocketsEnabled: false);
  }
  if (seed == null) return out;
  final start = groupMemberStartOfSeed(seed);
  int? bar(String need) {
    final v = seed['needsBaseline${need[0].toUpperCase()}${need.substring(1)}'];
    return v is num ? v.toInt().clamp(0, 100) : null;
  }

  final needs = seed['needs'];
  return out.copyWith(
    shortTermBond: start.shortTerm,
    longTermBond: start.longTerm,
    trustLevel: start.trust,
    characterEmotion: start.emotion,
    emotionIntensity: start.emotionIntensity,
    needsSimEnabled: needs is Map && needs.isNotEmpty,
    needsBaselineHunger: bar('hunger'),
    needsBaselineBladder: bar('bladder'),
    needsBaselineEnergy: bar('energy'),
    needsBaselineSocial: bar('social'),
    needsBaselineFun: bar('fun'),
    needsBaselineHygiene: bar('hygiene'),
    needsBaselineComfort: bar('comfort'),
    enjoysLowHygiene: seed['enjoysLowHygiene'] is bool
        ? seed['enjoysLowHygiene'] as bool
        : null,
    needsPace: seed['needsPace'] is String ? seed['needsPace'] as String : null,
    needsOff: seed['needsOff'] is List
        ? [for (final n in seed['needsOff'] as List) '$n']
        : null,
  );
}

/// Writes group [groupId]'s stored per-member start onto each member's own
/// copy ([memberCopyFromGroupSeed]). The upgrade runs it for every group; a
/// group made or imported afterwards runs it once its members exist, so the
/// start the creator chose is on the copies new chats read.
Future<void> moveGroupSeedsOntoMembers(
  AppDatabase db,
  String groupId,
  String definitionJson,
) async {
  for (final row in await db.getGroupMembers(groupId)) {
    FrontPorchExtensions? ext;
    final raw = row.frontPorchExtensions;
    if (raw != null && raw.isNotEmpty) {
      try {
        ext = FrontPorchExtensions.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        continue; // Unreadable extensions stay as they are.
      }
    }
    final next = memberCopyFromGroupSeed(
      ext,
      definitionJson,
      row.id,
      originId: GroupMember.fromRow(row).originStableId,
    );
    await db.updateGroupMember(
      GroupMembersCompanion(
        id: Value(row.id),
        frontPorchExtensions: Value(encodeMemberFrontPorch(next)),
      ),
    );
  }
}

/// One-time upgrade step (schema v67): every group's stored per-member
/// start moves onto that member's own copy, so existing groups start new
/// chats as they did and runtime reads the member copy only.
Future<void> migrateGroupSeedsToMemberCopies(AppDatabase db) async {
  try {
    for (final group in await db.getAllGroups()) {
      await moveGroupSeedsOntoMembers(
        db,
        group.id,
        group.defaultMemberRealismState,
      );
    }
  } catch (e) {
    debugPrint('[DB] v67: group seeds were not moved onto members: $e');
  }
}
