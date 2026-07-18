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

import 'package:front_porch_ai/models/lorebook.dart';

/// Single source of truth for converting the web wizard's lorebook entry list
/// (`[{name, key, content, enabled, constant, stickyDepth, ext}]`) to/from
/// the [Lorebook] model. Shared by the character and world facades so both
/// author lore identically.
///
/// `ext` is the entry's full internal JSON. The web editor only exposes the
/// six simple fields, so it round-trips `ext` untouched — saving from the
/// web must never strip the advanced/imported ST metadata an entry carries.

/// Build a [Lorebook] from a web entry list, dropping rows with no key/content.
/// Returns null when the result is empty.
Lorebook? buildLorebookFromJson(dynamic raw) {
  if (raw is! List || raw.isEmpty) return null;
  final entries = <LorebookEntry>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final content = e['content']?.toString() ?? '';
    final key = e['key']?.toString() ?? '';
    if (content.trim().isEmpty && key.trim().isEmpty) continue;
    final ext = e['ext'];
    final entry = ext is Map
        ? LorebookEntry.fromJson(Map<String, dynamic>.from(ext))
        : LorebookEntry();
    entry.name = e['name']?.toString() ?? '';
    entry.keys = LorebookEntry.parseKeyList(key);
    entry.content = content;
    entry.enabled = e['enabled'] != false;
    entry.constant = e['constant'] == true;
    entry.stickyDepth = e['stickyDepth'] is int ? e['stickyDepth'] as int : 1;
    // Additive Simple-level fields (older web UIs simply omit them).
    if (e['probability'] is int) {
      entry.probability = (e['probability'] as int).clamp(0, 100);
      entry.useProbability = true;
    }
    if (e['position'] is int) {
      entry.position = (e['position'] as int).clamp(0, 6);
    }
    // Advanced tier (web parity with the desktop editor). Only keys PRESENT
    // in the row override — untouched fields keep their ext-decoded values.
    if (e['secondaryKeys'] is String) {
      entry.secondaryKeys =
          LorebookEntry.parseKeyList(e['secondaryKeys'] as String);
    }
    if (e['selectiveLogic'] is int) {
      entry.selectiveLogic = (e['selectiveLogic'] as int).clamp(0, 3);
    }
    if (e['useRegex'] is bool) entry.useRegex = e['useRegex'] as bool;
    if (e['order'] is int) entry.order = e['order'] as int;
    if (e['depth'] is int) entry.depth = (e['depth'] as int).clamp(0, 999);
    if (e['role'] is int) entry.role = (e['role'] as int).clamp(0, 2);
    if (e['sticky'] is int) entry.sticky = (e['sticky'] as int).clamp(0, 9999);
    if (e['cooldown'] is int) {
      entry.cooldown = (e['cooldown'] as int).clamp(0, 9999);
    }
    if (e['delay'] is int) entry.delay = (e['delay'] as int).clamp(0, 9999);
    if (e.containsKey('scanDepth')) {
      entry.scanDepth = e['scanDepth'] is int ? e['scanDepth'] as int : null;
    }
    if (e.containsKey('caseSensitive')) {
      entry.caseSensitive =
          e['caseSensitive'] is bool ? e['caseSensitive'] as bool : null;
    }
    if (e.containsKey('matchWholeWords')) {
      entry.matchWholeWords =
          e['matchWholeWords'] is bool ? e['matchWholeWords'] as bool : null;
    }
    if (e['excludeRecursion'] is bool) {
      entry.excludeRecursion = e['excludeRecursion'] as bool;
    }
    if (e['preventRecursion'] is bool) {
      entry.preventRecursion = e['preventRecursion'] as bool;
    }
    if (e['delayUntilRecursion'] is int) {
      entry.delayUntilRecursion =
          (e['delayUntilRecursion'] as int).clamp(0, 10);
    }
    if (e['group'] is String) entry.group = (e['group'] as String).trim();
    if (e['groupWeight'] is int) {
      entry.groupWeight = (e['groupWeight'] as int).clamp(1, 10000);
    }
    if (e['groupOverride'] is bool) {
      entry.groupOverride = e['groupOverride'] as bool;
    }
    if (e.containsKey('useGroupScoring')) {
      entry.useGroupScoring =
          e['useGroupScoring'] is bool ? e['useGroupScoring'] as bool : null;
    }
    if (e['ignoreBudget'] is bool) entry.ignoreBudget = e['ignoreBudget'] as bool;
    entries.add(entry);
  }
  return entries.isEmpty ? null : Lorebook(entries: entries);
}

/// Flatten a [Lorebook] to the web entry list (comma-joined `key` string,
/// plus the opaque `ext` blob the web editor round-trips).
List<Map<String, dynamic>> lorebookEntriesToJson(Lorebook? lorebook) {
  if (lorebook == null) return const [];
  return lorebook.entries
      .map((e) => {
            'name': e.name,
            'key': e.key,
            'content': e.content,
            'enabled': e.enabled,
            'constant': e.constant,
            'stickyDepth': e.stickyDepth,
            'probability': e.probability,
            'position': e.position,
            'secondaryKeys': e.secondaryKeys.join(', '),
            'selectiveLogic': e.selectiveLogic,
            'useRegex': e.useRegex,
            'order': e.order,
            'depth': e.depth,
            if (e.role != null) 'role': e.role,
            'sticky': e.sticky,
            'cooldown': e.cooldown,
            'delay': e.delay,
            'scanDepth': e.scanDepth,
            'caseSensitive': e.caseSensitive,
            'matchWholeWords': e.matchWholeWords,
            'excludeRecursion': e.excludeRecursion,
            'preventRecursion': e.preventRecursion,
            'delayUntilRecursion': e.delayUntilRecursion,
            'group': e.group,
            'groupWeight': e.groupWeight,
            'groupOverride': e.groupOverride,
            'useGroupScoring': e.useGroupScoring,
            'ignoreBudget': e.ignoreBudget,
            'ext': e.toJson(),
          })
      .toList();
}
