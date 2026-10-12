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

/// [raw] decoded as a JSON list, or empty when it is not one.
List<dynamic> decodeJsonList(String raw) {
  try {
    final v = jsonDecode(raw);
    return v is List ? v : const [];
  } catch (_) {
    return const [];
  }
}

/// Normalize the DB lorebook blob (keys array / comment) into the frontend
/// shape (comma-joined key string / name), as the legacy detail handler did.
Map<String, dynamic>? normalizeLorebookJson(String? raw) {
  if (raw == null) return null;
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic> || parsed['entries'] is! List) {
      return parsed is Map<String, dynamic> ? parsed : null;
    }
    final entries = (parsed['entries'] as List).map((e) {
      if (e is! Map<String, dynamic>) return e;
      final keyStr = e['keys'] is List
          ? (e['keys'] as List).map((k) => k.toString()).join(', ')
          : (e['key']?.toString() ?? '');
      return {
        'name': e['comment']?.toString() ?? e['name']?.toString() ?? '',
        'key': keyStr,
        'content': e['content']?.toString() ?? '',
        'enabled': e['enabled'] ?? true,
        'constant': e['constant'] ?? false,
        'stickyDepth': e['sticky_depth'] ?? e['insertion_order'] ?? 1,
      };
    }).toList();
    return {'entries': entries};
  } catch (_) {
    return null;
  }
}
