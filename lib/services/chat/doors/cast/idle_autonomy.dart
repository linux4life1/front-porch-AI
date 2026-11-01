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

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_deps.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';

/// Dynamic ("AFK") autonomous responses: the idle timer's lifecycle. When
/// Dynamic Responses is on and the user goes quiet after a completed
/// exchange, the timer fires a solitary, user-unaware narrative turn. The
/// timer is per chat, so it behaves the same in 1:1 and group.
///
/// It fires only after a completed exchange ([hasCompletedExchange]) and
/// never while a turn is busy ([CastShellHooks.isTurnBusy] re-arms it).
class IdleAutonomy {
  IdleAutonomy(this._d);

  final CastDeps _d;

  Timer? _idleTimer;

  /// The hidden cue the idle turn's prompt carries, until it lands.
  String? pendingIdleCue;
  bool autoResponseInProgress = false;

  /// A reply has landed in this chat; the timer may arm.
  bool hasCompletedExchange = false;

  /// Idle turns in a row; capped by the persisted
  /// `dynamicResponseMaxMessages` the sidebar, `/afk` and Settings share.
  int consecutiveAutoResponses = 0;

  CastShellHooks get _h => _d.hooks;
  TurnEngine get _turn => _d.turn();
  GenerationSettings get _gen => _d.storage.generationSettings;

  /// Called when the user leaves the chat page.
  void pauseDynamicResponses() {
    cancelIdleTimer();
  }

  /// Called when the user re-enters the chat page.
  void resumeDynamicResponses() {
    if (!_gen.dynamicResponses) return;
    if (!hasCompletedExchange) return;
    if (_h.disposed()) return;
    resetIdleTimer();
  }

  /// Drives the production idle callback without waiting on a wall-clock
  /// timer. Tests still traverse every readiness guard and generation phase.
  /// Tests reach it through the bridge, which carries `@visibleForTesting`.
  void debugFireIdleTimerForTest() => _onIdleTimerFired();

  void resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_gen.dynamicResponses) return;
    if (!hasCompletedExchange) return;
    if (autoResponseInProgress) {
      final cooldown = _gen.dynamicResponseInterval * 2;
      _idleTimer = Timer(Duration(seconds: cooldown), _onIdleTimerFired);
      return;
    }
    final interval = _gen.dynamicResponseInterval;
    _idleTimer = Timer(Duration(seconds: interval), _onIdleTimerFired);
  }

  void cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    pendingIdleCue = null;
    autoResponseInProgress = false;
    consecutiveAutoResponses = 0;
  }

  void _onIdleTimerFired() {
    if (_h.disposed()) return;
    if (_turn.isTurnBusy) {
      resetIdleTimer();
      return;
    }
    if (_h.ttsSpeaking()) {
      resetIdleTimer();
      return;
    }
    if (!_h.mouthReady()) {
      resetIdleTimer();
      return;
    }
    if (consecutiveAutoResponses >= _gen.dynamicResponseMaxMessages) {
      return;
    }

    // The away pace on the clock, the speaker and their bars, and the cue
    // built for that speaker (the shell's half; see the idle part).
    final staged = _h.stageIdleTurn();
    pendingIdleCue = staged.cue;
    autoResponseInProgress = true;
    consecutiveAutoResponses++;

    _turn
        .generate(
          GenerationMode.normal,
          forceSpeaker: staged.speaker,
          autonomous: true,
        )
        .then((_) {
          pendingIdleCue = null;
          resetIdleTimer();
          autoResponseInProgress = false;
        })
        .catchError((_) {
          pendingIdleCue = null;
          autoResponseInProgress = false;
          resetIdleTimer();
        });
  }
}
