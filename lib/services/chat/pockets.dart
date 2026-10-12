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

/// Pockets & Wardrobe — what a character is wearing and carrying.
/// Design: docs/design/pockets-and-preferences.md Part 1.
///
/// No AI chat app keeps clothing and carried-item state straight, because
/// nothing STORES it: an outfit is a sentence of prose that scrolls out of
/// context by turn thirty, and then the character is barefoot in a scene they
/// put boots on for. This app already solves that shape of problem three times
/// over — Needs, the Journal, the story clock — the same way each time: keep a
/// real record, inject it every turn, apply deltas. This is the fourth.
///
/// Strictly session-scoped, exactly like Journal cards: a chat's pockets belong
/// to that chat and die with it. Nothing here crosses conversations.
///
/// This file is the PURE core — the item, the op grammar, and the ONE applier.
/// No I/O, no LLM, no Flutter. Everything that decides *what* happened lives in
/// the eval; everything that decides *how state changes* lives here, where it
/// can be tested without a model.
library;

export 'pockets/pockets.dart';

/// Which of [names] did the model mean by [to]?
///
/// Returns the matched name, or null when nothing matches confidently — and
/// null is a real answer, not a failure. The whole reason `give` shipped
/// without transfers was that guessing wrong puts an item in the WRONG
/// character's pocket, which is invisible and wrong rather than merely
/// incomplete. So this refuses anything it is not sure about, and the caller
/// falls back to the old behaviour: the item leaves the giver and goes nowhere.
///
/// Deliberately NOT fuzzy. Three passes, each of which can only produce one
/// answer:
///   1. exact, case-insensitive ("bob" -> "Bob")
///   2. first name, when it is unambiguous across the roster ("Bob" -> "Bob
///      Vance"); skipped entirely if two members share a first name
///   3. nothing else. Pronouns ("him"), roles ("the barkeep"), the user, and
///      anyone off-screen all resolve to null on purpose.
///
/// Substring matching is what this must never do: "Ann" would match "Joanne",
/// and a longest-common-prefix rule would hand "Sam"'s coat to "Samantha".
String? resolveRecipient(String to, List<String> names) {
  final t = to.trim().toLowerCase();
  if (t.isEmpty || names.isEmpty) return null;

  for (final n in names) {
    if (n.trim().toLowerCase() == t) return n;
  }

  // First names, only where they are unique. A roster with two Bobs gets no
  // first-name pass at all rather than an arbitrary winner.
  final firsts = <String, List<String>>{};
  for (final n in names) {
    final f = n.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (f.isNotEmpty) (firsts[f] ??= []).add(n);
  }
  final hit = firsts[t];
  if (hit != null && hit.length == 1) return hit.single;

  return null;
}
