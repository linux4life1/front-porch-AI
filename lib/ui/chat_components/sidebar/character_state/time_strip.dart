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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/story_calendar_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'weather_chip.dart';

/// THE one scene-time widget: time-of-day emoji + label + story clock,
/// tappable date (opens the Story Calendar), manual nudge chevrons, and the
/// six period dots.
///
/// Absorbs the old group-only SceneTimeSection and the byte-similar inline
/// copy that lived inside realism_section (1:1) — both modes now render this
/// exact widget inside the Character State accordion. Time is chat-level
/// state (TimeService), identical in 1:1 and group.
class TimeStrip extends StatelessWidget {
  final ChatService chat;

  const TimeStrip({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final time = chat.timeService.timeOfDay;
    final day = chat.timeService.dayCount;
    final canNudge = chat.realismEnabled && !chat.isGenerating;
    final activeDot = AppColors.timeDayAccentOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(timeEmoji(time), style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text(
              '${timeLabel(time)} · ${chat.timeService.displayClock}',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
            const Spacer(),
            if (canNudge)
              GestureDetector(
                onTap: () => chat.nudgeTimePeriod(-1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_left,
                    size: 16,
                    color: AppColors.iconSecondary(context),
                  ),
                ),
              ),
            GestureDetector(
              onTap: () =>
                  StoryCalendarDialog.show(context, chatService: chat),
              child: Text(
                '${chat.timeService.displayShortDate} · Day $day',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary(context),
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.borderOf(context),
                ),
              ),
            ),
            if (canNudge)
              GestureDetector(
                onTap: () => chat.nudgeTimePeriod(1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.iconSecondary(context),
                  ),
                ),
              ),
          ],
        ),
        // Story weather (Living Time §3) — absent entirely when the feature
        // is gated off, so the strip is byte-identical for weather-off users.
        if (chat.currentWeather != null) ...[
          const SizedBox(height: 4),
          WeatherChip(
            sessionSeed: chat.currentSessionId ?? '',
            dayCount: chat.timeService.dayCount,
            date: chat.timeService.clock,
          ),
        ],
        const SizedBox(height: 4),
        // Time period dots
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final period in const [
              'dawn',
              'morning',
              'late_morning',
              'afternoon',
              'evening',
              'night',
            ])
              Column(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: time == period
                          ? activeDot
                          : AppColors.borderOf(context).withValues(alpha: 0.25),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _timeDotLabel(period),
                    style: TextStyle(
                      fontSize: 8,
                      color: time == period
                          ? activeDot
                          : AppColors.textTertiary(context),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  /// Shared emoji/label helpers (also used by the Character State accordion
  /// subtitle).
  static String timeEmoji(String time) {
    switch (time) {
      case 'dawn':
        return '🌅';
      case 'morning':
        return '☀️';
      case 'late_morning':
        return '🌤️';
      case 'afternoon':
        return '☀️';
      case 'evening':
        return '🌇';
      case 'night':
        return '🌙';
      default:
        return '🕐';
    }
  }

  static String timeLabel(String time) {
    switch (time) {
      case 'dawn':
        return 'Dawn';
      case 'morning':
        return 'Morning';
      case 'late_morning':
        return 'Late Morning';
      case 'afternoon':
        return 'Afternoon';
      case 'evening':
        return 'Evening';
      case 'night':
        return 'Night';
      default:
        return time;
    }
  }

  static String _timeDotLabel(String period) {
    switch (period) {
      case 'dawn':
        return 'D';
      case 'morning':
        return 'M';
      case 'late_morning':
        return 'LM';
      case 'afternoon':
        return 'A';
      case 'evening':
        return 'E';
      case 'night':
        return 'N';
      default:
        return '';
    }
  }
}
