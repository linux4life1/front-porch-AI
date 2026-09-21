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

/// Item-memory journal cards — the pure mapper from applied pocket events to
/// diary lines (maintainer design, 2026-08-11).
///
/// "They put their keys on the hallway table" is not STATE — it is an event they
/// should REMEMBER, and remembering is the Journal's whole trade: heat while
/// fresh, cooling as the scene moves on, keyword/semantic resurfacing when
/// the conversation drifts back near it. This mapper is the feed's editorial
/// desk: it decides which pocket events are diary-worthy and writes the line
/// in the diary's own first-person voice.
///
/// DETERMINISTIC BY DESIGN — no LLM writes these. The events arrive from the
/// applier with canonical item names, downstream of ops the record already
/// trusted enough to render as chips, so the cards can never disagree with
/// the record about what happened. (The Journal's own LLM pass would never
/// write them itself: it is tuned for emotional salience, and "keys on the
/// table" is emotionally flat — which is exactly why it needs this desk.)
///
/// THE SALIENCE FILTER, and why each rule points the way it does:
///   * setdown / give / drop → one card each. These are the events the
///     feature exists for — where things went, who has them now.
///   * a change of clothes (remove + wear in one turn) → ONE combined card.
///     Outfit history is worth remembering ("what did I wear to the fair");
///     eight individual wear lines are not.
///   * undressing alone (removes, no wears — bed, bath, shower) → SILENT.
///     Routine, daily, and already handled by set-aside + overnight expiry;
///     a diary that logs every bedtime is a grocery list.
///   * wear alone (dressing fresh in the morning) → SILENT, same reason.
///   * pickup / update / transform → no events reach here at all.
library;

import 'package:front_porch_ai/services/chat/pockets.dart';

/// One diary line to write: [content] in the card's first-person voice,
/// [item] the canonical name for the metadata pouch (keyword re-warm +
/// one-live-card-per-item dedup key).
typedef ItemCardDraft = ({String item, String content});

/// Map one turn's applied [events] to the cards worth keeping.
List<ItemCardDraft> itemCardsFrom(List<PocketEvent> events) {
  if (events.isEmpty) return const [];
  final drafts = <ItemCardDraft>[];

  String placed(String where) => where.isEmpty ? '' : ' — $where';

  for (final e in events) {
    switch (e.kind) {
      case PocketOpKind.setdown:
        drafts.add((
          item: e.item,
          content: 'I set my ${e.item} down${placed(e.where)}.',
        ));
      case PocketOpKind.give:
        drafts.add((
          item: e.item,
          content: e.to.isEmpty
              ? 'I handed my ${e.item} over.'
              : 'I gave my ${e.item} to ${e.to}.',
        ));
      case PocketOpKind.drop:
        drafts.add((
          item: e.item,
          content: 'I parted with my ${e.item}${placed(e.where)}.',
        ));
      case PocketOpKind.wear:
      case PocketOpKind.remove:
      case PocketOpKind.pickup:
      case PocketOpKind.update:
      case PocketOpKind.transform:
        break; // handled below (outfit change) or deliberately silent
    }
  }

  // A change of clothes: something came off AND something went on in the
  // same turn. One card, newest-worn first, the shed outfit in parentheses.
  // The em-dash/paren shapes keep the line grammatical whatever the names.
  final wears = [
    for (final e in events)
      if (e.kind == PocketOpKind.wear) e.item,
  ];
  final removes = [
    for (final e in events)
      if (e.kind == PocketOpKind.remove && e.clothing) e.item,
  ];
  if (wears.isNotEmpty && removes.isNotEmpty) {
    String short(List<String> names) =>
        names.length <= 3 ? names.join(', ') : '${names.take(3).join(', ')}, …';
    drafts.add((
      item: wears.first,
      content: 'I changed into ${short(wears)} (out of ${short(removes)}).',
    ));
  }

  return drafts;
}
