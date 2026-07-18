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

/// Growth Rings — deterministic ring physics
/// (docs/design/growth-rings.md §4.4). Pure constants + functions, no LLM
/// judgment and no I/O: strength tiers, reinforcement, per-pass fade, and
/// cap-trim victim selection. "LLM proposes, code disposes."
///
/// Tunables are code constants until proven to need settings (same policy as
/// JournalPhysics). GrowthStore applies fade/trim, GrowthService the pass
/// cadence, and the injection layering the tier rendering — all through this
/// one class, so 1:1 and group share the exact same numbers.
class GrowthPhysics {
  GrowthPhysics._(); // static namespace, never instantiated

  /// Strength a brand-new ring starts at (emerging).
  static const double kNewRingStrength = 0.30;

  /// Strength a distilled legacy-blob ring starts at (developing — it
  /// represents growth that already accumulated under the old system).
  static const double kDistillSeedStrength = 0.60;

  /// Strength gained when the pass reinforces a ring.
  static const double kReinforceStep = 0.20;

  /// Strength lost per growth pass by a non-established, unpinned ring that
  /// was NOT reinforced in that pass. An abandoned emerging ring dies in ~6
  /// passes (~30 turns at the default cadence).
  static const double kFadePerPass = 0.05;

  /// Tier thresholds. At or above [kEstablishedThreshold] a ring is permanent:
  /// it never fades and is never auto-retired.
  static const double kDevelopingThreshold = 0.35;
  static const double kEstablishedThreshold = 0.8;

  /// The applier accepts at most this many `add` ops per owner per pass —
  /// a fast cadence must produce reinforcement, not ring floods.
  static const int kMaxNewRingsPerPass = 2;

  /// Cap on active (non-retired) rings per owner. Inserting past the cap
  /// retires the weakest unpinned, non-established ring (a demotion to Past
  /// growth, not a deletion).
  static const int kMaxActiveRings = 12;

  /// How many rings the [Character Growth] injection block renders.
  static const int kInjectedRings = 8;

  /// Of [kInjectedRings], up to this many slots are reserved for the
  /// strongest still-in-progress (non-established) rings. Established rings
  /// never fade and strength ties rank the older ring first, so without a
  /// reserve a cast of 8+ permanent rings would crowd new growth out of the
  /// prompt forever — the character would keep growing on record while
  /// visibly freezing in the story.
  static const int kReservedFreshSlots = 2;

  /// Max stored length of a ring sentence (model-written rings; the archive
  /// entry written by code is exempt).
  static const int kRingMaxChars = 200;

  /// Category for the code-written legacy archive entry ("Pre-rings growth
  /// summary"). Never emitted by the model (unknown categories normalize to
  /// trait) and rendered specially by the timeline.
  static const String kArchiveCategory = 'archive';

  static bool isEstablished(GrowthRingData ring) =>
      ring.strength >= kEstablishedThreshold;

  /// Tier name for UI + injection prefixes: emerging / developing /
  /// established.
  static String tierOf(GrowthRingData ring) {
    if (ring.strength >= kEstablishedThreshold) return 'established';
    if (ring.strength >= kDevelopingThreshold) return 'developing';
    return 'emerging';
  }

  static double reinforced(double strength) =>
      (strength + kReinforceStep).clamp(0.0, 1.0);

  /// One ring's strength after one growth pass without reinforcement.
  /// Established and pinned rings never fade.
  static double fadedStrength(GrowthRingData ring) {
    if (ring.pinned || isEstablished(ring)) return ring.strength;
    return (ring.strength - kFadePerPass).clamp(0.0, 1.0);
  }

  /// The ring an over-cap insert should retire: the weakest unpinned,
  /// non-established active ring (oldest wins the tie via caller ordering).
  /// Null when every active ring is protected — the cap then yields (a cast
  /// of only permanent rings is already a settled character).
  static GrowthRingData? capVictim(List<GrowthRingData> activeRings) {
    GrowthRingData? weakest;
    for (final ring in activeRings) {
      if (ring.pinned || isEstablished(ring)) continue;
      if (weakest == null || ring.strength < weakest.strength) weakest = ring;
    }
    return weakest;
  }

  /// The rings the injection block renders: the top [kInjectedRings] of
  /// [activeRings] (already strongest-first), except that up to
  /// [kReservedFreshSlots] are held for the strongest non-established rings
  /// so in-progress growth always keeps a prompt voice. Relative strength
  /// order is preserved; when 8 or fewer rings are active — or the fresh
  /// rings already rank inside the top 8 — this matches a plain top-8 take.
  static List<GrowthRingData> injectionSelection(
    List<GrowthRingData> activeRings,
  ) {
    if (activeRings.length <= kInjectedRings) return activeRings;
    final reserved = activeRings
        .where((r) => !isEstablished(r))
        .take(kReservedFreshSlots)
        .toList();
    final chosen = {
      ...reserved,
      ...activeRings
          .where((r) => !reserved.contains(r))
          .take(kInjectedRings - reserved.length),
    };
    return activeRings.where(chosen.contains).toList();
  }

  /// Deterministic injection prefix by tier — settled facts read plainly,
  /// younger rings are hedged, with no LLM judgment involved. [charName] is
  /// the ring owner's name: rings open with it often ("Mira has stopped…"),
  /// and a name must never be case-folded into the sentence frame.
  static String injectionLine(GrowthRingData ring, {String? charName}) {
    switch (tierOf(ring)) {
      case 'established':
        return ring.content;
      case 'developing':
        return 'Increasingly, ${_foldFirst(ring.content, charName)}';
      default:
        return 'Lately, ${_foldFirst(ring.content, charName)}';
    }
  }

  static String _foldFirst(String s, String? charName) {
    if (s.isEmpty) return s;
    // The owner's name (and ALL-CAPS openers) keep their capital — only a
    // plain leading capital is folded into the sentence frame.
    if (charName != null && charName.isNotEmpty && s.startsWith(charName)) {
      return s;
    }
    final first = s[0];
    if (first != first.toLowerCase() && s.length > 1 && s[1] == s[1].toLowerCase()) {
      return first.toLowerCase() + s.substring(1);
    }
    return s;
  }
}
