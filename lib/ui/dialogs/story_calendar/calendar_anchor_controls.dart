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

/// "Story begins …" and "Set date & time" buttons, disabled unless
/// [canEdit].
class CalendarAnchorControls extends StatelessWidget {
  final DateTime startDate;
  final bool canEdit;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickCurrentDateTime;

  const CalendarAnchorControls({
    super.key,
    required this.startDate,
    required this.canEdit,
    required this.onPickStartDate,
    required this.onPickCurrentDateTime,
  });

  @override
  Widget build(BuildContext context) {
    final startLabel = StoryClock.formatShortDate(startDate);
    return Row(
      children: [
        Expanded(
          child: TextButton.icon(
            onPressed: canEdit ? onPickStartDate : null,
            icon: Icon(
              Icons.flag_outlined,
              size: 14,
              color: AppColors.porchAmberOf(context),
            ),
            label: Text(
              'Story begins $startLabel',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: canEdit
                    ? AppColors.textSecondary(context)
                    : AppColors.textTertiary(context),
              ),
            ),
          ),
        ),
        Expanded(
          child: TextButton.icon(
            onPressed: canEdit ? onPickCurrentDateTime : null,
            icon: Icon(
              Icons.schedule,
              size: 14,
              color: AppColors.porchAmberOf(context),
            ),
            label: Text(
              'Set date & time',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: canEdit
                    ? AppColors.textSecondary(context)
                    : AppColors.textTertiary(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
