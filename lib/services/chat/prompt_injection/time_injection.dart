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

import 'package:front_porch_ai/services/chat/time_service.dart';

/// Scene-time fragment for the words-only state block
/// (docs/design/prompt-state-injection.md §3). One line; the day count is the
/// one digit deliberately allowed in the composed block (dates are normal
/// fiction, unlike meters). State stays in TimeService.
class TimeInjection {
  final TimeService timeService;

  TimeInjection({required this.timeService});

  String buildTimeInjection() {
    if (timeService.timeOfDay.isEmpty) return '';
    final timeLabel = timeService.timeOfDay.replaceAll('_', ' ');
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final narrativeDayIndex =
        (timeService.startDayOfWeekAnchor - 1 + (timeService.dayCount - 1)) % 7;
    final weekdayName = days[narrativeDayIndex];
    return 'It is $timeLabel on $weekdayName (day ${timeService.dayCount} of '
        'the story).';
  }
}
