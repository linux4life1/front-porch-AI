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

/// The entry member [mid] has in a member-keyed group [store]: their own,
/// or one a group made before the id-keying fix filed under one of
/// [legacyIds] (the member's origin or name key), as Edit group's Realism
/// tab finds it.
Map<String, dynamic>? _ownEntry(
  Map<String, dynamic> store,
  String mid,
  Iterable<String> legacyIds,
) {
  for (final key in [mid, ...legacyIds]) {
    final v = store[key];
    if (v is Map) return Map<String, dynamic>.from(v);
  }
  return null;
}

/// Whether [seed] holds the bonds a new chat starts a member from (the
/// wizard, Edit group and this editor always write them). An entry without
/// them (a Group Settings preference, an older editor's card-named keys,
/// an imported card's mood and bars) still makes the group's new chats run
/// Realism, as every other reader of the blob has it; its member starts
/// from their card, with what the entry does hold kept over it.
bool _hasBonds(Map<String, dynamic> seed) =>
    seed.containsKey(GroupRealismKeys.affection) ||
    seed.containsKey(GroupRealismKeys.longTermScore) ||
    seed.containsKey(GroupRealismKeys.trust);

/// Member [mid]'s entry as a start seed: their own when it has bonds, else
/// one from their card's extensions [card] with anything their entry does
/// hold kept over it, and whether it was built fresh.
({Map<String, dynamic> seed, bool fresh}) _startSeedOf(
  Map<String, dynamic> perChar,
  String mid,
  Iterable<String> legacyIds,
  FrontPorchExtensions? card,
) {
  final own = _ownEntry(perChar, mid, legacyIds);
  if (own != null && _hasBonds(own)) return (seed: own, fresh: false);
  return (seed: {...groupMemberStartingSeed(card), ...?own}, fresh: true);
}

/// Member [mid]'s start in a group whose definition holds
/// [defaultMemberJson]. A member with no seed of their own (under [mid] or
/// a [legacyIds] key) reads from their card's extensions [card], as Edit
/// group's Realism tab shows them. Null when the definition has no member
/// entries at all: the group's new chats start without Realism (the rule
/// New Chat, Edit group and Group Settings read), so there is no start.
/// Callers pass the PERSISTED definition (the group's row, or the template
/// Edit group holds), never an open chat's copy, which can carry Group
/// Settings edits not saved yet.
GroupMemberStart? groupMemberStartIn(
  String defaultMemberJson,
  String mid, {
  FrontPorchExtensions? card,
  Iterable<String> legacyIds = const [],
}) {
  final Map<String, Map<String, dynamic>> seeds;
  try {
    seeds = parseGroupRealismSeeds(defaultMemberJson);
  } catch (_) {
    return null;
  }
  if (seeds.isEmpty) return null;
  return groupMemberStartOfSeed(_startSeedOf(seeds, mid, legacyIds, card).seed);
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
/// Every other key of their seed, and every other member, is kept. A seed
/// filed under one of [legacyIds] moves onto [mid] (and other members'
/// feelings toward it follow), so nothing it holds is dropped later. A
/// member with no seed gets one from their [card], without its Needs bars
/// while the group's new chats run without Needs: a seed with bars reads as
/// Needs on. A definition with no member entries comes back as it is: an
/// entry there would switch Realism on for the group's new chats.
({String defaultMemberJson, String baselineJson}) withGroupMemberStart({
  required String defaultMemberJson,
  required String baselineJson,
  required String mid,
  required GroupMemberStart start,
  FrontPorchExtensions? card,
  Iterable<String> legacyIds = const [],
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
  final legacy = [
    for (final id in legacyIds)
      if (id.isNotEmpty && id != mid) id,
  ];
  final (:seed, :fresh) = _startSeedOf(perChar, mid, legacy, card);
  if (fresh && !groupTemplateRealismOf(defaultMemberJson).needsOn) {
    seed.remove('needs');
  }
  for (final id in legacy) {
    perChar.remove(id);
  }
  if (legacy.isNotEmpty) {
    for (final entry in perChar.entries.toList()) {
      final other = entry.value;
      final rels = other is Map ? other['relationships'] : null;
      if (rels is! Map || !rels.keys.any((k) => legacy.contains('$k'))) {
        continue;
      }
      perChar[entry.key] = {
        ...Map<String, dynamic>.from(other as Map),
        'relationships': {
          for (final r in rels.entries)
            legacy.contains('${r.key}') ? mid : '${r.key}': r.value,
        },
      };
    }
  }
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
  final ownBaseline = _ownEntry(baseline, mid, legacy);
  for (final id in legacy) {
    baseline.remove(id);
  }
  baseline[mid] = {
    'timeOfDay': time?.timeOfDay ?? 'morning',
    'dayCount': time?.dayCount ?? 1,
    ...?ownBaseline,
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

/// The keys a group made before the id-keying fix may have filed member
/// [mid]'s entries under: the library character they were copied from, as
/// their row records it.
Future<List<String>> groupMemberLegacyKeys(
  AppDatabase db,
  String groupId,
  String mid,
) async {
  for (final row in await db.getGroupMembers(groupId)) {
    if (row.id != mid) continue;
    final origin = GroupMember.fromRow(row).originStableId;
    return [if (origin != null && origin.isNotEmpty) origin];
  }
  return const [];
}

/// Saves member [mid]'s [start] into group [groupId]'s definition, onto the
/// blobs stored now: only the member's own entries change (an editor
/// holding an older copy, or an open chat holding Group Settings edits not
/// saved yet, writes nothing else). When the row is written, the open
/// chat's copy of the group, when it is that group, gets the same start, so
/// its next New Chat starts there and its own later save keeps it. A seed
/// under the member's origin key (from their row) or one of [legacyIds]
/// moves onto [mid].
///
/// A row with no member entries (its new chats run without Realism) is
/// never written, and neither is the open copy then. Returns the blobs
/// written to the row, or null when nothing was written.
Future<({String defaultMemberJson, String baselineJson})?> saveGroupMemberStart(
  AppDatabase db, {
  required String groupId,
  required String mid,
  required GroupMemberStart start,
  FrontPorchExtensions? card,
  ChatService? chat,
  Iterable<String> legacyIds = const [],
}) async {
  final row = await db.getGroupById(groupId);
  if (row == null) throw StateError('no group $groupId');
  final keys = {...legacyIds, ...await groupMemberLegacyKeys(db, groupId, mid)};
  ({String defaultMemberJson, String baselineJson}) onto(String d, String b) =>
      withGroupMemberStart(
        defaultMemberJson: d,
        baselineJson: b,
        mid: mid,
        start: start,
        card: card,
        legacyIds: keys,
      );
  final next = onto(row.defaultMemberRealismState, row.baselineRealismState);
  if (next.defaultMemberJson == row.defaultMemberRealismState) return null;
  await db.updateGroup(
    GroupsCompanion(
      id: Value(groupId),
      defaultMemberRealismState: Value(next.defaultMemberJson),
      baselineRealismState: Value(next.baselineJson),
      updatedAt: Value(DateTime.now()),
    ),
  );
  final candidate = chat?.activeGroup;
  if (candidate != null && candidate.id == groupId) {
    final live = onto(
      candidate.defaultMemberRealismState,
      candidate.baselineRealismState,
    );
    candidate
      ..defaultMemberRealismState = live.defaultMemberJson
      ..baselineRealismState = live.baselineJson;
  }
  return next;
}
