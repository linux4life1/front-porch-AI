// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';

/// Cast-list roles for a world-from-wiki shelf. Wiki-agnostic: the scout
/// emits these for *this* index. Not chargen categories.
enum WorldCraftRole { era, hub, leaf, crown }

WorldCraftRole? parseWorldCraftRole(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'era':
      return WorldCraftRole.era;
    case 'hub':
      return WorldCraftRole.hub;
    case 'leaf':
      return WorldCraftRole.leaf;
    case 'crown':
      return WorldCraftRole.crown;
    default:
      return null;
  }
}

/// One scout-proposed card. Default unsigned; the user signs a shelf.
class WorldProposedCard {
  const WorldProposedCard({
    required this.name,
    required this.keys,
    required this.role,
    required this.sourceTitles,
    this.group = '',
  });

  final String name;
  final List<String> keys;
  final WorldCraftRole role;
  final List<String> sourceTitles;
  final String group;

  Map<String, dynamic> toJson() => {
    'name': name,
    'keys': keys,
    'role': role.name,
    'sourceTitles': sourceTitles,
    if (group.isNotEmpty) 'group': group,
  };

  static WorldProposedCard? tryParse(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    final role = parseWorldCraftRole(json['role']?.toString());
    if (role == null) return null;
    final sources = _stringList(
      json['sourceTitles'] ?? json['source_titles'],
      max: 3,
    );
    if (sources.isEmpty) return null;
    final keys = _stringList(json['keys']);
    final group = json['group']?.toString().trim() ?? '';
    return WorldProposedCard(
      name: name,
      keys: keys.isEmpty ? [name] : keys,
      role: role,
      sourceTitles: sources,
      group: group,
    );
  }
}

/// Written prose plus the signed role/group from the scout card.
class WorldCraftDraft {
  const WorldCraftDraft({
    required this.name,
    required this.keys,
    required this.content,
    required this.role,
    this.group = '',
  });

  final String name;
  final List<String> keys;
  final String content;
  final WorldCraftRole role;
  final String group;

  WorldCraftDraft copyWith({WorldCraftRole? role, String? group}) {
    return WorldCraftDraft(
      name: name,
      keys: keys,
      content: content,
      role: role ?? this.role,
      group: group ?? this.group,
    );
  }
}

/// Insertion `order` for a role at [index] among [count] siblings.
int worldCraftOrderFor(
  WorldCraftRole role, {
  required int index,
  required int count,
}) {
  if (role == WorldCraftRole.era) return 1;
  final (lo, hi) = switch (role) {
    WorldCraftRole.hub => (145, 210),
    WorldCraftRole.leaf => (60, 140),
    WorldCraftRole.crown => (240, 250),
    WorldCraftRole.era => (1, 1),
  };
  if (count <= 1) return (lo + hi) ~/ 2;
  final clamped = index.clamp(0, count - 1);
  return lo + (((hi - lo) * clamped) / (count - 1)).round();
}

/// Map signed drafts to lorebook entries. Does **not** call chargen
/// [assignLoreMechanics]. At most one era. Group string is whatever the
/// scout emitted for this book. Highest order in a group wins
/// (`groupOverride`). Never hub+crown in one group. Depth 4. No regex.
List<LorebookEntry> applyWorldCraftMechanics(List<WorldCraftDraft> drafts) {
  final usable = [
    for (final d in drafts)
      if (d.content.trim().isNotEmpty) d,
  ];
  var eraUsed = false;
  final normalized = <WorldCraftDraft>[];
  for (final d in usable) {
    var role = d.role;
    if (role == WorldCraftRole.era) {
      if (eraUsed) {
        role = WorldCraftRole.hub;
      } else {
        eraUsed = true;
      }
    }
    final group = role == WorldCraftRole.era ? '' : d.group.trim();
    normalized.add(d.copyWith(role: role, group: group));
  }
  final crownGroups = {
    for (final d in normalized)
      if (d.role == WorldCraftRole.crown && d.group.isNotEmpty) d.group,
  };
  final split = [
    for (final d in normalized)
      if (d.role == WorldCraftRole.hub && crownGroups.contains(d.group))
        d.copyWith(group: '')
      else
        d,
  ];

  final counts = <WorldCraftRole, int>{};
  final seen = <WorldCraftRole, int>{};
  for (final d in split) {
    counts[d.role] = (counts[d.role] ?? 0) + 1;
  }

  final entries = <LorebookEntry>[];
  for (final d in split) {
    final i = seen[d.role] ?? 0;
    seen[d.role] = i + 1;
    final order = worldCraftOrderFor(
      d.role,
      index: i,
      count: counts[d.role] ?? 1,
    );
    final group = d.group;
    final constant = d.role == WorldCraftRole.era;
    final ignoreBudget = d.role == WorldCraftRole.era;
    final preventRecursion = d.role != WorldCraftRole.hub;
    final sticky = switch (d.role) {
      WorldCraftRole.era => 0,
      WorldCraftRole.hub => 3,
      WorldCraftRole.leaf || WorldCraftRole.crown => 2,
    };
    debugPrint(
      '[World] mechanics name=${d.name} role=${d.role.name} '
      'const=$constant prevR=$preventRecursion sticky=$sticky '
      'order=$order group=$group',
    );
    entries.add(
      LorebookEntry(
        name: d.name,
        keys: d.keys,
        content: d.content.trim(),
        enabled: true,
        constant: constant,
        ignoreBudget: ignoreBudget,
        preventRecursion: preventRecursion,
        sticky: sticky,
        order: order,
        group: group,
        groupOverride: group.isNotEmpty,
        depth: 4,
        useRegex: false,
        probability: 100,
      ),
    );
  }
  return entries;
}

List<String> _stringList(dynamic raw, {int max = 24}) {
  final out = <String>[];
  if (raw is List) {
    for (final e in raw) {
      final s = e.toString().trim();
      if (s.isEmpty) continue;
      out.add(s);
      if (out.length >= max) break;
    }
    return out;
  }
  if (raw is String && raw.trim().isNotEmpty) {
    for (final part in raw.split(',')) {
      final s = part.trim();
      if (s.isEmpty) continue;
      out.add(s);
      if (out.length >= max) break;
    }
  }
  return out;
}
