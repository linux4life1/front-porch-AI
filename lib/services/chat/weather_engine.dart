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

/// Deterministic story weather (docs/design/living-time-features.md §3).
///
/// Pure math over state the app already has — NOTHING is stored. The same
/// (sessionSeed, dayCount, date) always yields the same weather, on every
/// platform and across app restarts, so save/load, group re-entry, and the
/// web facade all agree for free. Determinism rests on a hand-rolled FNV-1a
/// hash + xorshift PRNG because Dart's String.hashCode is not guaranteed
/// stable across VM versions.
///
/// Day-to-day continuity is a persistence-biased walk from day 1: each day
/// either keeps yesterday's condition (45%) or resamples from the season's
/// weight table, so fronts roll through over a few days instead of strobing.
/// The walk is O(dayCount) of integer math — microseconds even for
/// thousand-day chats — so callers just call [weatherFor]; no caching layer
/// is needed (the Riverpod UI provider memoizes by inputs anyway).
library;

enum WeatherCondition { clear, cloudy, overcast, fog, rain, storm, snow }

enum TempBand { cold, cool, mild, warm, hot }

/// One story day's weather. Value type (== by fields) so Riverpod family
/// consumers rebuild only on real change.
class DailyWeather {
  final WeatherCondition condition;
  final TempBand temp;

  /// 'winter' | 'spring' | 'summer' | 'autumn' (northern-hemisphere months).
  final String season;

  const DailyWeather({
    required this.condition,
    required this.temp,
    required this.season,
  });

  @override
  bool operator ==(Object other) =>
      other is DailyWeather &&
      other.condition == condition &&
      other.temp == temp &&
      other.season == season;

  @override
  int get hashCode => Object.hash(condition, temp, season);

  @override
  String toString() => 'DailyWeather(${condition.name}, ${temp.name}, $season)';
}

class WeatherEngine {
  WeatherEngine._(); // static-only

  /// Persistence chance of keeping yesterday's condition (weather "fronts").
  static const int _stayPermille = 450;

  /// Season condition weights (clear, cloudy, overcast, fog, rain, storm,
  /// snow). Snow weight is only nonzero in winter; a snow draw outside cold
  /// temps demotes to rain in [_conditionFor].
  static const Map<String, List<int>> _seasonWeights = {
    'winter': [20, 20, 20, 10, 10, 2, 18],
    'spring': [30, 25, 15, 8, 18, 4, 0],
    'summer': [45, 22, 8, 2, 12, 11, 0],
    'autumn': [24, 24, 20, 10, 16, 6, 0],
  };

  /// Season base temperature band index into [TempBand.values].
  static const Map<String, int> _seasonBaseTemp = {
    'winter': 0, // cold
    'spring': 2, // mild
    'summer': 3, // warm
    'autumn': 1, // cool
  };

  static String seasonOf(DateTime date) {
    switch (date.month) {
      case 12:
      case 1:
      case 2:
        return 'winter';
      case 3:
      case 4:
      case 5:
        return 'spring';
      case 6:
      case 7:
      case 8:
        return 'summer';
      default:
        return 'autumn';
    }
  }

  /// The weather for story day [dayCount] of the chat whose stable identity
  /// is [sessionSeed] (the session id), where [date] is the story-clock date
  /// of that day (used for seasons — day d in the walk is dated
  /// `date - (dayCount - d)` days).
  static DailyWeather weatherFor({
    required String sessionSeed,
    required int dayCount,
    required DateTime date,
  }) {
    final days = dayCount < 1 ? 1 : dayCount;
    final base = _fnv1a(sessionSeed);

    WeatherCondition cond = WeatherCondition.clear;
    TempBand temp = TempBand.mild;
    String season = 'spring';
    for (int d = 1; d <= days; d++) {
      final dayDate = date.subtract(Duration(days: days - d));
      season = seasonOf(dayDate);
      final rng = _Xorshift(base ^ (d * 0x9E3779B9));
      final stay = d > 1 && rng.nextPermille() < _stayPermille;
      temp = _tempFor(season, rng);
      if (!stay) {
        cond = _conditionFor(season, temp, rng);
      } else if (cond == WeatherCondition.snow && temp != TempBand.cold) {
        cond = WeatherCondition.rain; // thaw: persisted snow melts to rain
      }
    }
    return DailyWeather(condition: cond, temp: temp, season: season);
  }

  static TempBand _tempFor(String season, _Xorshift rng) {
    final jitter = rng.nextPermille() < 250
        ? -1
        : rng.nextPermille() < 250
        ? 1
        : 0;
    final idx = ((_seasonBaseTemp[season] ?? 2) + jitter).clamp(
      0,
      TempBand.values.length - 1,
    );
    return TempBand.values[idx];
  }

  static WeatherCondition _conditionFor(
    String season,
    TempBand temp,
    _Xorshift rng,
  ) {
    final weights = _seasonWeights[season] ?? _seasonWeights['spring']!;
    final total = weights.fold(0, (a, b) => a + b);
    var roll = rng.next() % total;
    for (int i = 0; i < weights.length; i++) {
      roll -= weights[i];
      if (roll < 0) {
        final cond = WeatherCondition.values[i];
        if (cond == WeatherCondition.snow && temp != TempBand.cold) {
          return WeatherCondition.rain;
        }
        return cond;
      }
    }
    return WeatherCondition.clear; // unreachable; weights are non-empty
  }

  // ── Shared display helpers (single source for desktop UI, injection, web) ──

  static String emoji(WeatherCondition c) {
    switch (c) {
      case WeatherCondition.clear:
        return '☀️';
      case WeatherCondition.cloudy:
        return '⛅';
      case WeatherCondition.overcast:
        return '☁️';
      case WeatherCondition.fog:
        return '🌫️';
      case WeatherCondition.rain:
        return '🌧️';
      case WeatherCondition.storm:
        return '⛈️';
      case WeatherCondition.snow:
        return '❄️';
    }
  }

  static String label(DailyWeather w) {
    final cond = switch (w.condition) {
      WeatherCondition.clear => 'Clear',
      WeatherCondition.cloudy => 'Partly cloudy',
      WeatherCondition.overcast => 'Overcast',
      WeatherCondition.fog => 'Foggy',
      WeatherCondition.rain => 'Rain',
      WeatherCondition.storm => 'Storm',
      WeatherCondition.snow => 'Snow',
    };
    return '$cond · ${_tempWord(w.temp)}';
  }

  /// One banded prose phrase for the prompt state block — words only, no
  /// numbers (prompt-state-injection.md contract).
  static String prose(DailyWeather w) {
    final t = _tempWord(w.temp);
    final s = _seasonWord(w.season);
    switch (w.condition) {
      case WeatherCondition.clear:
        return 'The sky is clear and the air is $t — a bright $s day.';
      case WeatherCondition.cloudy:
        return 'Broken clouds drift over a $t $s day.';
      case WeatherCondition.overcast:
        return 'A flat grey overcast hangs over this $t $s day.';
      case WeatherCondition.fog:
        return 'Fog has settled in, $t and muffling — deep $s.';
      case WeatherCondition.rain:
        return 'A $t, steady rain is falling — $s weather.';
      case WeatherCondition.storm:
        return 'A storm is rolling through, $t wind and hard rain — wild $s weather.';
      case WeatherCondition.snow:
        return 'Snow is falling in the $t air — deep $s.';
    }
  }

  static String _tempWord(TempBand t) {
    switch (t) {
      case TempBand.cold:
        return 'cold';
      case TempBand.cool:
        return 'cool';
      case TempBand.mild:
        return 'mild';
      case TempBand.warm:
        return 'warm';
      case TempBand.hot:
        return 'hot';
    }
  }

  static String _seasonWord(String season) {
    switch (season) {
      case 'winter':
        return 'midwinter';
      case 'summer':
        return 'high-summer';
      default:
        return season;
    }
  }

  /// FNV-1a 32-bit — stable across platforms/VM versions, unlike
  /// String.hashCode.
  static int _fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash == 0 ? 0x811c9dc5 : hash;
  }
}

/// Tiny xorshift32 — deterministic, allocation-free.
class _Xorshift {
  int _state;
  _Xorshift(int seed) : _state = (seed & 0xFFFFFFFF) == 0 ? 0xDEADBEEF : (seed & 0xFFFFFFFF);

  int next() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >>> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state;
  }

  int nextPermille() => next() % 1000;
}
