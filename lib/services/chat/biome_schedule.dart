// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure biome changeover schedule for a chat (Living Worlds phase 1).
// Span snapshots are full biome JSON; history before a switch is immutable
// because weather RNG is keyed by day index, not a running stream.

import 'package:front_porch_ai/services/chat/weather_biomes.dart';

/// One climate changeover: effective from story day [effectiveFromDay] onward
/// until the next span (or forever).
class BiomeSpanEntry {
  final int effectiveFromDay;
  final Biome biome;

  const BiomeSpanEntry({
    required this.effectiveFromDay,
    required this.biome,
  });
}

/// Precomputed-friendly view of `chat_biome_spans` + world default.
///
/// [biomeAt] is O(spans) with a short list (typically ≤ a handful of
/// mid-chat switches). Callers hydrate once per session load / climate
/// change — never per day of the weather walk.
class BiomeSchedule {
  /// Sorted ascending by [BiomeSpanEntry.effectiveFromDay].
  final List<BiomeSpanEntry> spans;

  /// Climate when no span covers the day (attached world default, else temperate).
  final Biome worldDefault;

  const BiomeSchedule({
    this.spans = const [],
    this.worldDefault = Biome.temperate,
  });

  /// Biome active on story day [day] (1-based dayCount).
  Biome biomeAt(int day) {
    final d = day < 1 ? 1 : day;
    BiomeSpanEntry? active;
    for (final s in spans) {
      if (s.effectiveFromDay <= d) {
        active = s;
      } else {
        break;
      }
    }
    return active?.biome ?? worldDefault;
  }

  /// True when [day] is the first day of a span (foreshadow from the prior
  /// biome may lie for exactly this day — suppress the line).
  bool isSpanStart(int day) {
    final d = day < 1 ? 1 : day;
    for (final s in spans) {
      if (s.effectiveFromDay == d) return true;
      if (s.effectiveFromDay > d) return false;
    }
    return false;
  }

  /// Build from DB rows (already ordered by effective_from_day ASC).
  factory BiomeSchedule.fromJsonSpans({
    required List<({int effectiveFromDay, String biomeJson})> rows,
    Biome? worldDefault,
  }) {
    final entries = <BiomeSpanEntry>[];
    for (final r in rows) {
      final b = Biome.tryParse(r.biomeJson);
      if (b == null) continue;
      entries.add(
        BiomeSpanEntry(effectiveFromDay: r.effectiveFromDay, biome: b),
      );
    }
    return BiomeSchedule(
      spans: entries,
      worldDefault: worldDefault ?? Biome.temperate,
    );
  }
}
