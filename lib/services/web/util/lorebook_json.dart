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
/// (`[{name, key, content, enabled, constant, stickyDepth}]`) to/from the
/// [Lorebook] model. Shared by the character and world facades so both author
/// lore identically.

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
    entries.add(LorebookEntry(
      name: e['name']?.toString() ?? '',
      key: key,
      content: content,
      enabled: e['enabled'] != false,
      constant: e['constant'] == true,
      stickyDepth: e['stickyDepth'] is int ? e['stickyDepth'] as int : 1,
    ));
  }
  return entries.isEmpty ? null : Lorebook(entries: entries);
}

/// Flatten a [Lorebook] to the web entry list (comma-joined `key` string).
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
          })
      .toList();
}
