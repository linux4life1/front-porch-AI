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
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';

import 'send_spine.dart';

/// The Chance Time park a send waits on, as the web and mobile clients see
/// it, and the manual spin.
///
/// The desktop pops its wheel from the one-shot [chanceTimePendingTrigger]
/// via a ChangeNotifier. Web clients (which drive the same shared
/// chat service over HTTP/WS) have no such hook and no spinning wheel, so
/// they observe the park through these accessors and resolve it with
/// [acceptPendingChanceTime]. All of this is UI-coordination glue for the
/// completer [SendTurn.run] parks on — the simulation is untouched, so
/// 1:1/group parity is unaffected.
class ChanceReveal {
  ChanceReveal(this._s);

  final SendSpine _s;

  ChanceTime get _chance => _s.controls.chance;
  ChaosModeService get _chaosModeService => _s.graph.chaos;
  CharacterCard? get nextCharacter => _s.entry.director.nextCharacter;
  CharacterCard? get activeCharacter => _s.session.activeCharacter;
  void notifyListeners() => _s.notify();

  /// True when auto-trigger fires. UI reads then calls consumeChanceTimeTrigger().
  bool get chanceTimePendingTrigger => _chance.pendingTrigger;

  /// True when a chaos event is queued for the next response (blocks manual spin + auto-trigger).
  bool get hasPendingChaosEvent => _chaosModeService.hasPendingChaosEvent;

  /// Called by the overlay once it has opened. Clears the auto-trigger flag.
  void consumeChanceTimeTrigger() => _chance.pendingTrigger = false;

  /// True from the moment a Chance Time parks [SendSpine.sendMessage] until
  /// it is accepted. The durable signal the web surface uses to show — and,
  /// after a phone wakes and reconnects, re-show — the reveal modal.
  bool get isAwaitingChanceTime =>
      _chance.webEvent != null ||
      (_chance.completer != null && !_chance.completer!.isCompleted);

  /// Manual SPIN NOW. Parks a pre-picked event until accept. No-op when
  /// chaos is off, an event is already queued, or a park is already live.
  bool requestManualChanceTime() {
    if (!_chaosModeService.chaosModeEnabled) return false;
    if (_chaosModeService.hasPendingChaosEvent) return false;
    if (_chance.webEvent != null) return false;
    final wheel = _chance.spinWheelEvents();
    if (wheel.isEmpty) return false;
    _chance.webEvent = wheel.first;
    _chance.webName = chanceTimeSpeakerName;
    notifyListeners();
    return true;
  }

  /// The speaker a Chance Time event is attributed to: the upcoming group
  /// speaker (a spin picks one ahead in random turn order), else the 1:1 host.
  /// Shared by the desktop wheel overlay and the web accept path so both
  /// attribute the event identically.
  String get chanceTimeSpeakerName =>
      nextCharacter?.name ?? activeCharacter?.name ?? 'Character';

  /// The pre-picked pending event with its placeholders resolved, for the web reveal
  /// modal. Null when nothing is parked.
  String? get webChanceTimeDisplay => _chance.webEvent == null
      ? null
      : _chance.resolveChanceTimeEvent(
          _chance.webEvent!,
          _chance.webName ?? chanceTimeSpeakerName,
        );

  /// Web/mobile "Accept Your Fate": applies the pre-picked pending event using
  /// the same attribution the desktop wheel uses, then lets generation resume.
  /// No-op if nothing is parked (e.g. the desktop already accepted).
  Future<void> acceptPendingChanceTime() async {
    final raw = _chance.webEvent;
    if (raw == null) return;
    // The name the reveal showed, even if a turn has passed since the spin.
    await _chance.applyChanceTimeResult(
      raw,
      _chance.webName ?? chanceTimeSpeakerName,
    );
  }
}

/// The Journal recap ("Where we are") controls.
///
/// The recap reuses the _summary scalar + Sessions.summary persistence the
/// old summary system used, so the public surface (sidebar, web facade, the
/// growth pass's getRecap cb) is unchanged. The generator is the Journal
/// maintenance pass (journal_maintenance leaf), which also produces the
/// per-character memory cards in the same LLM call.
class RecapControls {
  RecapControls(this._s);

  final SendSpine _s;

  SessionStore get _sessions => _s.sessions;

  /// Manually set the recap text.
  void setSummary(String text) {
    _sessions.rememberRecapEdit(text);
    final id = _s.session.currentSessionId;
    if (id != null) {
      unawaited(_s.graph.journalStore.persistRecap(id, text));
    }
    _s.saveChat();
    _s.notify();
  }

  /// Pause or resume the automatic Journal maintenance pass.
  void setSummaryPaused(bool paused) {
    _sessions.summaryPaused = paused;
    _s.notify();
  }

  /// Force an immediate Journal maintenance pass (cards + recap), bypassing
  /// the interval. Backs the sidebar/web "Regenerate" button (name kept for
  /// the existing public surface).
  Future<void> forceSummaryUpdate() async {
    if (_sessions.isSummaryGenerating) return;
    await _sessions.window.awaitHistoryHydrated();
    await _s.graph.journalMaintenance.runMaintenancePass(force: true);
  }
}
