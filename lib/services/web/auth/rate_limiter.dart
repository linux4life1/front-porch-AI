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

/// In-memory login throttling for the web secure-login.
///
/// Two layers:
/// - Per-username exponential backoff after [_freeAttempts] consecutive
///   failures (base [_baseLockout], doubling, capped at [_maxLockout]).
/// - Per-IP sliding window cap to blunt distributed guessing across usernames.
///
/// State is intentionally in-memory only: this is a single-host desktop app, so
/// counters resetting on restart is acceptable and keeps the implementation
/// simple. Inject [now] in tests for deterministic time.
class RateLimiter {
  RateLimiter({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static const int _freeAttempts = 5;
  static const Duration _baseLockout = Duration(seconds: 15);
  static const Duration _maxLockout = Duration(minutes: 15);

  static const int _ipWindowMax = 50;
  static const Duration _ipWindow = Duration(minutes: 5);

  final Map<String, _Attempts> _byUser = {};
  final Map<String, List<DateTime>> _byIp = {};

  /// Remaining lockout for [username], or null if a login attempt is allowed.
  Duration? lockoutFor(String username) {
    final a = _byUser[username];
    if (a == null || a.failures < _freeAttempts) return null;
    final lockUntil = a.lastFailure.add(_lockoutDuration(a.failures));
    final remaining = lockUntil.difference(_now());
    return remaining.isNegative ? null : remaining;
  }

  /// Whether [ip] is within the sliding-window attempt cap.
  bool ipAllowed(String? ip) {
    if (ip == null || ip.isEmpty) return true;
    final cutoff = _now().subtract(_ipWindow);
    final hits = (_byIp[ip] ??= [])..removeWhere((t) => t.isBefore(cutoff));
    return hits.length < _ipWindowMax;
  }

  /// Record a failed attempt for backoff + window accounting.
  void recordFailure(String username, String? ip) {
    final a = _byUser.putIfAbsent(username, _Attempts.new);
    a.failures++;
    a.lastFailure = _now();
    _touchIp(ip);
  }

  /// Clear a username's failure streak after a successful login.
  void recordSuccess(String username) => _byUser.remove(username);

  void _touchIp(String? ip) {
    if (ip == null || ip.isEmpty) return;
    (_byIp[ip] ??= []).add(_now());
  }

  Duration _lockoutDuration(int failures) {
    final over = failures - _freeAttempts; // 0 at the first locked attempt
    final ms = _baseLockout.inMilliseconds * (1 << over.clamp(0, 16));
    return ms >= _maxLockout.inMilliseconds
        ? _maxLockout
        : Duration(milliseconds: ms);
  }
}

class _Attempts {
  int failures = 0;
  DateTime lastFailure = DateTime.fromMillisecondsSinceEpoch(0);
}
