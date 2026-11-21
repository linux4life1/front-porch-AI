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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/web/facade/character/character_json.dart';

/// The library rows the web search [term] (lowercase) finds: by name, title
/// or tag, through the same rule as the desktop grid. Titles live on the
/// PNG-backed cards in [byDbId], not on the rows.
List<Character> searchCharacterRows(
  List<Character> rows,
  String term,
  Map<String, CharacterCard> byDbId,
) => [
  for (final c in rows)
    if (libraryEntryMatches(
      term,
      name: c.name,
      title: byDbId[c.id]?.title ?? '',
      tags: [for (final t in decodeJsonList(c.tags)) '$t'],
    ))
      c,
];

/// Sorts [rows] in place for the web list's [sort] key.
void sortCharacterRows(
  List<Character> rows,
  String sort, {
  required Map<String, int> msgCounts,
  required Map<String, DateTime> lastActivity,
}) {
  // Case-insensitive name comparison, reused as a stable tiebreak so equal
  // keys (no activity, no messages, no import date) keep a deterministic
  // order instead of jittering. Kept 1:1 with the desktop sort helper
  // (lib/utils/character_sort.dart).
  int byName(Character a, Character b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final epochZero = DateTime.fromMillisecondsSinceEpoch(0);
  switch (sort) {
    case 'recent':
      // Most recent turn first — by real per-character activity, not a bare
      // reversal of insertion order (which ignored activity entirely).
      rows.sort((a, b) {
        final at = lastActivity[a.id] ?? epochZero;
        final bt = lastActivity[b.id] ?? epochZero;
        final c = bt.compareTo(at);
        return c != 0 ? c : byName(a, b);
      });
    case 'messages':
      rows.sort((a, b) {
        final c = (msgCounts[b.id] ?? 0).compareTo(msgCounts[a.id] ?? 0);
        return c != 0 ? c : byName(a, b);
      });
    case 'importDate':
      // Newest first by the real DB createdAt (not the fragile filename
      // epoch, which was 0 for JSON/Chub/renamed cards).
      rows.sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : byName(a, b);
      });
    case 'name':
    default:
      rows.sort(byName);
  }
}
