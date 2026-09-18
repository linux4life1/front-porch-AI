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

part 'pockets.items.dart';
part 'pockets.ops.dart';
part 'pockets.names.dart';
part 'pockets.apply.dart';

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

String _tidy(String s, int cap) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= cap ? t : t.substring(0, cap).trimRight();
}

/// How many things may sit set aside at once — one full outfit plus one full

/// A single character's pockets in a single chat.
/// A single character's pockets in a single chat.
class Pockets {
  final List<PocketItem> worn;
  final List<PocketItem> carrying;

  /// Things parked in the scene — see [SetAsideItem] for the expiry
  /// asymmetry. Serialised as an ADDITIVE `set_aside` key, omitted when
  /// empty, so an untouched record stays byte-identical to one written
  /// before this existed.
  final List<SetAsideItem> setAside;

  Pockets({
    List<PocketItem>? worn,
    List<PocketItem>? carrying,
    List<SetAsideItem>? setAside,
  }) : worn = worn ?? [],
       carrying = carrying ?? [],
       setAside = setAside ?? [];

  bool get isEmpty => worn.isEmpty && carrying.isEmpty && setAside.isEmpty;

  Pockets copy() => Pockets(
    worn: [...worn],
    carrying: [...carrying],
    setAside: [...setAside],
  );

  /// Set-aside entries still standing on story [day]: possessions always,
  /// clothing only until the story's next morning (people dress fresh —
  /// maintainer ruling, 2026-08-11). Pure view for prompt builders and the
  /// UI; [expireSetAside] is the matching cleanup for when the record is
  /// actually being written.
  List<SetAsideItem> setAsideOn(int day) => [
    for (final e in setAside)
      if (!e.clothing || e.day <= 0 || e.day >= day) e,
  ];

  /// Lazily applied whenever the record is touched — no timers. A `day` of
  /// 0 (no story clock) expires nothing: without a clock there is no
  /// "next morning".
  void expireSetAside(int day) =>
      setAside.removeWhere((e) => e.clothing && e.day > 0 && e.day < day);

  Map<String, dynamic> toJson() => {
    'worn': [for (final i in worn) i.toJson()],
    'carrying': [for (final i in carrying) i.toJson()],
    if (setAside.isNotEmpty)
      'set_aside': [for (final e in setAside) e.toJson()],
  };

  /// [toJson] as the story sees it on [day] — expired clothing filtered the
  /// same way [setAsideOn] does. The web facade reads this so the PWA can
  /// never show a stale morning-after outfit in the window before the next
  /// pass touches (and actually expires) the stored record.
  Map<String, dynamic> toJsonOn(int day) => {
    'worn': [for (final i in worn) i.toJson()],
    'carrying': [for (final i in carrying) i.toJson()],
    if (setAsideOn(day).isNotEmpty)
      'set_aside': [for (final e in setAsideOn(day)) e.toJson()],
  };

  /// Tolerates both the rich `{name, state}` shape and the plain-string shape a
  /// card author writes by hand in `frontPorchExtensions.inventory`.
  static Pockets fromJson(Object? raw) {
    if (raw is! Map) return Pockets();
    // Capped on the way IN, not only in the applier. A card is a stranger's
    // upload: without this a hostile or careless `inventory` with hundreds of
    // entries would load whole into session state and be re-serialised every
    // turn. The applier's own cap only ever ran on ops. (Grok, 2026-08-07.)
    List<PocketItem> list(Object? v, int max) => [
      for (final e in (v is List ? v : const []).take(max))
        ?PocketItem.fromJson(e),
    ];
    return Pockets(
      worn: list(raw['worn'], kMaxWorn),
      carrying: list(raw['carrying'], kMaxCarrying),
      setAside: [
        for (final e
            in (raw['set_aside'] is List ? raw['set_aside'] as List : const [])
                .take(kMaxSetAside))
          ?SetAsideItem.fromJson(e),
      ],
    );
  }

  /// Both lists as editable chip text — the seed side of the character editor.
  List<String> get wornDisplay => [for (final i in worn) i.display];
  List<String> get carryingDisplay => [for (final i in carrying) i.display];

  /// Chip text back to the card's `frontPorchExtensions.inventory` map.
  ///
  /// The ONE normalization for all three authoring surfaces (the edit page and
  /// both creators). They already disagree about this for the neighbouring
  /// lists — the edit page trims and drops blanks inline while both creators
  /// pass raw text and lean on the card parser later — and a fourth, slightly
  /// different rule here is how that kind of drift becomes permanent. Routing
  /// every save through [fromJson] gives wardrobe the same tidy, the same
  /// length caps and the same kMaxWorn/kMaxCarrying trim the runtime applies.
  ///
  /// Returns an EMPTY map when nothing survives, so the card keeps omitting the
  /// key entirely (`CharacterCard.toJson` emits it only when non-empty). That
  /// conditional emit is what keeps a card without a wardrobe byte-identical to
  /// one written before this existed.
  static Map<String, dynamic> cardJsonFrom({
    required List<String> worn,
    required List<String> carrying,
  }) {
    final wornItems = [
      for (final s in worn) PocketItem.parseDisplay(s),
    ].where((i) => !i.isEmpty && !isEmptyWardrobeRef(i.name));
    final p = Pockets.fromJson({
      'worn': [for (final i in wornItems) i.toJson()],
      'carrying': [
        for (final s in carrying) PocketItem.parseDisplay(s).toJson(),
      ],
    });
    return p.isEmpty ? const {} : p.toJson();
  }
}

/// Did two item names mean the same thing?
///
/// The model will not say "car keys" twice running — it says "the keys", then
/// "their car keys". Exact matching would leave a character carrying three sets
/// of keys, which is the failure that makes an inventory feature worse than no
/// inventory feature. Token overlap is the same rule the promise ledger uses to
/// decide whether a promise is the one already on file.
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
