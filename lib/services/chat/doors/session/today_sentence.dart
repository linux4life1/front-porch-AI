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

import 'package:flutter/foundation.dart';

/// The session-scoped today line (Planner V2). Day-clear is on the clock
/// advance, never in the getter. A mixin so a test harness can carry the
/// same behaviour the chat's [TodaySentence] does.
mixin TodayLine on ChangeNotifier {
  String? _todaySentence;

  /// The objective row the today line is held as, if any.
  String? todayObjectiveId;

  /// The text that row was written with (planner resolve compares it).
  String? todayObjectiveText;

  /// Called with the dropped line when the user abandons it.
  void Function(String? held)? onTodayAbandoned;

  String? get todaySentence => _todaySentence;

  void setTodaySentence(String? value) {
    final next = value?.trim();
    _todaySentence = (next == null || next.isEmpty) ? null : next;
    notifyListeners();
  }

  /// User X or empty [today:] tag. Setter stays a plain clear.
  void abandonToday() {
    final held = todaySentence;
    setTodaySentence(null);
    onTodayAbandoned?.call(held);
  }

  String? get todayLine => todaySentence;

  /// Drop the RAM hold. Does not touch the DB row.
  void clearTodayPointer() {
    _todaySentence = null;
    todayObjectiveId = null;
    todayObjectiveText = null;
    notifyListeners();
  }
}

/// The open chat's today line. The session store owns one; the chat
/// service forwards its notifies synchronously, as the mixin it replaces
/// notified the service itself.
class TodaySentence extends ChangeNotifier with TodayLine {}
