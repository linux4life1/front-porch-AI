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

// The per-character, per-chat record: worn, carrying, and set aside.

import 'pockets_items.dart';
import 'pockets_limits.dart';
import 'pockets_names.dart';

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
