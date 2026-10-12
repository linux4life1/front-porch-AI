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
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Previous / next month arrows around the shown month's name.
class CalendarMonthNav extends StatelessWidget {
  /// First of the shown month (UTC).
  final DateTime visibleMonth;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const CalendarMonthNav({
    super.key,
    required this.visibleMonth,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.chevron_left,
            size: 18,
            color: AppColors.iconSecondary(context),
          ),
          onPressed: onPrevious,
        ),
        Expanded(
          child: Text(
            '${StoryClock.monthName(visibleMonth)} ${visibleMonth.year}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.iconSecondary(context),
          ),
          onPressed: onNext,
        ),
      ],
    );
  }
}
