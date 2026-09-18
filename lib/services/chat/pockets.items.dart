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

// The things themselves: a worn or carried item, a set-aside one, and the
// three lists a hand edit can target.

part of 'pockets.dart';

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

/// Which of the record's three lists a hand edit targets.
enum PocketSection { worn, carrying, setAside }
