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

/// Same library card. Ids decide when both cards have one, so a rename
/// still matches and two cards that share a name stay apart. Names decide
/// only for sessions saved before cards carried an id.
bool waifuSameCard(CharacterCard a, CharacterCard b) {
  final ia = a.dbId;
  final ib = b.dbId;
  if (ia != null && ib != null) return ia == ib;
  return a.name == b.name;
}

/// [coworker]'s card in [cards], or null when it is gone. A coworker with
/// an id never falls back to a different card that happens to share its
/// name.
CharacterCard? waifuFindCard(
  Iterable<CharacterCard> cards,
  CharacterCard coworker,
) {
  final id = coworker.dbId;
  for (final c in cards) {
    if (id != null ? c.dbId == id : c.name == coworker.name) return c;
  }
  return null;
}
