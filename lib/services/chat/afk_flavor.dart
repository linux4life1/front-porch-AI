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

/// AFK snapshot flavor (Living Time — the away-time upgrade): pure,
/// deterministic selection of 1–2 directive lines that let the autonomous
/// cue USE the state already in the prompt (time of day, weather, fixation,
/// hot journal memories) instead of defaulting to meals-and-naps forever.
///
/// Deliberately a picker, not a pile: stacking every system into one cue
/// dilutes into mush, so a priority ladder chooses the strongest flavor and
/// [snapshotIndex] rotates among ties so consecutive snapshots vary —
/// deterministically (same inputs → same cue), like everything else in the
/// time system.
class AfkFlavor {
  AfkFlavor._(); // static-only

  /// Preamble time phrase for [periods] story-periods per snapshot (the
  /// away-pace setting). Words only.
  static String timePhrase(int periods) {
    if (periods >= 6) return 'A full day has passed.';
    if (periods >= 3) return 'Much of the day has slipped by.';
    return 'A few hours have passed.';
  }

  /// Montage guidance when a snapshot spans more than a couple of hours —
  /// the prose should read as a span, not a single frozen moment.
  static String spanDirective(int periods) {
    if (periods >= 6) {
      return 'Let the snapshot read as a whole day passing — a montage of '
          'two or three beats, not one frozen moment.';
    }
    if (periods >= 3) {
      return 'Let the snapshot cover the stretch of hours — one main beat '
          'with the day moving around it.';
    }
    return '';
  }

  /// The 1–2 flavor directives. Priority: sleep (night) → weather shelter /
  /// outdoors → fixation intrusion → memory drift (the default — solitary
  /// time is when people process). A second line is added from further down
  /// the ladder on alternating snapshots so a 3-snapshot run doesn't repeat.
  static List<String> directives({
    required String timeOfDay,
    DailyWeather? weather,
    String fixation = '',
    int snapshotIndex = 0,
  }) {
    final ladder = <String>[];

    if (timeOfDay == 'night') {
      ladder.add(
        'It is deep in the night — winding down or sleep is the natural '
        'shape of this moment.',
      );
    } else if (timeOfDay == 'evening') {
      ladder.add(
        'The day is ending — let the scene lean toward evening rituals and '
        'lowering energy.',
      );
    }

    if (weather != null) {
      final rough =
          weather.condition == WeatherCondition.storm ||
          weather.condition == WeatherCondition.rain ||
          weather.condition == WeatherCondition.snow ||
          weather.temp == TempBand.hot ||
          weather.temp == TempBand.cold;
      if (rough) {
        ladder.add(
          'The weather is keeping them in — let it shape the scene\'s '
          'textures (sound on the windows, warmth sought or heat endured).',
        );
      } else if (weather.condition == WeatherCondition.clear &&
          (weather.temp == TempBand.mild || weather.temp == TempBand.warm)) {
        ladder.add(
          'It is a fine day out — this moment may naturally happen outdoors.',
        );
      }
    }

    if (fixation.trim().isNotEmpty) {
      ladder.add(
        'Their current preoccupation ($fixation) may intrude on idle '
        'thoughts, uninvited.',
      );
    }

    // The universal floor: reflection. Always present so the ladder is
    // never empty, and the strongest reason AFK stops feeling like chores.
    ladder.add(
      'While they do, a recent memory may surface and quietly color their '
      'mood — let the story so far leak into the moment.',
    );

    if (ladder.length == 1) return ladder;
    // Primary = top of ladder; secondary rotates through the rest by
    // snapshot index so consecutive snapshots vary deterministically.
    final secondary = ladder[1 + (snapshotIndex % (ladder.length - 1))];
    return [ladder.first, if (secondary != ladder.first) secondary];
  }
}
