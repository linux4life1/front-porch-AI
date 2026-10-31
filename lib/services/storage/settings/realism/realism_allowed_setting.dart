// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import '../settings_base.dart';

/// Porch Life "Realism Engine": whether Realism may run in any chat. Within
/// it each chat's own switch decides, and a card or a group seeds new chats.
///
/// A missing pref reads as ON, so an install upgrading to this switch keeps
/// every chat exactly as it was and nothing is written at startup. Read live
/// from the preferences (no load step). Not `realismDefault`: that one only
/// starts new chats with Realism on, and it stays off for most people.
///
/// It also remembers what a closed chat needs to score its starting point
/// when it next opens: the last stretch Realism was blocked, and the chats
/// the existing-chats question switched on.
mixin RealismAllowedSetting on SettingsBase {
  static const _key = 'realism_allowed';
  static const _blockedKey = 'realism_blocked_at';
  static const _sinceKey = 'realism_allowed_since';
  static const _owedKey = 'realism_start_owed';

  // What this run set, ahead of the preferences (which may not be loaded).
  bool? _allowedSet;
  DateTime? _blockedSet;
  DateTime? _sinceSet;
  Set<String>? _owedSet;

  bool get realismAllowed => _allowedSet ?? prefs?.getBool(k(_key)) ?? true;

  /// When Porch Life last started blocking Realism; null when it never has.
  DateTime? get realismBlockedAt => _blockedSet ?? _readTime(_blockedKey);

  /// When Porch Life last went from blocking Realism to allowing it.
  DateTime? get realismAllowedSince => _sinceSet ?? _readTime(_sinceKey);

  /// Whether a chat last saved at [savedAt] was saved while Realism was
  /// blocked: in the last blocked stretch, compared in whole seconds as
  /// session rows keep their times.
  bool savedWhileRealismBlocked(DateTime savedAt) {
    final from = realismBlockedAt;
    final to = realismAllowedSince;
    if (from == null || to == null || to.isBefore(from)) return false;
    final at = _seconds(savedAt);
    return !at.isBefore(from) && at.isBefore(to);
  }

  /// [now] is when it changed (the caller's clock; tests pass their own).
  Future<void> setRealismAllowed(bool value, {DateTime? now}) async {
    final was = realismAllowed;
    _allowedSet = value;
    await prefs?.setBool(k(_key), value);
    if (value != was) {
      final at = _seconds(now ?? DateTime.now());
      if (value) {
        _sinceSet = at;
      } else {
        _blockedSet = at;
      }
      await prefs?.setInt(
        k(value ? _sinceKey : _blockedKey),
        at.millisecondsSinceEpoch,
      );
    }
    notify();
  }

  /// Chats the existing-chats question switched on while closed: each scores
  /// its starting point when it next opens, wherever its last save fell.
  Set<String> get realismStartOwed =>
      _owedSet ??= (prefs?.getStringList(k(_owedKey)) ?? const []).toSet();

  Future<void> oweRealismStart(Iterable<String> sessionIds) =>
      _writeOwed({...realismStartOwed, ...sessionIds});

  /// The chat opened: whatever it was owed is being paid now.
  Future<void> settleRealismStart(String sessionId) async {
    if (!realismStartOwed.contains(sessionId)) return;
    await _writeOwed({...realismStartOwed}..remove(sessionId));
  }

  Future<void> _writeOwed(Set<String> ids) async {
    _owedSet = ids;
    await prefs?.setStringList(k(_owedKey), ids.toList());
  }

  DateTime? _readTime(String key) {
    final ms = prefs?.getInt(k(key));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static DateTime _seconds(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
    t.millisecondsSinceEpoch ~/ 1000 * 1000,
  );
}
