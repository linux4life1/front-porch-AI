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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/pages/repository/stoop_card_sections.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Group-level sections for the Stoop detail panel — the "overview" shown above
/// the per-member carousel: the group's own scenario / greeting / system prompt,
/// its group lorebook, and the pre-seeded intra-group dynamics (per-character
/// realism baseline + inter-character relationships). Reuses the shared
/// per-character primitives from stoop_card_sections.dart.

/// The group's own top-of-panel overview. Member-specific detail lives in the
/// carousel below this (built by the page).
List<Widget> stoopGroupOverview(
  BuildContext context,
  Map<String, dynamic> card,
  String name,
) {
  final to = (card['turn_order'] ?? card['turnOrder'] ?? 'roundRobin')
      .toString();
  final mode = to == 'random' ? 'Random' : 'Round Robin';
  final members =
      (card['raw_member_data'] as List?) ??
      (card['members'] as List?) ??
      const [];
  String s(String key) =>
      stoopResolveMacros((card[key] ?? '').toString(), name);
  return [
    stoopTextSection(
      context,
      'Group',
      '$mode · ${members.length} character${members.length == 1 ? '' : 's'}',
    ),
    stoopTextSection(context, 'Group scenario', s('scenario')),
    stoopTextSection(context, 'Group greeting', s('first_message')),
    stoopGroupDynamicsSection(context, card),
    _groupLorebookSection(context, card, name),
    stoopTextSection(context, 'Group system prompt', s('system_prompt')),
  ];
}

/// The pre-seeded per-character realism baseline + inter-character relationships
/// ("Group Dynamics") carried in `default_member_realism_state`. Empty when the
/// group has no seeded per-character state.
Widget stoopGroupDynamicsSection(
  BuildContext context,
  Map<String, dynamic> card,
) {
  final blob =
      _asMap(card['default_member_realism_state']) ??
      _asMap(card['baseline_realism_state']) ??
      _asMap(card['realism_state']);
  final perChar = _asMap(blob?['perChar']);
  if (perChar == null || perChar.isEmpty) return const SizedBox.shrink();
  final names = _groupMemberNames(card);
  String nm(String id) => names[id] ?? id;

  final rows = <Widget>[];
  for (final entry in perChar.entries) {
    final b = _asMap(entry.value) ?? const {};
    final bond = b['affection'] ?? b['short_term_bond'] ?? b['bond'] ?? 0;
    final trust = b['trust'] ?? b['trust_level'] ?? 0;
    final emotion = (b['emotion'] ?? '').toString();
    final rel = _asMap(b['relationships']) ?? const {};
    rows.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nm(entry.key),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Bond $bond · Trust $trust'
              '${emotion.isNotEmpty ? ' · $emotion' : ''}',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 13,
              ),
            ),
            for (final r in rel.entries)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  '→ ${nm(r.key)}: ${_relationshipText(r.value)}',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  return StoopCollapsible(
    title: 'Group dynamics (pre-seeded)',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
  );
}

// The group-level lorebook (separate from members' own), parsed from the
// `group_lorebook` JSON string. Empty when there are no entries.
Widget _groupLorebookSection(
  BuildContext context,
  Map<String, dynamic> card,
  String name,
) {
  final lb = _asMap(card['group_lorebook']);
  final entries =
      (lb?['entries'] as List?)?.whereType<Map>().toList() ?? const [];
  if (entries.isEmpty) return const SizedBox.shrink();
  return stoopLorebookEntries(
    context,
    'Group lorebook (${entries.length})',
    entries,
    name,
  );
}

// A relationship value may be a scalar or a small blob; render it compactly.
String _relationshipText(dynamic v) {
  final m = _asMap(v);
  if (m != null) {
    final feeling = m['feeling'] ?? m['affection'] ?? m['bond'] ?? m['value'];
    return feeling?.toString() ?? m.toString();
  }
  return v?.toString() ?? '';
}

// Map a realism-state char id (the export's _original_stable_id) to a member
// name so dynamics read in plain language instead of raw ids.
Map<String, String> _groupMemberNames(Map<String, dynamic> card) {
  final out = <String, String>{};
  final rmd = card['raw_member_data'];
  if (rmd is List) {
    for (final m in rmd) {
      if (m is Map) {
        final id = (m['_original_stable_id'] ?? '').toString();
        final nm = (m['name'] ?? '').toString();
        if (id.isNotEmpty && nm.isNotEmpty) out[id] = nm;
      }
    }
  }
  return out;
}

// Coerce a value that may be a Map or a JSON string into a Map (or null).
Map<String, dynamic>? _asMap(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String && v.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(v);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}
