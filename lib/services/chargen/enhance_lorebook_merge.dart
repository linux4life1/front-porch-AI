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

import 'package:front_porch_ai/models/models.dart';

/// Append [incoming] onto [original], replacing an existing entry when
/// the incoming name is non-empty and already present. Enhance Review
/// must never assign the proposal as the whole book — the duplicate
/// already carries the original entries.
List<LorebookEntry> mergeLorebookEntries(
  List<LorebookEntry> original,
  List<LorebookEntry> incoming,
) {
  final out = List<LorebookEntry>.from(original);
  for (final entry in incoming) {
    final name = entry.name.trim();
    final i = name.isEmpty ? -1 : out.indexWhere((e) => e.name.trim() == name);
    if (i >= 0) {
      out[i] = entry;
    } else {
      out.add(entry);
    }
  }
  return out;
}
