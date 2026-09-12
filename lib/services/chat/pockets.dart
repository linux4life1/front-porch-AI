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

/// One thing, worn or carried.
///
/// [state] is deliberately FREE TEXT and deliberately optional — "half-eaten",
/// "rain-soaked, muddy hem", "notched, needs sharpening". The maintainer asked
/// for condition; what was explicitly NOT asked for, and is a stated non-goal,
/// is an RPG stat system: no durability bars, no damage math, no per-category
/// schemas. The model narrates a sword getting notched anyway, and a phrase is
/// exactly as expressive as a story needs. A number would be less.
class PocketItem {
  final String name;
  final String state;

  const PocketItem(this.name, {this.state = ''});

  /// Trimmed, whitespace-collapsed and length-capped. Whitespace collapsing is
  /// not cosmetic: these strings are written by a model and land inside a
  /// prompt, so a newline would let an item name open what looks like a new
  /// prompt section (the same hardening preference_phrases.dart applies).
  factory PocketItem.clean(String name, {String state = ''}) => PocketItem(
    _tidy(name, kMaxItemNameChars),
    state: _tidy(state, kMaxItemStateChars),
  );

  bool get isEmpty => name.isEmpty;

  /// "iron sword (notched)" — how the item reads in a prompt and in the UI.
  String get display => state.isEmpty ? name : '$name ($state)';

  PocketItem withState(String s) =>
      PocketItem(name, state: _tidy(s, kMaxItemStateChars));

  Map<String, dynamic> toJson() => {
    'name': name,
    if (state.isNotEmpty) 'state': state,
  };

  /// The inverse of [display]: `"iron sword (notched)"` -> name + state.
  ///
  /// This is what lets the character editor author condition through a plain
  /// text chip instead of growing a second field per item. The convention is
  /// already the one the user reads everywhere else — the sidebar row, the
  /// receipts under a reply, and the prompt itself all render [display] — so
  /// the editor teaches nothing new.
  ///
  /// **It round-trips exactly, which is the only losslessness that matters
  /// here.** An item whose NAME ends in brackets ("pepper spray (small)")
  /// re-splits as name "pepper spray" + state "small" rather than as one long
  /// name — but [display] rebuilds the identical string, and [display] is what
  /// is injected and shown. The split is invisible in every direction a user
  /// or a model can look.
  ///
  /// Only a trailing `(...)` counts, and only when both halves are non-empty:
  /// "(nothing)" and "keys ()" are names, not conditions.
  factory PocketItem.parseDisplay(String raw) {
    final s = raw.trim();
    if (s.endsWith(')')) {
      final open = s.lastIndexOf('(');
      if (open > 0) {
        final name = s.substring(0, open).trim();
        final state = s.substring(open + 1, s.length - 1).trim();
        if (name.isNotEmpty && state.isNotEmpty) {
          return PocketItem.clean(name, state: state);
        }
      }
    }
    return PocketItem.clean(s);
  }

  static PocketItem? fromJson(Object? raw) {
    if (raw is String) {
      final i = PocketItem.clean(raw);
      return i.isEmpty ? null : i;
    }
    if (raw is! Map) return null;
    final i = PocketItem.clean(
      (raw['name'] ?? '').toString(),
      state: (raw['state'] ?? '').toString(),
    );
    return i.isEmpty ? null : i;
  }

  @override
  bool operator ==(Object other) =>
      other is PocketItem && other.name == name && other.state == state;

  @override
  int get hashCode => Object.hash(name, state);

  @override
  String toString() => display;
}

String _tidy(String s, int cap) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= cap ? t : t.substring(0, cap).trimRight();
}

/// How many things may sit set aside at once — one full outfit plus one full
/// set of carried things, since a bulk undress can park both in one op.
const kMaxSetAside = kMaxWorn + kMaxCarrying;

/// One thing set aside — still theirs, still in the scene, just not on their
/// body or in their hands. The nightstand, the chair, the doorway table.
///
/// The [clothing] flag is the whole asymmetry of the feature (maintainer
/// design, 2026-08-11): clothes and possessions have OPPOSITE memory rules.
/// Yesterday's shirt must not come back tomorrow — people dress fresh — so
/// clothing entries expire at the next story morning. Yesterday's keys
/// absolutely must come back — nobody picks out a fresh wallet — so
/// possessions sit there until picked up, given away, dropped, or hand
/// edited. [day] is the story day the thing was parked (0 = no story clock
/// running, which means nothing ever expires: without a clock there is no
/// "next morning").
class SetAsideItem {
  final PocketItem item;
  final bool clothing;
  final int day;

  const SetAsideItem(this.item, {required this.clothing, this.day = 0});

  SetAsideItem withItem(PocketItem it) =>
      SetAsideItem(it, clothing: clothing, day: day);

  Map<String, dynamic> toJson() => {
    ...item.toJson(),
    'clothing': clothing,
    if (day > 0) 'day': day,
  };

  static SetAsideItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final i = PocketItem.fromJson(raw);
    if (i == null) return null;
    return SetAsideItem(
      i,
      clothing: raw['clothing'] == true,
      day: (raw['day'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Which of the record's three lists a hand edit targets.
enum PocketSection { worn, carrying, setAside }

/// What the eval is allowed to say happened.
enum PocketOpKind {
  wear,
  remove,
  pickup,
  drop,
  give,
  setdown,
  update,
  transform;

  static PocketOpKind? parse(String raw) {
    final s = raw.trim().toLowerCase();
    for (final v in PocketOpKind.values) {
      if (v.name == s) return v;
    }
    // A local model will reach for the obvious synonym; accepting a handful
    // costs nothing and is the same forgiving-floor posture the Journal's XML
    // transport takes.
    return const {
      'put_on': PocketOpKind.wear,
      'puton': PocketOpKind.wear,
      'equip': PocketOpKind.wear,
      'take_off': PocketOpKind.remove,
      'takeoff': PocketOpKind.remove,
      'unequip': PocketOpKind.remove,
      'take': PocketOpKind.pickup,
      'pick_up': PocketOpKind.pickup,
      'get': PocketOpKind.pickup,
      'discard': PocketOpKind.drop,
      'lose': PocketOpKind.drop,
      'hand': PocketOpKind.give,
      'set_down': PocketOpKind.setdown,
      'put_down': PocketOpKind.setdown,
      'putdown': PocketOpKind.setdown,
      'set_aside': PocketOpKind.setdown,
      'setaside': PocketOpKind.setdown,
      'place': PocketOpKind.setdown,
      'stow': PocketOpKind.setdown,
      'become': PocketOpKind.transform,
      'becomes': PocketOpKind.transform,
    }[s];
  }
}

/// One reported change. [to] names the recipient of a `give`; [state] carries
/// the new condition for `update`, or what the item BECAME for `transform`;
/// [where] is an optional short place phrase for `setdown`/`drop`/`give`
/// ("on the nightstand", "by the door") — never required, purely enrichment
/// for the item-memory journal cards.
class PocketOpReport {
  final PocketOpKind kind;
  final String item;
  final String to;
  final String state;
  final String where;

  const PocketOpReport({
    required this.kind,
    required this.item,
    this.to = '',
    this.state = '',
    this.where = '',
  });

  /// Forgiving parse of one eval-reported op. Returns null for anything
  /// unusable — a missing verb, an empty item — rather than throwing, because
  /// one malformed entry in a list of five must cost that entry and not the
  /// turn.
  static PocketOpReport? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = PocketOpKind.parse((raw['op'] ?? '').toString());
    if (kind == null) return null;
    final item = _tidy((raw['item'] ?? '').toString(), kMaxItemNameChars);
    if (item.isEmpty) return null;
    return PocketOpReport(
      kind: kind,
      item: item,
      to: _tidy((raw['to'] ?? '').toString(), kMaxItemNameChars),
      state: _tidy((raw['state'] ?? '').toString(), kMaxItemStateChars),
      where: _tidy((raw['where'] ?? '').toString(), kMaxItemStateChars),
    );
  }
}

/// One change that ACTUALLY applied, with the item's CANONICAL name (the
/// record's own spelling, not whatever the model typed). This is the feed
/// for the item-memory journal cards (maintainer design, 2026-08-11):
/// deterministic, downstream of ops the record already trusted, zero extra
/// model calls. The applier emits these; it neither knows nor cares what a
/// journal is.
class PocketEvent {
  final PocketOpKind kind;
  final String item;
  final String to;
  final String where;

  /// The item was clothing (came from / went onto the worn list).
  final bool clothing;

  /// Part of a generic whole-outfit remove ("they undress") rather than a
  /// named single-item op — lets the card writer keep routine undressing
  /// out of the diary.
  final bool bulk;

  const PocketEvent({
    required this.kind,
    required this.item,
    this.to = '',
    this.where = '',
    this.clothing = false,
    this.bulk = false,
  });
}

/// Content tokens of an item name — lowercased, punctuation-stripped, filler
/// words dropped, and short noise (< 3 chars) skipped. ONE tokenizer shared
/// by the applier's matching and the Journal's keyword re-warm floor, so
/// "what counts as mentioning the keys" can never drift between them.
Set<String> itemNameTokens(String s) =>
    _contentTokens(s).where((t) => t.length >= 3).toSet();

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
/// cards. No-op ops emit nothing; passing null costs nothing.
List<String> applyPocketOps(
  Pockets p,
  Iterable<PocketOpReport> ops, {
  void Function(String to, PocketItem item)? onTransfer,
  int day = 0,
  List<PocketEvent>? events,
}) {
  final receipts = <String>[];

  // Housekeeping before ops, so everything below acts on the record as the
  // story sees it: yesterday's set-aside clothes are already gone.
  p.expireSetAside(day);

  int find(List<PocketItem> list, String name) =>
      list.indexWhere((i) => sameItem(i.name, name));
  int findAside(String name) =>
      p.setAside.indexWhere((e) => sameItem(e.item.name, name));

  void capTo(List<PocketItem> list, int max) {
    // Trim the OLDEST, not the newest: the thing just picked up is the thing
    // the scene is about.
    while (list.length > max) {
      list.removeAt(0);
    }
  }

  void park(PocketItem item, {required bool clothing}) {
    p.setAside.add(SetAsideItem(item, clothing: clothing, day: day));
    while (p.setAside.length > kMaxSetAside) {
      // Evict CLOTHING first — it expires at the next story morning anyway,
      // while a possession is under the "never vanishes" promise. Trimming
      // strictly oldest-first let tonight's bulk undress silently evict the
      // mysterious letter parked three days ago (hostile review 2026-08-11).
      final firstClothing = p.setAside.indexWhere((e) => e.clothing);
      p.setAside.removeAt(firstClothing != -1 ? firstClothing : 0);
    }
  }

  void undressAll() {
    for (final it in p.worn) {
      park(it, clothing: true);
      receipts.add('took off: ${it.name}');
      events?.add(
        PocketEvent(
          kind: PocketOpKind.remove,
          item: it.name,
          clothing: true,
          bulk: true,
        ),
      );
    }
    p.worn.clear();
    for (final it in p.carrying) {
      park(it, clothing: false);
      receipts.add('set aside: ${it.name}');
      events?.add(
        PocketEvent(kind: PocketOpKind.remove, item: it.name, bulk: true),
      );
    }
    p.carrying.clear();
  }

  for (final op in ops) {
    switch (op.kind) {
      case PocketOpKind.wear:
        // Bulk-out, mirroring remove's bulk-in: "they get dressed" arrives
        // as ONE wear op naming "clothes", and the rubric's own "remove of
        // 'clothes' means all of it" teaches models the symmetric report.
        // Without this branch the applier minted a literal garment named
        // "clothes" into the worn list — garbage the record then displayed
        // AND injected (hostile review, 2026-08-11). Re-dress from the
        // set-aside pile's clothing; with nothing set aside there is
        // nothing to put on, and inventing an item is exactly the failure
        // the no-op rule exists to prevent.
        if (isEmptyWardrobeRef(op.item)) {
          // Nude is remove, not a garment named "nothing".
          if (p.worn.isEmpty && p.carrying.isEmpty) break;
          undressAll();
          break;
        }
        if (isGenericClothingRef(op.item)) {
          final backOn = [
            for (final e in p.setAside)
              if (e.clothing) e,
          ];
          for (final e in backOn) {
            p.setAside.remove(e);
            p.worn.add(e.item);
            receipts.add('put on: ${e.item.name}');
            events?.add(
              PocketEvent(kind: op.kind, item: e.item.name, clothing: true),
            );
          }
          capTo(p.worn, kMaxWorn);
          break;
        }
        final alreadyWorn = find(p.worn, op.item);
        if (alreadyWorn != -1) {
          // Already on — but the model may be reporting a CHANGE to it ("their
          // dress is now torn"), and dropping that on the floor was silent
          // data loss (Grok, 2026-08-07). Nothing to say without a state.
          if (op.state.isNotEmpty && p.worn[alreadyWorn].state != op.state) {
            p.worn[alreadyWorn] = p.worn[alreadyWorn].withState(op.state);
            receipts.add('${op.item}: ${op.state}');
          }
          break;
        }
        final c = find(p.carrying, op.item);
        final s = c == -1 ? findAside(op.item) : -1;
        // Carrying first, then the set-aside pile (the shower case: their
        // clothes are right there), then a genuinely new garment.
        final item = c != -1
            ? p.carrying.removeAt(c)
            : s != -1
            ? p.setAside.removeAt(s).item
            : PocketItem.clean(op.item, state: op.state);
        p.worn.add(op.state.isEmpty ? item : item.withState(op.state));
        capTo(p.worn, kMaxWorn);
        receipts.add('put on: ${op.item}');
        events?.add(
          PocketEvent(kind: op.kind, item: item.name, clothing: true),
        );

      case PocketOpKind.remove:
        // Clothing taken off goes to SET ASIDE, not to carrying and not
        // into thin air. The 2026-08-11 morning ruling ("remove deletes")
        // was superseded the same day by the approved set-aside design: a
        // mid-scene shower needs the outfit recoverable ("their clothes are
        // right there"), while the overnight case still honours the ruling
        // — clothing entries expire at the next story morning, so tomorrow
        // they dress fresh via wear ops and yesterday's shirt is gone.
        if (isGenericClothingRef(op.item)) {
          // "They undress" — the whole outfit comes off, and what they were
          // carrying lands beside it (pockets are in the clothes; nobody
          // showers holding their phone). Possessions park as
          // non-expiring: the keys are still on the nightstand tomorrow.
          undressAll();
          break;
        }
        final w = find(p.worn, op.item);
        if (w == -1) break;
        final removed = p.worn.removeAt(w);
        park(removed, clothing: true);
        receipts.add('took off: ${op.item}');
        events?.add(
          PocketEvent(kind: op.kind, item: removed.name, clothing: true),
        );

      case PocketOpKind.setdown:
        // Put down nearby, still theirs — the mid-scene sibling of the bulk
        // undress ("they set their bag by the door"). Before this op existed
        // the model's only honest choices were `drop` (which DELETES the
        // bag) or silence (they "carry" it all evening) — the same
        // data-loss shape as the undress bug, in miniature.
        if (isGenericThingsRef(op.item)) {
          // "They set their things down" — everything in hand goes beside
          // them. Carried only: undressing is remove's business.
          for (final it in p.carrying) {
            park(it, clothing: false);
            receipts.add('set aside: ${it.name}');
            events?.add(
              PocketEvent(kind: op.kind, item: it.name, where: op.where),
            );
          }
          p.carrying.clear();
          break;
        }
        final sc = find(p.carrying, op.item);
        if (sc != -1) {
          final down = p.carrying.removeAt(sc);
          park(down, clothing: false);
          receipts.add('set aside: ${op.item}');
          events?.add(
            PocketEvent(kind: op.kind, item: down.name, where: op.where),
          );
          break;
        }
        // A worn thing set down (hat on the table) is clothing taken off.
        final sw = find(p.worn, op.item);
        if (sw == -1) break;
        final downWorn = p.worn.removeAt(sw);
        park(downWorn, clothing: true);
        receipts.add('set aside: ${op.item}');
        events?.add(
          PocketEvent(
            kind: op.kind,
            item: downWorn.name,
            where: op.where,
            clothing: true,
          ),
        );

      case PocketOpKind.pickup:
        if (find(p.carrying, op.item) != -1 || find(p.worn, op.item) != -1) {
          break;
        }
        // The set-aside pile first — taking back their own keys is not
        // acquiring new ones, and the condition rides along. A NEW state on
        // the op updates it, the same rule wear's retrieval follows (the
        // two paths disagreed for no reason — hostile review 2026-08-11).
        final sa = findAside(op.item);
        final got = sa != -1
            ? p.setAside.removeAt(sa).item
            : PocketItem.clean(op.item, state: op.state);
        p.carrying.add(op.state.isEmpty ? got : got.withState(op.state));
        capTo(p.carrying, kMaxCarrying);
        receipts.add('picked up: ${op.item}');
        events?.add(PocketEvent(kind: PocketOpKind.pickup, item: got.name));

      // `give` used to be half a transfer: the item left the giver and reached
      // nobody, so Alice handing Bob the keys left Bob's record untouched. The
      // reason was real — resolving a free-text name the model chose to a
      // member record, and putting the keys in the WRONG character's pocket, is
      // a worse failure than not moving them, because it is invisible AND
      // wrong. The fix is not to guess better; it is to only accept a name the
      // caller can match to a real member, and otherwise keep the old floor.
      case PocketOpKind.drop:
      case PocketOpKind.give:
        // All three locations: they can hand over or throw away something
        // they set down five minutes ago ("gives Bob the keys from the
        // nightstand") just as naturally as something in their hands.
        final c = find(p.carrying, op.item);
        final w = c == -1 ? find(p.worn, op.item) : -1;
        final sa = c == -1 && w == -1 ? findAside(op.item) : -1;
        if (c == -1 && w == -1 && sa == -1) break;
        // Take the item as it stands, so its condition travels with it.
        final taken = c != -1
            ? p.carrying.removeAt(c)
            : w != -1
            ? p.worn.removeAt(w)
            : p.setAside.removeAt(sa).item;
        if (op.kind == PocketOpKind.give && op.to.isNotEmpty) {
          onTransfer?.call(op.to, taken);
        }
        receipts.add(
          op.kind == PocketOpKind.give && op.to.isNotEmpty
              ? 'gave ${op.item} to ${op.to}'
              : 'dropped: ${op.item}',
        );
        events?.add(
          PocketEvent(
            kind: op.kind,
            item: taken.name,
            to: op.to,
            where: op.where,
            clothing: w != -1,
          ),
        );

      case PocketOpKind.update:
        if (op.state.isEmpty) break;
        bool touch(List<PocketItem> list) {
          final i = find(list, op.item);
          if (i == -1) return false;
          if (list[i].state != op.state) {
            list[i] = list[i].withState(op.state);
            receipts.add('${op.item}: ${op.state}');
          }
          return true;
        }

        if (touch(p.worn) || touch(p.carrying)) break;
        final u = findAside(op.item);
        if (u == -1 || p.setAside[u].item.state == op.state) break;
        p.setAside[u] = p.setAside[u].withItem(
          p.setAside[u].item.withState(op.state),
        );
        receipts.add('${op.item}: ${op.state}');

      case PocketOpKind.transform:
        // A candy bar becomes a wrapper. The item is REPLACED, not annotated,
        // because what they are holding is genuinely a different thing now.
        if (op.state.isEmpty) break;
        bool morph(List<PocketItem> list) {
          final i = find(list, op.item);
          if (i == -1) return false;
          list[i] = PocketItem.clean(op.state);
          receipts.add('${op.item} → ${op.state}');
          return true;
        }

        if (morph(p.worn) || morph(p.carrying)) break;
        final t = findAside(op.item);
        if (t == -1) break;
        p.setAside[t] = p.setAside[t].withItem(PocketItem.clean(op.state));
        receipts.add('${op.item} → ${op.state}');
    }
  }
  return receipts;
}
