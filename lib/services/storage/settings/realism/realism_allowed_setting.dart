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
/// from the preferences (no load step), so every chat sees a change on its
/// next read. Not `realismDefault`: that one only starts new chats with
/// Realism on, and it stays off for most people.
mixin RealismAllowedSetting on SettingsBase {
  static const _key = 'realism_allowed';
  static const _sinceKey = 'realism_allowed_since';

  // What this run set, ahead of the preferences (which may not be loaded).
  bool? _allowedSet;
  DateTime? _sinceSet;

  bool get realismAllowed => _allowedSet ?? prefs?.getBool(k(_key)) ?? true;

  /// When Porch Life last went from blocking Realism to allowing it; null
  /// when it never has. A chat last saved before then was saved while its
  /// Realism could not run, so it scores its starting point when it opens.
  DateTime? get realismAllowedSince {
    if (_sinceSet != null) return _sinceSet;
    final ms = prefs?.getInt(k(_sinceKey));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// [now] is when it changed (the caller's clock; tests pass their own).
  Future<void> setRealismAllowed(bool value, {DateTime? now}) async {
    final was = realismAllowed;
    _allowedSet = value;
    await prefs?.setBool(k(_key), value);
    if (value && !was) {
      final at = _sinceSet = now ?? DateTime.now();
      await prefs?.setInt(k(_sinceKey), at.millisecondsSinceEpoch);
    }
    notify();
  }
}
