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

// The op grammar: what the eval is allowed to say happened, the report it
// parses into, and the event the applier emits for item-memory cards.

part of 'pockets.dart';

/// What the eval is allowed to say happened.
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
