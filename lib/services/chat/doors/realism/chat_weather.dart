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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/world_chain.dart';

/// The open chat's story weather. Pure recompute from existing state —
/// nothing stored, so save/load and group re-entry agree for free. Gate: a
/// MOVING clock + the global toggle + a climate author in the Setting's
/// chain. Weather is deterministic math over the day count and needs no
/// eval of its own; the Porch Life tab has always told users weather
/// depends on Passage of Time. Consumed by the injection leaf, the needs
/// decay modifiers, the sidebar TimeStrip and the web facade — one source.
class ChatWeather {
  ChatWeather(this._g);

  final RealismGraph _g;

  TimeService get _timeService => _g.time;
  String? get _sessionId => _g.session.currentSessionId;

  /// The climate the chat's spans give the current story day.
  Biome get activeChatBiome => _biomeAtDay(_timeService.dayCount);

  Biome _biomeAtDay(int day) => _g.places.biomes.biomeAt(day);

  /// Today's story weather, or null when off (living-time-features.md §3).
  DailyWeather? get currentWeather {
    final storage = _g.deps.services.storage;
    if (!_g.controls.clockRunning || !storage.realismSettings.weatherEnabled) {
      return null;
    }
    // The Setting's chain owns weather (locations slice 2): the nearest
    // climate-enabled ancestor authors it. Empty chain OR an all-lore-only
    // chain ⇒ off. Lore climate-on (e.g. Mars in Lore) never turns weather
    // on — a chain walk only ever reaches the Setting's own ancestors.
    final primaryId = _g.places.primaryId;
    final chain = primaryId == null
        ? const <World>[]
        : _g.deps.services.worlds.chainFor(primaryId);
    if (!chainAllowsClimate(chain)) {
      return null;
    }
    final seed = _sessionId;
    if (seed == null) return null;
    return WeatherEngine.weatherFor(
      sessionSeed: seed,
      dayCount: _timeService.dayCount,
      date: _timeService.clock,
      biomeAtDay: _biomeAtDay,
    );
  }

  /// Tomorrow's story weather under the same gate as [currentWeather].
  /// Because the engine is a prefix-stable deterministic walk, this forecast
  /// is exactly what day dayCount+1 will be when the story clock reaches it
  /// (dayCount is derived from the calendar date, so +1 day ⇔ +1 dayCount) —
  /// foreshadowed fronts always arrive (except the first day of a mid-chat
  /// climate switch — see [WeatherInjection.suppressForeshadow]).
  /// Recompute is O(dayCount) integer math, called once per turn by the
  /// injection and once per facade read.
  DailyWeather? get upcomingWeather {
    if (currentWeather == null) return null;
    return WeatherEngine.weatherFor(
      sessionSeed: _sessionId!,
      dayCount: _timeService.dayCount + 1,
      date: _timeService.clock.add(const Duration(days: 1)),
      biomeAtDay: _biomeAtDay,
    );
  }

  /// The current DAY-PART's weather (Living Time §3 v3): the day script's
  /// condition for the story-clock hour plus the deterministic °C. Same gate
  /// and recompute contract as [currentWeather] — nothing stored.
  SegmentWeather? get currentSegmentWeather {
    if (currentWeather == null) return null;
    return WeatherSegments.segmentWeatherFor(
      sessionSeed: _sessionId!,
      dayCount: _timeService.dayCount,
      date: _timeService.clock,
      hour: _timeService.clock.hour,
      biomeAtDay: _biomeAtDay,
    );
  }

  /// The segment BEFORE the current one — same day for afternoon/evening/
  /// night, yesterday's night for a morning (cross-day continuity, so
  /// "the rain has eased off" can span the night). Null on day 1 mornings
  /// (nothing came before) and whenever weather is off.
  SegmentWeather? get previousSegmentWeather {
    final now = currentSegmentWeather;
    return now == null ? null : previousSegmentBefore(now);
  }

  /// The segment before [now], the current day-part's weather.
  SegmentWeather? previousSegmentBefore(SegmentWeather now) {
    final day = _timeService.dayCount;
    return switch (now.segment) {
      DaySegment.morning =>
        day <= 1
            ? null
            : WeatherSegments.segmentWeatherFor(
                sessionSeed: _sessionId!,
                dayCount: day - 1,
                date: _timeService.clock.subtract(const Duration(days: 1)),
                hour: 23,
                biomeAtDay: _biomeAtDay,
              ),
      DaySegment.afternoon => _segmentAt(7),
      DaySegment.evening => _segmentAt(14),
      DaySegment.night => _segmentAt(18),
    };
  }

  SegmentWeather _segmentAt(int hour) => WeatherSegments.segmentWeatherFor(
    sessionSeed: _sessionId!,
    dayCount: _timeService.dayCount,
    date: _timeService.clock,
    hour: hour,
    biomeAtDay: _biomeAtDay,
  );
}
