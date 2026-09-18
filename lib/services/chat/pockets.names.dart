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

// Matching an item the model named against one the record already holds:
// filler words, generic references ("my clothes", "nothing"), and same-item.

part of 'pockets.dart';

const _filler = {'a', 'an', 'the', 'her', 'his', 'their', 'my', 'your', 'of'};

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '');

Set<String> _contentTokens(String s) => _norm(
  s,
).split(' ').where((t) => t.isNotEmpty && !_filler.contains(t)).toSet();

/// Did the model mean the whole outfit rather than one garment?
///
/// "They undress for bed" arrives as ONE remove op naming "clothes" or
/// "everything" — never an enumeration of the worn list. Before this existed
/// that op matched nothing and silently no-opped, which is exactly the
/// maintainer's report: they are in the shower and the sidebar still shows
/// them fully dressed (2026-08-11).
///
/// A phrase counts as generic only when EVERY content token is a whole-outfit
/// word: "their clothes" and "all of their clothes" qualify; "wet dress" has a
/// garment token and falls through to ordinary item matching. Real garment
/// names ("dress", "pajamas") are deliberately absent from this set.
bool isGenericClothingRef(String raw) {
  const generic = {
    'clothes',
    'clothing',
    'outfit',
    'garments',
    'everything',
    'all',
  };
  final toks = _contentTokens(raw);
  return toks.isNotEmpty && toks.every(generic.contains);
}

/// Did the model mean "they are wearing nothing" rather than a garment?
///
/// `wear "nothing"` is how local models report undressing. Without this the
/// applier mints a literal item named "nothing" — the sidebar chip and the
/// `put on: nothing` receipt (2026-08-20). Same shape as [isGenericClothingRef]
/// minting `"clothes"`. "bare feet" has a real token and falls through.
bool isEmptyWardrobeRef(String raw) {
  const empty = {
    'nothing',
    'none',
    'nude',
    'naked',
    'unclothed',
    'undressed',
    'bare',
    'empty',
  };
  final toks = _contentTokens(raw);
  return toks.isNotEmpty && toks.every(empty.contains);
}

/// Did the model mean everything they are CARRYING? The setdown sibling of
/// [isGenericClothingRef]: "they set their things down" arrives as one op
/// naming "their things"/"their belongings", which matched no single item and
/// silently no-opped (hostile review, 2026-08-11 — the mid-scene half of
/// the same bulk gap the undress fix closed).
bool isGenericThingsRef(String raw) {
  const generic = {'things', 'belongings', 'stuff', 'everything', 'all'};
  final toks = _contentTokens(raw);
  return toks.isNotEmpty && toks.every(generic.contains);
}

bool sameItem(String a, String b) {
  final an = _norm(a), bn = _norm(b);
  if (an.isEmpty || bn.isEmpty) return false;
  if (an == bn) return true;

  final at = _contentTokens(a), bt = _contentTokens(b);
  if (at.isEmpty || bt.isEmpty) return false;

  // CONTAINMENT ONLY — deliberately not a shared-token ratio.
  //
  // The first draft counted overlap and matched when shared tokens were at
  // least half the shorter name. That looked reasonable and was wrong on the
  // most ordinary case there is: "car keys" and "house keys" share "keys",
  // which is half of two, so a character could never hold both. Caught by the
  // applier tests before any of this was wired to anything.
  //
  // Containment covers what actually needs covering — "the car keys" and
  // "their car keys" reduce to the same token set, and "satchel" is contained by
  // "worn leather satchel" — while leaving genuinely different things apart.
  // A bare "keys" said while holding two kinds resolves to whichever is
  // listed first; ambiguous, but far better than inventing a third set.
  return at.containsAll(bt) || bt.containsAll(at);
}

/// THE applier. Every change to a character's pockets goes through here —
/// the eval, the sidebar's hand edits, and the card seed all end up in this one
/// function, so there is one place where "what happens when you wear something
/// you are already wearing" is decided.
///
/// Returns a human-readable receipt line per applied op ("picked up: car
/// keys"), in order, for the message chips. An op that changes nothing returns
/// nothing — a model reporting that they are still wearing the dress they were
/// already wearing should not produce a chip.
/// Apply [ops] to [p] in place and return the receipt lines for the chips.
///
/// [onTransfer] fires when a `give` names a recipient and the item was really
/// in the giver's possession — it hands over the ITEM AS IT WAS, condition and
/// all, so a rain-soaked coat arrives rain-soaked. It stays a callback rather
/// than a return value because this function owns exactly one character's
/// record; who the other side is, and whether that name resolves to anyone, is
/// the caller's business (see ChatService._runPocketsPass).
///
/// A `give` with no recipient, or with one nobody can resolve, still removes
/// the item from the giver. That is the floor and it is deliberate: the giver
/// no longer holding what they handed over is true regardless of whether the
/// app can work out who took it.
/// [day] is the current story day, used to stamp newly parked set-aside
/// entries and to expire yesterday's clothing before any op can match it.
/// The default 0 means "no story clock": nothing is stamped, nothing expires.
/// [events], when supplied, collects a [PocketEvent] per APPLIED change
/// (canonical item names) — the deterministic feed for item-memory journal
