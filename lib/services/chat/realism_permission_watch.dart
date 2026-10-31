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

import 'package:flutter/foundation.dart';

/// Porch Life's Realism permission as the open chat's gate reads it.
///
/// Porch Life can change from the desktop or the phone at any moment, a
/// reply mid-stream included. A turn keeps the permission it started with:
/// a change made while a turn is in flight lands when that turn settles, so
/// a reply never has its post-generation passes run (or skipped) against
/// pre-turn evals that ran the other way. Between turns a change lands at
/// once. [onChange] hears each change as it lands.
class RealismPermissionWatch {
  /// [turn] notifies when a turn's state changes; [turnBusy] says whether
  /// one is in flight. [ready] completes once the settings have loaded: the
  /// permission is read again then, so a value loaded after this was built
  /// is not taken for a change.
  RealismPermissionWatch({
    required bool Function() allowed,
    required this.turnBusy,
    required this.turn,
    required this.onChange,
    Future<void>? ready,
  }) : _read = allowed,
       _allowed = allowed() {
    if (ready != null) unawaited(ready.then((_) => _allowed = _read()));
  }

  final bool Function() _read;
  final bool Function() turnBusy;
  final Listenable turn;

  /// Called with the permission each time a change lands.
  final void Function(bool allowed) onChange;

  bool _allowed;
  bool _waiting = false;

  /// The permission the gate reads: the settings', except during a turn
  /// that started before they changed.
  bool get allowed => _allowed;

  /// The settings listener. Settings notify for every pref, so most calls
  /// find no change.
  void settingsChanged() {
    if (_read() == _allowed) return;
    if (turnBusy()) {
      if (!_waiting) {
        _waiting = true;
        turn.addListener(_turnChanged);
      }
      return;
    }
    _land();
  }

  void _turnChanged() {
    if (turnBusy()) return;
    _waiting = false;
    turn.removeListener(_turnChanged);
    // Out of the notification that reported the settle.
    scheduleMicrotask(() {
      if (_read() != _allowed && !turnBusy()) _land();
    });
  }

  void _land() {
    _allowed = _read();
    onChange(_allowed);
  }
}

/// The scan that scores a chat's starting point when its Realism starts
/// running. It never runs beside a turn or another scan: asked for while
/// either is in flight, it waits for them to settle, then runs once for the
/// chat it was asked for (a chat left meanwhile is not scanned). [start]
/// re-checks whether a scan is still owed, so asking twice scans once.
class RealismStartQueue {
  RealismStartQueue({
    required this.busy,
    required this.turn,
    required this.chatId,
    required this.start,
  });

  /// A turn or a scan in flight.
  final bool Function() busy;
  final Listenable turn;
  final String? Function() chatId;
  final void Function() start;

  String? _owedFor;
  bool _waiting = false;

  /// Whether a scan is waiting for a turn or another scan to settle.
  bool get waiting => _waiting;

  void request() {
    if (!busy()) {
      start();
      return;
    }
    _owedFor = chatId();
    if (_waiting) return;
    _waiting = true;
    turn.addListener(_turnChanged);
  }

  void _turnChanged() {
    if (busy()) return;
    _waiting = false;
    turn.removeListener(_turnChanged);
    final owed = _owedFor;
    _owedFor = null;
    scheduleMicrotask(() {
      if (owed == chatId()) request();
    });
  }
}
