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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character/trait_kit.dart';
import 'package:front_porch_ai/models/character_card.dart';

import 'growth_boons_bogies.dart';

/// Boons & Bogies kit seeding — the card's `traitKit` copied into this
/// chat's rings (docs/design/boons-and-bogies.md §4, ruling 13, §9).
///
/// Seeding is a COPY, not a link: each entry becomes a ring at its tier's
/// strength and the chat's copy grows on from there. A chat that has never
/// grown takes the kit silently at its first Growth touch; a chat with
/// rings already earned is OFFERED the kit naming the whole cast, and a
/// decline writes nothing but the settle itself.
///
/// Pure decisions + ring plans here; the desk and the panel own the when,
/// the button, and the DB write (through GrowthStore.addRing, where
/// receipts, macro resolution and the separate kit budget live).
class GrowthKitSeed {
  GrowthKitSeed._(); // static namespace, never instantiated

  /// `growth_state.kit_seed_state` (v69). Declined is its own state so
  /// "decline changes nothing" never re-nags, and the panel's re-run can
  /// tell an untouched chat from one the author already said no to.
  static const int kStateUnsettled = 0;
  static const int kStateSettled = 1;
  static const int kStateDeclined = 2;

  static bool hasKit(CharacterCard card) =>
      card.frontPorchExtensions?.traitKit.isNotEmpty ?? false;

  /// One owner's kit, or empty. Never throws on a card from anywhere.
  static List<TraitKitEntry> kitOf(CharacterCard card) =>
      card.frontPorchExtensions?.traitKit ?? const [];

  /// What the first Growth touch does with the cast's kits. The unit is
  /// the CHAT: a chat with no rings yet takes its kit silently (it has no
  /// history to preserve); a chat that already has rings is offered the
  /// kit instead, because those rings are the user's story (§4).
  static KitAction decide({
    required int state,
    required bool castHasKit,
    required bool sessionHasRings,
  }) {
    if (state != kStateUnsettled || !castHasKit) return KitAction.none;
    return sessionHasRings ? KitAction.offer : KitAction.autoSeed;
  }

  /// Rings to write for one owner. An owner who already has ANY kit-seeded
  /// ring is settled and skipped — the kit seeds once per chat, and the
  /// user deleting those rings is their story, not a bug to undo. Bogies
  /// past the shared 3-bogey cap are dropped, never trimmed (§5).
  static List<KitSeedRing> planOwner({
    required List<TraitKitEntry> kit,
    required List<GrowthRingData> activeRings,
  }) {
    if (kit.isEmpty || activeRings.any(BoonsBogies.isKitSeeded)) {
      return const [];
    }
    var bogeys = activeRings.where(BoonsBogies.isBogey).length;
    final plan = <KitSeedRing>[];
    for (final entry in kit) {
      final bogey = entry.isBogey;
      if (bogey && bogeys >= BoonsBogies.kMaxActiveBogies) continue;
      if (bogey) bogeys++;
      plan.add(
        KitSeedRing(
          characterText: entry.text,
          category: bogey ? BoonsBogies.kCategoryBogey : 'skill',
          strength: BoonsBogies.kitSeedStrength(entry.tier),
          advanceCount: BoonsBogies.kitSeedAdvance(entry.tier, bogey: bogey),
          pinned: entry.pinned,
          metadata: bogey
              ? BoonsBogies.bogeyMetadata(
                  seeded: true,
                  linkedBoon: entry.linkedTo,
                )
              : BoonsBogies.boonMetadata(seeded: true),
        ),
      );
    }
    return plan;
  }
}

/// What a first Growth touch does with the cast's kits.
enum KitAction { none, autoSeed, offer }

/// What a retroactive kit offer shows the user (ruling 13): which cast
/// members carry a kit and how many entries it holds in total.
class KitOffer {
  const KitOffer({required this.names, required this.entryCount});

  /// Display names of the cast members whose cards carry a kit.
  final List<String> names;
  final int entryCount;
}

/// One ring to insert for a kit entry, in the shape GrowthStore.addRing
/// takes. The desk feeds `sessionId`/`characterId` and resolves macros.
class KitSeedRing {
  const KitSeedRing({
    required this.characterText,
    required this.category,
    required this.strength,
    required this.advanceCount,
    required this.pinned,
    required this.metadata,
  });

  final String characterText;
  final String category;
  final double strength;
  final int advanceCount;
  final bool pinned;
  final String metadata;
}
