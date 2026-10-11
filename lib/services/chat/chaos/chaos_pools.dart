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

import 'dart:math';

import 'chaos_event.dart';
import 'chaos_pool_adult.dart';
import 'chaos_pool_classic.dart';
import 'chaos_pool_expanded.dart';

/// Every Chance Time event, SFW first.
final List<ChaosEvent> kAllChaosEvents = [
  ...kChaosClassicEvents,
  ...kChaosExpandedEvents,
  ...kChaosAdultEvents,
];

final Map<String, ChaosEvent> _byText = {
  for (final e in kAllChaosEvents) e.text: e,
};

/// The event behind a raw (unresolved) wheel string, or null for text that is
/// not in the pools.
ChaosEvent? chaosEventFor(String text) => _byText[text];

/// Wheel slots given to adult events when the spicy pool is in play.
const int kAdultWheelSlots = 3;

/// Picks [size] distinct events for one wheel.
///
/// SFW slots are spread across categories (one per category before any
/// repeats) so a wheel is never eight bathroom jokes. When [includeAdult] is
/// set, [kAdultWheelSlots] of the slots are adult. Events in [recent] are
/// skipped while enough others remain. Pair events need [allowPair]; events
/// naming the user need [allowUser].
List<String> buildChaosWheel({
  required bool includeAdult,
  required bool allowPair,
  required bool allowUser,
  Iterable<String> recent = const [],
  int size = 8,
  Random? random,
}) {
  final rng = random ?? Random();
  final recentSet = recent.toSet();
  bool fits(ChaosEvent e) =>
      (allowPair || !e.needsPartner) && (allowUser || !e.involvesUser);

  List<ChaosEvent> fresh(Iterable<ChaosEvent> pool) {
    final all = pool.where(fits).toList()..shuffle(rng);
    final unseen = all.where((e) => !recentSet.contains(e.text)).toList();
    return unseen.length >= size ? unseen : all;
  }

  final adult = includeAdult
      ? fresh(kAllChaosEvents.where((e) => e.adult))
      : const <ChaosEvent>[];
  final picked = adult.take(kAdultWheelSlots).toList();

  final sfw = fresh(kAllChaosEvents.where((e) => !e.adult));
  final usedCategories = <ChaosCategory>{};
  for (final e in sfw) {
    if (picked.length >= size) break;
    if (usedCategories.add(e.category)) picked.add(e);
  }
  for (final e in sfw) {
    if (picked.length >= size) break;
    if (!picked.contains(e)) picked.add(e);
  }
  picked.shuffle(rng);
  return [for (final e in picked) e.text];
}
