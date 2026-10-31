// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:async';

/// Watches Porch Life's Realism permission from the settings it is read
/// from. Every chat reads the permission live, so nothing has to be pushed
/// to it; this only tells the open chat the moment the permission changes,
/// so it can repaint and, when Realism has just become allowed, score its
/// starting point the way turning its own switch on does.
class RealismPermissionWatch {
  /// [ready] completes once the settings have loaded: the permission is
  /// read again then, so a value loaded after this was built is not taken
  /// for a change.
  RealismPermissionWatch({
    required bool Function() allowed,
    required this.onChange,
    Future<void>? ready,
  }) : _allowed = allowed,
       _was = allowed() {
    if (ready != null) unawaited(ready.then((_) => _was = _allowed()));
  }

  final bool Function() _allowed;

  /// Called with the new permission, once per change.
  final void Function(bool allowed) onChange;

  bool _was;

  /// The settings listener. Settings notify for every pref, so most calls
  /// find no change.
  void settingsChanged() {
    final now = _allowed();
    if (now == _was) return;
    _was = now;
    onChange(now);
  }
}
