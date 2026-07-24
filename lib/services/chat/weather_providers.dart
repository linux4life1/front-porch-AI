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

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:front_porch_ai/services/chat/weather_engine.dart';

part 'weather_providers.g.dart';

/// Riverpod surface for weather (Living Time §3) — @riverpod codegen style
/// (project standard, maintainer directive 2026-07-21): family parameters
/// are plain named args, autoDispose is the default, and the provider is
/// memoized per-argument so the deterministic recompute runs only when the
/// story day/session actually changes. The engine stays pure; inputs cross
/// the Provider→Riverpod boundary as plain values handed down by the
/// existing widget tree (TimeStrip).
@riverpod
DailyWeather dailyWeather(
  Ref ref, {
  required String sessionSeed,
  required int dayCount,
  required DateTime date,
}) => WeatherEngine.weatherFor(
  sessionSeed: sessionSeed,
  dayCount: dayCount,
  date: date,
);
