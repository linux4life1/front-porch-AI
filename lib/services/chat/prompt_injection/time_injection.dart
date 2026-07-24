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

import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

/// Scene-time fragment for the words-only state block
/// (docs/design/prompt-state-injection.md §3). One line; clock digits and
/// dates are normal fiction, unlike meters (design: story-calendar.md §7).
/// The year appears only when the story isn't set in the current real-world
/// year. State stays in TimeService.
class TimeInjection {
  final TimeService timeService;

  /// Optional one-shot real-absence note (living-time-features.md §2).
  /// Null (the default, and whenever the opt-in is off or nothing is
  /// pending) appends nothing — the fragment stays byte-identical to the
  /// pre-absence block. State/gating live in ChatService; this leaf only
  /// renders words.
  final String? Function()? getAbsenceNote;

  TimeInjection({required this.timeService, this.getAbsenceNote});

  String buildTimeInjection() {
    final clock = timeService.clock;
    final line =
        'It is ${StoryClock.clockPhrase(clock)} on '
        '${timeService.displayDate} '
        '(day ${timeService.dayCount} of the story).';
    final note = getAbsenceNote?.call();
    return (note == null || note.isEmpty) ? line : '$line\n$note';
  }
}
