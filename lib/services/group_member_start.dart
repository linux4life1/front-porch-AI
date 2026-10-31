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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show GroupRealismKeys;
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/member_baseline_seed.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Where a group member starts in new chats of their group: the bonds and
/// mood their seed in the group's definition holds (`perChar` in
/// `defaultMemberRealismState`, and the member's `baselineRealismState`
/// entry). The same seed the new-group wizard and Edit group's Realism tab
/// write. Never the member card's own extensions, and never a chat that
/// already exists: each chat keeps the state it has.
class GroupMemberStart {
  const GroupMemberStart({
    required this.shortTerm,
    required this.longTerm,
    required this.trust,
    required this.emotion,
    required this.emotionIntensity,
  });

  final int shortTerm;
  final int longTerm;
  final int trust;
  final String emotion;
  final String emotionIntensity;

  GroupMemberStart copyWith({
    int? shortTerm,
    int? longTerm,
    int? trust,
    String? emotion,
    String? emotionIntensity,
  }) => GroupMemberStart(
    shortTerm: shortTerm ?? this.shortTerm,
    longTerm: longTerm ?? this.longTerm,
    trust: trust ?? this.trust,
    emotion: emotion ?? this.emotion,
    emotionIntensity: emotionIntensity ?? this.emotionIntensity,
  );

  /// The web editor's field names (the 1:1 card's).
  Map<String, dynamic> toJson() => {
    'shortTermBond': shortTerm,
    'longTermBond': longTerm,
    'trustLevel': trust,
    'characterEmotion': emotion,
    'emotionIntensity': emotionIntensity,
  };

  /// [json] over [base]: a field missing or of the wrong type keeps [base]'s.
  static GroupMemberStart fromJson(Object? json, GroupMemberStart base) {
    if (json is! Map) return base;
    int? n(String k) => json[k] is num ? (json[k] as num).toInt() : null;
    String? s(String k) => json[k] is String ? json[k] as String : null;
    return GroupMemberStart(
      shortTerm: (n('shortTermBond') ?? base.shortTerm).clamp(-300, 300),
      longTerm: (n('longTermBond') ?? base.longTerm).clamp(-300, 300),
      trust: (n('trustLevel') ?? base.trust).clamp(-100, 100),
      emotion: s('characterEmotion') ?? base.emotion,
      emotionIntensity: emotionIntensityFromSeed(
        s('emotionIntensity') ?? base.emotionIntensity,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GroupMemberStart &&
      other.shortTerm == shortTerm &&
      other.longTerm == longTerm &&
      other.trust == trust &&
      other.emotion == emotion &&
      other.emotionIntensity == emotionIntensity;

  @override
  int get hashCode =>
      Object.hash(shortTerm, longTerm, trust, emotion, emotionIntensity);
}

/// Member [mid]'s start in a group whose definition holds
/// [defaultMemberJson]. A member with no seed of their own reads from their
/// card's extensions [card], as Edit group's Realism tab shows them. Null
/// when the definition has no member seeds at all: the group's new chats
/// start without Realism, so there is no start to set.
GroupMemberStart? groupMemberStartIn(
  String defaultMemberJson,
  String mid, {
  FrontPorchExtensions? card,
}) {
  final Map<String, Map<String, dynamic>> seeds;
  try {
    seeds = parseGroupRealismSeeds(defaultMemberJson);
  } catch (_) {
    return null;
  }
  if (seeds.isEmpty) return null;
  return groupMemberStartOfSeed(seeds[mid] ?? groupMemberStartingSeed(card));
}

/// The start a member's [seed] (their `perChar` entry) holds. Long-Term
/// Bond saved into `trust` by the old editors reads back where it belongs
/// (see [bondSlidersFromMemberSeed]).
GroupMemberStart groupMemberStartOfSeed(Map<String, dynamic> seed) {
  final bonds = bondSlidersFromMemberSeed(seed);
  final emotion = seed[GroupRealismKeys.emotion];
  return GroupMemberStart(
    shortTerm: bonds.shortTerm,
    longTerm: bonds.longTerm,
    trust: bonds.trust,
    emotion: emotion is String && emotion.trim().isNotEmpty
        ? emotion
        : 'neutral',
    emotionIntensity: emotionIntensityFromSeed(
      seed[GroupRealismKeys.emotionIntensity],
    ),
  );
}

/// The two group realism blobs with member [mid]'s start set to [start].
/// Every other key of their seed, and every other member, is kept. A
/// definition with no member seeds comes back as it is: a seed there would
/// switch Realism on for the group's new chats.
({String defaultMemberJson, String baselineJson}) withGroupMemberStart({
  required String defaultMemberJson,
  required String baselineJson,
  required String mid,
  required GroupMemberStart start,
  FrontPorchExtensions? card,
}) {
  final unchanged = (
    defaultMemberJson: defaultMemberJson,
    baselineJson: baselineJson,
  );
  final Map<String, dynamic> definition;
  try {
    if (parseGroupRealismSeeds(defaultMemberJson).isEmpty) return unchanged;
    definition = Map<String, dynamic>.from(
      jsonDecode(defaultMemberJson) as Map,
    );
  } catch (_) {
    return unchanged;
  }
  final perChar = Map<String, dynamic>.from(definition['perChar'] as Map);
  final seed = perChar[mid] is Map
      ? Map<String, dynamic>.from(perChar[mid] as Map)
      : groupMemberStartingSeed(card);
  perChar[mid] = applyBaselineToMemberSeed(
    seed,
    affection: start.shortTerm,
    longTermScore: start.longTerm,
    trust: start.trust,
    emotion: start.emotion,
    emotionIntensity: start.emotionIntensity,
  );
  definition['perChar'] = perChar;

  Map<String, dynamic> baseline;
  try {
    final decoded = baselineJson.isEmpty ? null : jsonDecode(baselineJson);
    baseline = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  } catch (_) {
    baseline = <String, dynamic>{};
  }
  final time = parseGroupTimeSeed(defaultMemberJson, baselineJson);
  baseline[mid] = {
    'timeOfDay': time?.timeOfDay ?? 'morning',
    'dayCount': time?.dayCount ?? 1,
    if (baseline[mid] is Map) ...Map<String, dynamic>.from(baseline[mid]),
    GroupRealismKeys.affection: start.shortTerm,
    GroupRealismKeys.longTermScore: start.longTerm,
    GroupRealismKeys.trust: start.trust,
    GroupRealismKeys.emotion: start.emotion,
    GroupRealismKeys.emotionIntensity: start.emotionIntensity,
  };
  return (
    defaultMemberJson: jsonEncode(definition),
    baselineJson: jsonEncode(baseline),
  );
}

/// Saves member [mid]'s [start] into group [groupId]'s definition, onto the
/// blobs stored now (an editor holding an older copy writes only the start),
/// and into the open chat's copy of the group when it is that group, so its
/// next New Chat starts there. Returns the blobs written, or null when the
/// group has no member seeds (nothing is written).
Future<({String defaultMemberJson, String baselineJson})?> saveGroupMemberStart(
  AppDatabase db, {
  required String groupId,
  required String mid,
  required GroupMemberStart start,
  FrontPorchExtensions? card,
  ChatService? chat,
}) async {
  final row = await db.getGroupById(groupId);
  if (row == null) throw StateError('no group $groupId');
  final next = withGroupMemberStart(
    defaultMemberJson: row.defaultMemberRealismState,
    baselineJson: row.baselineRealismState,
    mid: mid,
    start: start,
    card: card,
  );
  if (next.defaultMemberJson == row.defaultMemberRealismState) return null;
  await db.updateGroup(
    GroupsCompanion(
      id: Value(groupId),
      defaultMemberRealismState: Value(next.defaultMemberJson),
      baselineRealismState: Value(next.baselineJson),
      updatedAt: Value(DateTime.now()),
    ),
  );
  final open = chat?.activeGroup;
  if (open != null && open.id == groupId) {
    final live = withGroupMemberStart(
      defaultMemberJson: open.defaultMemberRealismState,
      baselineJson: open.baselineRealismState,
      mid: mid,
      start: start,
      card: card,
    );
    open
      ..defaultMemberRealismState = live.defaultMemberJson
      ..baselineRealismState = live.baselineJson;
  }
  return next;
}
