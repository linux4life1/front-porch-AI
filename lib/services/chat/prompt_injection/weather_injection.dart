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

import 'package:front_porch_ai/services/chat/weather_engine.dart';
import 'package:front_porch_ai/services/chat/weather_segments.dart';

/// Weather fragment for the words-only state block
/// (docs/design/living-time-features.md §3, intra-day since v3). Renders the
/// CURRENT DAY-PART's weather (dressing cue + condition prose), a within-day
/// transition sentence when the sky changed since the previous segment, and
/// the day-level tomorrow foreshadow. Words only, never numbers
/// (prompt-state-injection.md contract — temperatures are UI-only). Returns
/// '' when weather is off — the composer drops empty fragments, so the block
/// shape is unchanged for users with the feature disabled. State lives in
/// WeatherEngine/WeatherSegments (pure) via the ChatService gate; this leaf
/// only renders words.
class WeatherInjection {
  final SegmentWeather? Function() getWeather;
  final SegmentWeather? Function() getPreviousSegment;
  final DailyWeather? Function() getUpcoming;

  /// When true, omit tomorrow's foreshadow (Living Worlds: first day of a
  /// biome span — yesterday's prediction was under the old climate).
  final bool Function()? suppressForeshadow;

  WeatherInjection({
    required this.getWeather,
    required this.getPreviousSegment,
    required this.getUpcoming,
    this.suppressForeshadow,
  });

  String buildWeatherInjection() {
    final w = getWeather();
    if (w == null) return '';
    final parts = <String>[WeatherSegments.prose(w)];
    // Within-day change: '' when the sky is unchanged, one sentence when a
    // front moved through since the previous day-part (yesterday's night,
    // for a morning) — characters experience the shift instead of a silent
    // state swap.
    final prev = getPreviousSegment();
    if (prev != null) {
      final shift = WeatherSegments.transition(prev, w);
      if (shift.isNotEmpty) parts.add(shift);
    }
    // Foreshadow tomorrow only on notable transitions (incoming rain/storm/
    // snow/fog, a real clear-up, big temperature swings) so characters see
    // fronts coming instead of being ambushed — '' keeps the line unchanged.
    // Suppress on the first day of a mid-chat climate switch (span start).
    if (suppressForeshadow?.call() == true) {
      return parts.join(' ');
    }
    final next = getUpcoming();
    if (next != null) {
      final sign = WeatherEngine.foreshadow(w.day, next);
      if (sign.isNotEmpty) parts.add(sign);
    }
    return parts.join(' ');
  }
}
