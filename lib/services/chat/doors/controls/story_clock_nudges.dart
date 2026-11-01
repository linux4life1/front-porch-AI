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
import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_deps.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';

/// The story clock's manual controls: the sidebar chevrons and the
/// calendar dialog. Each runs only while the clock does ([clockRunning],
/// Porch Life's Passage of Time read live), writes the slot clock, mints
/// the day's crumbs, syncs birthdays, saves and notifies.
class StoryClockNudges {
  StoryClockNudges(this._d, {required this.clockRunning});

  final ControlsDeps _d;

  /// Porch Life Passage of Time, read live (the controls door's gate).
  final bool Function() clockRunning;

  RealismGraph get _g => _d.graph();
  TimeService get _timeService => _g.time;

  /// Called by the sidebar chevron buttons. delta = +1 (forward) or -1 (back).
  /// Thin delegation to TimeService (core logic + cb-driven patch); the
  /// save, notify and running-clock guard stay here.
  Future<void> nudgeTimePeriod(int delta) async {
    if (!clockRunning()) return;
    final before = _timeService.clock;
    _g.clockWriter.pendingNudgeBefore = before;
    await _timeService.nudgeTimePeriod(delta);
    _g.clockWriter.writeSlotClock(
      _g.clockReader.visibleTipMessage(),
      kind: SlotClockWrite.nudge,
    );
    // Day-ate journal rides TimeService.onStoryDayChanged.
    await _g.episodeCrumbs.maybeMint(before, _timeService.clock);
    unawaited(_g.birthdays.ensure());
    await _d.saveChat();
    _d.notify();
  }

  /// Calendar dialog: set the story's current date & time directly.
  /// Same guard/save/notify shape as the nudge (it IS a precise nudge).
  Future<void> setStoryClock(DateTime clock) async {
    if (!clockRunning()) return;
    final before = _timeService.clock;
    _g.clockWriter.pendingNudgeBefore = before;
    await _timeService.setClockDirect(clock);
    _g.clockWriter.writeSlotClock(
      _g.clockReader.visibleTipMessage(),
      kind: SlotClockWrite.nudge,
    );
    // Day-ate journal rides TimeService.onStoryDayChanged.
    await _g.episodeCrumbs.maybeMint(before, _timeService.clock);
    unawaited(_g.birthdays.ensure());
    await _d.saveChat();
    _d.notify();
  }

  /// Calendar dialog: re-anchor "story begins on…" — the whole timeline
  /// slides together (Day N is preserved, every date re-derives).
  Future<void> setStoryStartDate(DateTime date) async {
    if (!clockRunning()) return;
    final oldStart = _timeService.startDate;
    _timeService.setStartDate(date);
    final delta = _timeService.startDate.difference(oldStart);
    shiftMessageClockStamps(_d.session.messages, delta);
    await _shiftPersistedSessionClockStamps(delta);
    _g.clockReader.applyTipClock();
    unawaited(_g.birthdays.ensure());
    await _d.saveChat();
    _d.notify();
  }

  Future<void> _shiftPersistedSessionClockStamps(Duration delta) async {
    final sid = _d.session.currentSessionId;
    if (sid == null || delta == Duration.zero) return;
    final rows = await _d.db().getMessagesForSession(sid);
    final seen = Set<Map>.identity();
    for (final row in rows) {
      var changed = false;
      Map<String, dynamic>? meta;
      if (row.metadata != null) {
        meta = Map<String, dynamic>.from(
          jsonDecode(row.metadata!) as Map<String, dynamic>,
        );
        if (shiftClockFields(meta, delta, seen)) changed = true;
      }
      List<dynamic>? swipes;
      if (row.swipeMetadata != null) {
        swipes = [
          for (final e in jsonDecode(row.swipeMetadata!) as List<dynamic>)
            e == null
                ? null
                : () {
                    final m = Map<String, dynamic>.from(e as Map);
                    if (shiftClockFields(m, delta, seen)) changed = true;
                    return m;
                  }(),
        ];
      }
      if (!changed) continue;
      await _d.db().updateMessage(
        MessagesCompanion(
          id: drift.Value(row.id),
          metadata: drift.Value(meta == null ? null : jsonEncode(meta)),
          swipeMetadata: drift.Value(
            swipes == null ? null : jsonEncode(swipes),
          ),
        ),
      );
    }
  }
}
