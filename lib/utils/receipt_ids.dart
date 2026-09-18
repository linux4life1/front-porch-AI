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

/// Decode a `source_message_ids` column into message positions.
///
/// Journal cards and Growth rings both store their receipts this way, and the
/// desktop diary, the desktop rings panel and the web relay all render them. A
/// receipt that one surface accepts and another drops is a card that has
/// tappable pills in the browser and none in the app, so they read the column
/// the same way here.
///
/// Tolerant on purpose: a position that survived a JSON round-trip may arrive
/// as `12.0` or `"12"`. Anything genuinely unreadable yields no receipts rather
/// than throwing — a card with a corrupt column should still be readable.
List<int> decodeReceiptIds(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final positions = <int>[];
    for (final entry in decoded) {
      if (entry is num) {
        positions.add(entry.toInt());
        continue;
      }
      final parsed = int.tryParse('$entry');
      if (parsed != null) positions.add(parsed);
    }
    return positions;
  } catch (_) {
    return const [];
  }
}
