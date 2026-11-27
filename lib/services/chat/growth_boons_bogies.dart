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

import 'dart:convert';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character/trait_kit.dart';

import 'growth_physics.dart';

/// Boons & Bogies — the trait physics layered on Growth Rings
/// (docs/design/boons-and-bogies.md §3).
///
/// A **boon** is a `skill` ring tagged `bb.kind = boon`; it climbs Novice →
/// Skilled → Master on growth passes that actually used it. A **bogey** is a
/// `bogey` ring whose tier is evidence-only: it counts the times the roll
/// fired. Ordinary rings (trait / stance / habit / scar, and untagged skills
/// from before the feature) keep [GrowthPhysics] untouched.
///
/// Pure constants + derivation only. The applier owns content writes and the
/// roll owns the gauge columns (two writers, disjoint column sets —
/// docs/design/boons-and-bogies.md §12).
class BoonsBogies {
  BoonsBogies._(); // static namespace, never instantiated

  // ── Kinds + metadata keys ──────────────────────────────────────────────

  static const String kCategoryBogey = 'bogey';
  static const String kKindBoon = 'boon';
  static const String kKindBogey = 'bogey';

  static const String kBbKey = 'bb';
  static const String kKindKey = 'kind';
  static const String kSeededKey = 'seeded';
  static const String kLinkedBoonKey = 'linkedBoon';
  static const String kUndoKey = 'undo';

  // ── Ladders (§3.2) ─────────────────────────────────────────────────────

  static const int kBoonSkilledPasses = 3;
  static const int kBoonMasterPasses = 8;
  static const double kBoonSkilledStrength = 0.50;
  static const double kBoonMasterStrength = 0.90;

  static const int kBogeySkilledFires = 4;
  static const int kBogeyMasterFires = 12;
  static const double kBogeyBaseStrength = 0.30;
  static const double kBogeyStrengthPerFire = 0.05;
  static const double kBogeyMaxStrength = 0.90;

  /// A card carries at most this many boons and bogies combined, on a budget
  /// separate from the 12 story rings. Canonical value lives in the model
  /// layer (`TraitKitEntry.maxEntries`) — the card parses there.
  static const int kMaxKitEntries = TraitKitEntry.maxEntries;

  /// Active bogies per character, shared with card-seeded flaws. An add over
  /// the cap is dropped, never trimmed.
  static const int kMaxActiveBogies = 3;

  // ── Bogey rolls (§6) ───────────────────────────────────────────────────

  /// Base 3, growth jittered 2–6, cooldown jittered 1–3, chance ceiling 45%.
  /// The median gap is pinned to 7–9 replies by the simulation test.
  static const int kRollBase = 3;
  static const int kRollGrowthMin = 2;
  static const int kRollGrowthMax = 6;
  static const int kRollCooldownMin = 1;
  static const int kRollCooldownMax = 3;
  static const int kRollChanceCap = 45;
  static const int kRollPressureCap = 100;

  /// At most one milestone modal per this many user messages; overflow is
  /// queued, never dropped.
  static const int kMilestoneMinGapMessages = 8;

  /// Whether the next silent step would cross into Master (ruling 8: silent
  /// changes stop one step below it; the crossing is a milestone). [ring]
  /// is the ring before this step; [strengthAfter] what the step leaves it
  /// at. A declined ring never asks again until re-armed (§3.2).
  static bool crossesMaster(GrowthRingData ring, {double? strengthAfter}) {
    if (ring.masterDeclined || ring.retired) return false;
    if (isBogey(ring)) return ring.advanceCount >= kBogeyMasterFires - 1;
    if (!isBoon(ring)) return false;
    return ring.advanceCount >= kBoonMasterPasses - 1 &&
        (strengthAfter ?? ring.strength) >= kBoonMasterStrength;
  }

  /// A declined bogey is re-armed once coping drops it below this many
  /// fires; climbing back to Master then asks again (§3.2).
  static const int kBogeyMasterRearmBelow = 4;

  // ── Kind predicates ────────────────────────────────────────────────────

  /// A boon is a skill ring the applier tagged. Untagged skills (recorded
  /// before the feature, or with it off) stay ordinary rings.
  static bool isBoon(GrowthRingData ring) =>
      ring.category == 'skill' && kindOf(ring) == kKindBoon;

  static bool isBogey(GrowthRingData ring) => ring.category == kCategoryBogey;

  /// The `bb.kind` tag, or null for an ordinary ring.
  static String? kindOf(GrowthRingData ring) {
    final kind = bbOf(ring)[kKindKey];
    return kind is String ? kind : null;
  }

  /// True for either kind — the panel and the applier branch on this.
  static bool isBoonOrBogey(GrowthRingData ring) =>
      isBoon(ring) || isBogey(ring);

  /// Copied from a card kit (§4) rather than grown in-story. Kit rings sit
  /// on a budget separate from the 12 story rings: they never count
  /// against it and capVictim never retires them.
  static bool isKitSeeded(GrowthRingData ring) =>
      bbOf(ring)[kSeededKey] == true;

  // ── Card kit tiers (§4) ────────────────────────────────────────────────

  /// The strength a seeded ring starts at for a card tier. `developing`
  /// matches [GrowthPhysics.kDistillSeedStrength] on purpose. The
  /// `established` arms below are defensive: the seed cap (ruling 8,
  /// amended 2026-11-21) clamps `established` to `developing` in
  /// [TraitKitEntry]'s factory, so no kit entry reaches this function
  /// carrying it — a kit seeds at 0.60 at most, and 0.80 stays territory
  /// only a growth pass (or the milestone) earns.
  static double kitSeedStrength(String tier) => switch (tier) {
    'established' => 0.80,
    'developing' => 0.60,
    _ => 0.30,
  };

  /// The `advance_count` a seeded ring starts at for a card tier, chosen so
  /// the stored strength and the displayed tier agree the moment the ring
  /// exists: a bogey's strength is derived from its fire count (§3.2), so
  /// its count is the exact inverse of [kitSeedStrength] (0.30+0.05n →
  /// 0 / 6 / 10). A boon counts passes, so it starts at the ladder floor of
  /// the tier it maps to — and the Master floor obeys the half-built
  /// ceiling, so a seeded ring can never report a tier a growth pass would
  /// have to walk backwards to keep.
  static int kitSeedAdvance(String tier, {required bool bogey}) {
    if (bogey) {
      return switch (tier) {
        'established' => 10,
        'developing' => 6,
        _ => 0,
      };
    }
    final skilled = kBoonSkilledPasses;
    // A seed is never Master (ruling 8); 'established' clamps upstream.
    const master = kBoonMasterPasses - 1;
    return switch (tier) {
      'established' => master,
      'developing' => skilled,
      _ => 0,
    };
  }

  // ── Tiers (§3.2) ───────────────────────────────────────────────────────

  /// The displayed tier: Novice / Skilled / Master. Silent advancement stops
  /// one below Master, so Master shows only on a ring an accepted milestone
  /// crowned ([GrowthBbWriter.crownMaster]).
  static String tierOf(GrowthRingData ring) {
    if (isBogey(ring)) {
      if (ring.advanceCount >= kBogeyMasterFires) return 'master';
      if (ring.advanceCount >= kBogeySkilledFires) return 'skilled';
      return 'novice';
    }
    if (isBoon(ring)) {
      if (ring.advanceCount >= kBoonMasterPasses &&
          ring.strength >= kBoonMasterStrength) {
        return 'master';
      }
      if (ring.advanceCount >= kBoonSkilledPasses &&
          ring.strength >= kBoonSkilledStrength) {
        return 'skilled';
      }
      return 'novice';
    }
    return '';
  }

  /// Display label for the kind chip.
  static String kindLabel(GrowthRingData ring) =>
      isBogey(ring) ? 'Bogey' : 'Boon';

  // ── Advancement counters ───────────────────────────────────────────────

  /// A boon's count after one used growth pass. Silent steps stop one below
  /// Master (ruling 8); the crossing is a milestone ([crossesMaster]).
  static int nextBoonAdvance(int current) =>
      (current + 1).clamp(0, kBoonMasterPasses - 1);

  /// A bogey's count after one fire (or one "made worse" pass), held one
  /// below Master like [nextBoonAdvance].
  static int nextBogeyAdvance(int current) =>
      (current + 1).clamp(0, kBogeyMasterFires - 1);

  /// A bogey's count after one pass that showed the character coping
  /// (floor 0 — a flaw never goes negative). [steps] is 2 while the
  /// bogey's linked boon is Master (phase 7, `BoonLink.copeStepsFor`).
  static int fadedBogeyAdvance(int current, {int steps = 1}) =>
      (current - steps).clamp(0, 999);

  /// Strength is derived from the fire count so existing sorting and
  /// injection code keeps working (§3.2).
  static double bogeyStrength(int advanceCount) =>
      (kBogeyBaseStrength + kBogeyStrengthPerFire * advanceCount).clamp(
        kBogeyBaseStrength,
        kBogeyMaxStrength,
      );

  // ── Metadata pouch ─────────────────────────────────────────────────────

  /// The decoded `metadata.bb` map (empty on null/garbage).
  static Map<String, dynamic> bbOf(GrowthRingData ring) {
    final bb = _decodeMap(ring.metadata)[kBbKey];
    return bb is Map ? Map<String, dynamic>.from(bb) : <String, dynamic>{};
  }

  /// Metadata with `bb` replaced by [bb], other metadata keys preserved.
  static String metadataWithBb(GrowthRingData ring, Map<String, dynamic> bb) {
    final root = _decodeMap(ring.metadata);
    root[kBbKey] = bb;
    return jsonEncode(root);
  }

  /// Metadata that records the pre-change state under `bb.undo`, so the chip
  /// and the panel row can restore strength, count and text together.
  /// One step per ring, not a history stack.
  static String metadataWithUndo(GrowthRingData ring, {int at = 0}) {
    final root = _decodeMap(ring.metadata);
    final bb = Map<String, dynamic>.from(
      root[kBbKey] is Map ? root[kBbKey] as Map : const {},
    );
    bb[kUndoKey] = {
      'strength': ring.strength,
      'advance': ring.advanceCount,
      'text': ring.content,
      'at': at,
    };
    root[kBbKey] = bb;
    return jsonEncode(root);
  }

  /// The pending undo snapshot, or null when there is nothing to undo.
  static BbUndo? undoOf(GrowthRingData ring) {
    final raw = bbOf(ring)[kUndoKey];
    if (raw is! Map) return null;
    final strength = raw['strength'];
    final advance = raw['advance'];
    final text = raw['text'];
    if (strength is! num || advance is! num || text is! String) return null;
    return BbUndo(
      strength: strength.toDouble(),
      advance: advance.toInt(),
      text: text,
      at: raw['at'] is num ? (raw['at'] as num).toInt() : 0,
    );
  }

  /// Metadata with the undo snapshot cleared (after it has been applied).
  static String metadataWithoutUndo(GrowthRingData ring) {
    final root = _decodeMap(ring.metadata);
    final bb = Map<String, dynamic>.from(
      root[kBbKey] is Map ? root[kBbKey] as Map : const {},
    );
    bb.remove(kUndoKey);
    root[kBbKey] = bb;
    return jsonEncode(root);
  }

  /// Metadata tagging a new ring as a boon (optionally seeded from a card).
  static String boonMetadata({bool seeded = false}) => jsonEncode({
    kBbKey: {kKindKey: kKindBoon, if (seeded) kSeededKey: true},
  });

  /// Metadata tagging a new ring as a bogey (optionally seeded, pinned and
  /// linked to a boon).
  static String bogeyMetadata({bool seeded = false, String? linkedBoon}) =>
      jsonEncode({
        kBbKey: {
          kKindKey: kKindBogey,
          if (seeded) kSeededKey: true,
          kLinkedBoonKey: ?linkedBoon,
        },
      });

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

/// A stored pre-change snapshot for one boon/bogey ring.
class BbUndo {
  const BbUndo({
    required this.strength,
    required this.advance,
    required this.text,
    this.at = 0,
  });

  final double strength;
  final int advance;
  final String text;

  /// The message position the change came from (display only).
  final int at;
}
