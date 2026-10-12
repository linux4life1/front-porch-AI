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

// Caps and the one text tidy every pockets string goes through.

/// Longest item name and condition that will be kept. Items are things, not
/// paragraphs; a condition is a phrase ("half-eaten", "rain-soaked").
const kMaxItemNameChars = 60;
const kMaxItemStateChars = 60;

/// How many items a character may have in each list. The cap protects the
/// prompt, so it trims the COLDEST end (oldest) rather than refusing new ones:
/// a character who picks up a ninth thing should be holding it, and the first
/// thing they forgot about is what falls out.
const kMaxWorn = 8;
const kMaxCarrying = 8;

/// How many things may sit set aside at once — one full outfit plus one full
/// set of carried things, since a bulk undress can park both in one op.
const kMaxSetAside = kMaxWorn + kMaxCarrying;

/// Whitespace-collapsed, trimmed, and cut to [cap] characters.
String tidyPocketText(String s, int cap) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= cap ? t : t.substring(0, cap).trimRight();
}
