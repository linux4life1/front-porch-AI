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

/// Weather fragment for the words-only state block
/// (docs/design/living-time-features.md §3). One banded prose line, no
/// numbers, directly after the time line. Returns '' when weather is off —
/// the composer drops empty fragments, so the block shape is unchanged for
/// users with the feature disabled. State lives in WeatherEngine (pure) via
/// the ChatService gate; this leaf only renders words.
class WeatherInjection {
  final DailyWeather? Function() getWeather;

  WeatherInjection({required this.getWeather});

  String buildWeatherInjection() {
    final w = getWeather();
    if (w == null) return '';
    return WeatherEngine.prose(w);
  }
}
