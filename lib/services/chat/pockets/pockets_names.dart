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

/// Did two item names mean the same thing?
///
/// The model will not say "car keys" twice running — it says "the keys", then
/// "their car keys". Exact matching would leave a character carrying three sets
/// of keys, which is the failure that makes an inventory feature worse than no
/// inventory feature. Token overlap is the same rule the promise ledger uses to
/// decide whether a promise is the one already on file.
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

/// Content tokens of an item name — lowercased, punctuation-stripped, filler
/// words dropped, and short noise (< 3 chars) skipped. ONE tokenizer shared
/// by the applier's matching and the Journal's keyword re-warm floor, so
/// "what counts as mentioning the keys" can never drift between them.
Set<String> itemNameTokens(String s) =>
    _contentTokens(s).where((t) => t.length >= 3).toSet();
