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

import 'dart:io' show InternetAddress;

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
///
/// The maps are BOUNDED. Both tracked keys are attacker-chosen — the submitted
/// username, and a client IP (real TCP peer, or `X-Forwarded-For` only when
/// the immediate peer is loopback; see `requestClientIp`) — and a login
/// attempt for an unknown username short-circuits before Argon2, so an
/// unauthenticated loop against a LAN/tunnel-exposed server used to mint one
/// permanent map entry per request until the process died. Every mutator
/// therefore sweeps entries that can no longer affect a decision (empty
/// windows, streaks nobody is riding), and a hard [_maxKeys] ceiling drops
/// the least-relevant remainder.
class RateLimiter {
  RateLimiter({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static const int _freeAttempts = 5;
  static const Duration _baseLockout = Duration(seconds: 15);
  static const Duration _maxLockout = Duration(minutes: 15);

  static const int _ipWindowMax = 50;
  static const Duration _ipWindow = Duration(minutes: 5);

  /// First-run setup is a rarer, higher-stakes public endpoint — tighter cap
  /// than login so LAN/tunnel exposure cannot brute-claim the account.
  static const int setupWindowMax = 10;
  static const Duration setupWindow = Duration(minutes: 15);

  /// Hard ceiling on tracked keys per map — far above any real household's
  /// usernames-tried / client-IPs-seen, so it only ever bites under a flood.
  static const int _maxKeys = 2048;

  /// Low-water mark an over-cap sweep trims down to, so the O(n log n) ordering
  /// pass is paid once per few hundred requests instead of once per request.
  static const int _keepKeys = _maxKeys * 3 ~/ 4;

  /// A username's failure streak is forgotten once it has been idle this long:
  /// comfortably past [_maxLockout], so a genuine user's escalation still
  /// survives their next try, while one-shot probe usernames evaporate.
  static const Duration _userIdleTtl = Duration(minutes: 30);

  final Map<String, _Attempts> _byUser = {};
  final Map<String, List<DateTime>> _byIp = {};
  final Map<String, List<DateTime>> _setupByIp = {};

  /// Remaining lockout for [username], or null if a login attempt is allowed.
  Duration? lockoutFor(String username) {
    final a = _byUser[username];
    if (a == null || a.failures < _freeAttempts) return null;
    final lockUntil = a.lastFailure.add(_lockoutDuration(a.failures));
    final remaining = lockUntil.difference(_now());
    return remaining.isNegative ? null : remaining;
  }

  /// Whether [ip] is within the sliding-window attempt cap. A read never mints
  /// an entry — otherwise merely *asking* about a spoofed IP would grow the map.
  ///
  /// Empty / whitespace / null is not unlimited: those share one `_unknown`
  /// bucket so a missing IP cannot skip the cap.
  bool ipAllowed(String? ip) {
    final key = _ipKey(ip);
    final hits = _byIp[key];
    if (hits == null) return true;
    final cutoff = _now().subtract(_ipWindow);
    hits.removeWhere((t) => t.isBefore(cutoff));
    if (hits.isEmpty) _byIp.remove(key);
    return hits.length < _ipWindowMax;
  }

  /// Record a failed attempt for backoff + window accounting.
  void recordFailure(String username, String? ip) {
    if (_byUser.length >= _maxKeys) _sweep();
    final a = _byUser.putIfAbsent(username, _Attempts.new);
    a.failures++;
    a.lastFailure = _now();
    _touchIp(ip);
  }

  /// Clear a username's failure streak after a successful login.
  void recordSuccess(String username) => _byUser.remove(username);

  /// Whether [ip] may attempt first-run setup (stricter sliding window).
  bool setupIpAllowed(String? ip) {
    final key = _ipKey(ip);
    final hits = _setupByIp[key];
    if (hits == null) return true;
    final cutoff = _now().subtract(setupWindow);
    hits.removeWhere((t) => t.isBefore(cutoff));
    if (hits.isEmpty) _setupByIp.remove(key);
    return hits.length < setupWindowMax;
  }

  /// Count a setup attempt (success or fail) toward the setup IP window.
  void recordSetupAttempt(String? ip) {
    final key = _ipKey(ip);
    if (_setupByIp.length >= _maxKeys) _sweep();
    (_setupByIp[key] ??= []).add(_now());
  }

  /// Number of keys currently tracked across all three windows. Exposed so the
  /// boundedness guarantee is testable (and so a leak would be visible).
  int get trackedKeys => _byUser.length + _byIp.length + _setupByIp.length;

  void _touchIp(String? ip) {
    final key = _ipKey(ip);
    if (_byIp.length >= _maxKeys) _sweep();
    (_byIp[key] ??= []).add(_now());
  }

  /// Empty / whitespace / unparsed / loopback is not a valid IP — one
  /// shared fail-closed bucket. A client-chosen token must not mint a key.
  String _ipKey(String? ip) {
    final trimmed = ip?.trim() ?? '';
    if (trimmed.isEmpty) return '_unknown';
    final parsed = InternetAddress.tryParse(trimmed);
    if (parsed == null || parsed.isLoopback) return '_unknown';
    return trimmed;
  }

  /// Drop everything that can no longer change an answer: IP windows whose
  /// timestamps have all aged out, and username streaks that are idle past
  /// [_userIdleTtl] with no live lockout. If a flood still leaves a map over
  /// [_maxKeys] the freshest entries are kept and the rest discarded —
  /// bounded memory beats a perfect count, and keeping the freshest preserves
  /// the per-username lockout that actually guards the password.
  void _sweep() {
    final now = _now();

    void prune(Map<String, List<DateTime>> map, Duration window) {
      final cutoff = now.subtract(window);
      map.removeWhere((_, hits) {
        hits.removeWhere((t) => t.isBefore(cutoff));
        return hits.isEmpty;
      });
      if (map.length <= _keepKeys) return;
      final byRecency = map.keys.toList()
        ..sort((a, b) => map[b]!.last.compareTo(map[a]!.last));
      for (final k in byRecency.skip(_keepKeys)) {
        map.remove(k);
      }
    }

    prune(_byIp, _ipWindow);
    prune(_setupByIp, setupWindow);

    _byUser.removeWhere((_, a) {
      if (now.difference(a.lastFailure) <= _userIdleTtl) return false;
      if (a.failures < _freeAttempts) return true;
      return a.lastFailure.add(_lockoutDuration(a.failures)).isBefore(now);
    });
    if (_byUser.length > _keepKeys) {
      final byRecency = _byUser.keys.toList()
        ..sort(
          (a, b) => _byUser[b]!.lastFailure.compareTo(_byUser[a]!.lastFailure),
        );
      for (final k in byRecency.skip(_keepKeys)) {
        _byUser.remove(k);
      }
    }
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
