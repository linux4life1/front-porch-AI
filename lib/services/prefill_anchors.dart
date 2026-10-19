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

/// The confirmed-token samples of ONE prompt pass, and the prefill speed they
/// prove. The speed comes from this pass alone: a previous request's speed
/// (Kobold's `last_process_speed`) was usually a smaller, shallower pass and
/// ran the bar far ahead of the console (Discord report, 2026-10-19).
class PrefillAnchors {
  final List<(int, DateTime)> _samples = [];

  /// When the latest confirmed count arrived, or null before the first.
  DateTime? get lastAt => _samples.lastOrNull?.$2;

  void clear() => _samples.clear();

  /// Record [tokens] confirmed at [at]. Only growth is a new sample.
  void add(int tokens, DateTime at) {
    final last = _samples.lastOrNull;
    if (last != null && tokens <= last.$1) return;
    _samples.add((tokens, at));
  }

  /// Tokens per second over the latest interval, slowed by the trend across
  /// the pass: prefill gets slower per token as the context deepens, so the
  /// batch still running is slower than the one that just finished. Null
  /// until the pass has two samples.
  double? get rate {
    if (_samples.length < 2) return null;
    final latest = _speed(_samples[_samples.length - 2], _samples.last);
    if (latest == null || _samples.length < 3) return latest;
    final earlier = _speed(_samples.first, _samples[_samples.length - 2]);
    if (earlier == null) return latest;
    return latest * (latest / earlier).clamp(0.5, 1.0);
  }

  static double? _speed((int, DateTime) from, (int, DateTime) to) {
    final seconds = to.$2.difference(from.$2).inMilliseconds / 1000.0;
    if (seconds <= 0) return null;
    return (to.$1 - from.$1) / seconds;
  }
}
