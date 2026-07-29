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

library;

import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';

/// Intra-day weather + deterministic temperatures (Living Time §3 v3), on
/// top of the daily walk in weather_engine.dart.
///
/// Same contract as the daily engine: pure math, NOTHING stored, same inputs
/// → same output forever. The daily walk stays the untouched anchor (its
/// golden sequences must never change for existing chats), so this layer
/// derives its own INDEPENDENT seeded RNG streams from
/// [WeatherEngine.seedFor] — it never draws from the walk's RNG.
///
/// Each day picks one "script": a 4-segment (morning/afternoon/evening/
/// night) condition pattern built around the day's anchor condition. Scripts
/// encode the timing realism declaratively — fog belongs to mornings and
/// burns off, storms break in the afternoon or evening, rain fronts arrive
/// and clear — and every script contains the anchor condition, so the day's
/// headline (chip, forecast, season) keeps its meaning. Temperatures are a
/// per-day seeded °C within the band's range plus a fixed diurnal offset
/// (coolest at night, peak mid-afternoon). Numbers are for the UI ONLY —
/// the generation prompt stays words-only per prompt-state-injection.md.

enum DaySegment { morning, afternoon, evening, night }

/// One segment's weather. Value type (== by fields) so Riverpod family
/// consumers rebuild only on real change. Carries the daily anchor so
/// consumers can render both "now" and "today" without a second lookup.
class SegmentWeather {
  final DailyWeather day;
  final DaySegment segment;
  final WeatherCondition condition;

  /// This segment's temperature in whole °C (canonical unit; convert for
  /// display with [WeatherSegments.tempF]). UI-only — never in prompts.
  final int tempC;

  const SegmentWeather({
    required this.day,
    required this.segment,
    required this.condition,
    required this.tempC,
  });

  @override
  bool operator ==(Object other) =>
      other is SegmentWeather &&
      other.day == day &&
      other.segment == segment &&
      other.condition == condition &&
      other.tempC == tempC;

  @override
  int get hashCode => Object.hash(day, segment, condition, tempC);

  @override
  String toString() =>
      'SegmentWeather(${segment.name}, ${condition.name}, $tempC°C of $day)';
}

class WeatherSegments {
  WeatherSegments._(); // static-only

  /// Distinct mix constants so segment/temp streams never correlate with the
  /// daily walk (which mixes with 0x9E3779B9).
  static const int _kScriptMix = 0x85EBCA6B;
  static const int _kTempMix = 0xC2B2AE35;

  /// Day-part from the story-clock hour: morning 05–10, afternoon 11–16,
  /// evening 17–20, night otherwise (21–04, incl. the small hours).
  static DaySegment segmentForHour(int hour) {
    if (hour >= 5 && hour < 11) return DaySegment.morning;
    if (hour >= 11 && hour < 17) return DaySegment.afternoon;
    if (hour >= 17 && hour < 21) return DaySegment.evening;
    return DaySegment.night;
  }

  /// Weighted 4-segment scripts per anchor condition
  /// (morning, afternoon, evening, night). Invariants the tests pin: every
  /// script contains its anchor condition; fog-day mornings are always fog;
  /// storm segments only ever sit in the afternoon/evening (or a morning
  /// tail that fades before midday).
  static const Map<WeatherCondition, List<(int, List<WeatherCondition>)>>
  _scripts = {
    WeatherCondition.clear: [
      (40, [_cl, _cl, _cl, _cl]),
      (25, [_cy, _cl, _cl, _cl]), // morning cloud burning off
      (20, [_cl, _cl, _cy, _cl]),
      (15, [_ov, _cl, _cl, _cl]), // grey start, clearing
    ],
    WeatherCondition.cloudy: [
      (25, [_cy, _cy, _cy, _cy]),
      (20, [_ov, _cy, _cl, _cl]),
      (20, [_cl, _cy, _cy, _cy]),
      (15, [_cy, _cl, _cy, _ov]),
      (20, [_cy, _ov, _cy, _cl]),
    ],
    WeatherCondition.overcast: [
      (35, [_ov, _ov, _ov, _ov]),
      (25, [_cy, _ov, _ov, _ov]),
      (20, [_ov, _ov, _cy, _ov]),
      (20, [_fg, _ov, _ov, _ov]), // morning fog under a grey lid
    ],
    WeatherCondition.fog: [
      (30, [_fg, _cy, _cl, _cy]), // classic burn-off
      (25, [_fg, _fg, _cy, _fg]),
      (25, [_fg, _ov, _ov, _fg]),
      (20, [_fg, _fg, _ov, _ov]),
    ],
    WeatherCondition.rain: [
      (20, [_rn, _rn, _rn, _rn]),
      (25, [_ov, _rn, _rn, _ov]), // moves in midday
      (25, [_rn, _rn, _ov, _cy]), // clears by evening
      (30, [_cy, _ov, _rn, _rn]), // front arrives in the afternoon
    ],
    WeatherCondition.storm: [
      (30, [_ov, _st, _rn, _ov]), // afternoon break
      (35, [_cy, _ov, _st, _rn]), // evening break
      (20, [_rn, _st, _st, _rn]),
      (15, [_st, _rn, _ov, _cy]), // overnight storm's morning tail
    ],
    WeatherCondition.snow: [
      (25, [_sn, _sn, _sn, _sn]),
      (25, [_ov, _sn, _sn, _ov]),
      (30, [_cy, _ov, _sn, _sn]),
      (20, [_sn, _sn, _ov, _ov]),
    ],
  };

  static const _cl = WeatherCondition.clear;
  static const _cy = WeatherCondition.cloudy;
  static const _ov = WeatherCondition.overcast;
  static const _fg = WeatherCondition.fog;
  static const _rn = WeatherCondition.rain;
  static const _st = WeatherCondition.storm;
  static const _sn = WeatherCondition.snow;

  /// Per-band °C base ranges (min, max inclusive) — the day's base is drawn
  /// seeded within its band, so the number always agrees with the band word.
  static const Map<TempBand, (int, int)> _bandRangeC = {
    TempBand.cold: (-8, 2),
    TempBand.cool: (3, 10),
    TempBand.mild: (11, 17),
    TempBand.warm: (18, 25),
    TempBand.hot: (26, 34),
  };

  /// Fixed diurnal offsets from the day's base °C — coolest deep at night,
  /// peak mid-afternoon. Deterministic (no draws) so a segment's number is
  /// stable and the afternoon ≥ morning ordering is guaranteed.
  static const Map<DaySegment, int> _diurnalOffsetC = {
    DaySegment.morning: -3,
    DaySegment.afternoon: 2,
    DaySegment.evening: 0,
    DaySegment.night: -6,
  };

  /// The 4 segment conditions for one story day. Deterministic and
  /// independent of how far the day has advanced (prefix-stable within the
  /// day): the whole script is decided by (seed, dayCount, anchor).
  static List<WeatherCondition> segmentConditionsFor({
    required String sessionSeed,
    required int dayCount,
    required DateTime date,
    Biome? biome,
    Biome Function(int day)? biomeAtDay,
  }) {
    final day = WeatherEngine.weatherFor(
      sessionSeed: sessionSeed,
      dayCount: dayCount,
      date: date,
      biome: biome,
      biomeAtDay: biomeAtDay,
    );
    final scripts = _scripts[day.condition]!;
    final rng = WeatherRng(
      WeatherEngine.seedFor(sessionSeed) ^ (dayCount * _kScriptMix),
    );
    final total = scripts.fold(0, (a, s) => a + s.$1);
    var roll = rng.next() % total;
    for (final (weight, script) in scripts) {
      roll -= weight;
      if (roll < 0) return script;
    }
    return scripts.first.$2; // unreachable; weights are non-empty
  }

  /// The weather at [hour] of story day [dayCount] — condition from the
  /// day's script segment, temperature from the day's seeded base °C plus
  /// the segment's diurnal offset.
  static SegmentWeather segmentWeatherFor({
    required String sessionSeed,
    required int dayCount,
    required DateTime date,
    required int hour,
    Biome? biome,
    Biome Function(int day)? biomeAtDay,
  }) {
    final day = WeatherEngine.weatherFor(
      sessionSeed: sessionSeed,
      dayCount: dayCount,
      date: date,
      biome: biome,
      biomeAtDay: biomeAtDay,
    );
    final segment = segmentForHour(hour);
    final conditions = segmentConditionsFor(
      sessionSeed: sessionSeed,
      dayCount: dayCount,
      date: date,
      biome: biome,
      biomeAtDay: biomeAtDay,
    );
    final (lo, hi) = _bandRangeC[day.temp]!;
    final tempRng = WeatherRng(
      WeatherEngine.seedFor(sessionSeed) ^ (dayCount * _kTempMix),
    );
    final baseC = lo + (tempRng.next() % (hi - lo + 1));
    // Living Worlds: desert swings hard day/night; temperate amp is 1.0 so
    // pre-biome °C goldens stay bit-identical. Use the climate active today.
    final climateForDay = biomeAtDay != null
        ? biomeAtDay(dayCount < 1 ? 1 : dayCount)
        : (biome ?? Biome.temperate);
    final amp = climateForDay.diurnalAmplitude;
    final offset = (_diurnalOffsetC[segment]! * amp).round();
    return SegmentWeather(
      day: day,
      segment: segment,
      condition: conditions[segment.index],
      tempC: baseC + offset,
    );
  }

  // ── Display helpers (UI + web facade; numbers never enter prompts) ──

  static int tempF(int c) => (c * 9 / 5 + 32).round();

  static String formatTemp(int c, {required bool fahrenheit}) =>
      fahrenheit ? '${tempF(c)}°F' : '$c°C';

  /// Chip label: segment condition word + numeric temperature.
  static String label(SegmentWeather w, {required bool fahrenheit}) {
    final cond = switch (w.condition) {
      WeatherCondition.clear => 'Clear',
      WeatherCondition.cloudy => 'Partly cloudy',
      WeatherCondition.overcast => 'Overcast',
      WeatherCondition.fog => 'Foggy',
      WeatherCondition.rain => 'Rain',
      WeatherCondition.storm => 'Storm',
      WeatherCondition.snow => 'Snow',
    };
    return '$cond · ${formatTemp(w.tempC, fahrenheit: fahrenheit)}';
  }

  // ── Prompt prose (words only, no numbers — prompt-state contract) ──

  /// Banded dressing cue — the wardrobe signal the maintainer asked for,
  /// delivered in words the model actually acts on.
  static String dressCue(TempBand t) {
    switch (t) {
      case TempBand.cold:
        return 'coat-and-gloves cold';
      case TempBand.cool:
        return 'jacket weather';
      case TempBand.mild:
        return 'light-layers weather';
      case TempBand.warm:
        return 'shirtsleeve warmth';
      case TempBand.hot:
        return 'seek-the-shade heat';
    }
  }

  static String _segName(DaySegment s) => switch (s) {
    DaySegment.morning => 'this morning',
    DaySegment.afternoon => 'this afternoon',
    DaySegment.evening => 'this evening',
    DaySegment.night => 'tonight',
  };

  /// One words-only sentence for the current segment, ending with the
  /// dressing cue. Mirrors WeatherEngine.prose's register, but speaks about
  /// the day-part instead of the whole day.
  static String prose(SegmentWeather w) {
    final t = WeatherEngine.tempWord(w.day.temp);
    final when = _segName(w.segment);
    final base = switch (w.condition) {
      WeatherCondition.clear => 'The sky is clear $when, the air $t.',
      WeatherCondition.cloudy => 'Broken clouds drift by $when, the air $t.',
      WeatherCondition.overcast => 'A flat grey overcast hangs low $when.',
      WeatherCondition.fog => 'Fog has settled in $when, $t and muffling.',
      WeatherCondition.rain => 'A $t, steady rain is falling $when.',
      WeatherCondition.storm =>
        'A storm is breaking $when — $t wind and hard rain.',
      WeatherCondition.snow => 'Snow is falling $when in the $t air.',
    };
    return 'Outside it is ${dressCue(w.day.temp)}. $base';
  }

  /// Words-only within-day transition: how the sky changed since the
  /// previous segment (yesterday's night, for a morning). '' when the
  /// condition is unchanged — the composer keeps the line stable.
  static String transition(SegmentWeather prev, SegmentWeather now) {
    if (prev.condition == now.condition) return '';
    const wet = {
      WeatherCondition.rain,
      WeatherCondition.storm,
      WeatherCondition.snow,
    };
    final from = prev.condition;
    final to = now.condition;
    if (to == WeatherCondition.storm) {
      return 'The weather has turned — what was ${_conditionNoun(from)} '
          'earlier has broken into the storm.';
    }
    if (wet.contains(to) && !wet.contains(from)) {
      return 'The ${_conditionNoun(to)} moved in earlier, after '
          '${_conditionNoun(from)} skies.';
    }
    if (wet.contains(from) && !wet.contains(to)) {
      return 'The ${_conditionNoun(from)} has eased off since earlier, '
          'leaving ${_conditionNoun(to)} skies.';
    }
    if (from == WeatherCondition.fog) {
      return 'The morning fog has burned off.';
    }
    if (to == WeatherCondition.fog) {
      return 'Fog has been settling in as the air stills.';
    }
    final clearing = to.index < from.index; // clear < cloudy < overcast
    return clearing
        ? 'The sky has been clearing since earlier.'
        : 'The sky has been clouding over since earlier.';
  }

  static String _conditionNoun(WeatherCondition c) => switch (c) {
    WeatherCondition.clear => 'clear',
    WeatherCondition.cloudy => 'broken cloud',
    WeatherCondition.overcast => 'grey overcast',
    WeatherCondition.fog => 'fog',
    WeatherCondition.rain => 'rain',
    WeatherCondition.storm => 'storm',
    WeatherCondition.snow => 'snow',
  };
}
