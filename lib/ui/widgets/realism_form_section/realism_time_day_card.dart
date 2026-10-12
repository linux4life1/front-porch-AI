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
import 'package:flutter/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/synced_text_field.dart';

const _timeOptions = [
  'dawn',
  'morning',
  'late_morning',
  'afternoon',
  'evening',
  'night',
];

/// Time-of-day dropdown and day-number field.
class RealismTimeDayCard extends StatelessWidget {
  const RealismTimeDayCard({
    super.key,
    required this.timeOfDay,
    required this.onTimeOfDayChanged,
    required this.dayCount,
    required this.onDayCountChanged,
    required this.labelStyle,
  });

  final String timeOfDay;
  final ValueChanged<String> onTimeOfDayChanged;
  final int dayCount;
  final ValueChanged<int> onDayCountChanged;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          // Time of Day dropdown
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Time of Day', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: DropdownButton<String>(
                    value: timeOfDay,
                    isExpanded: true,
                    dropdownColor: AppColors.surfaceContainerOf(context),
                    underline: const SizedBox(),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                    ),
                    items: _timeOptions
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(_formatTimeLabel(t)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onTimeOfDayChanged(v);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Day Number
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Day Number', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  // SyncedTextField, not a TextField with an inline
                  // controller: every caller rebuilds this section on
                  // each keystroke, and a controller built in build()
                  // loses the caret (and any IME composition) every
                  // frame.
                  child: SyncedTextField(
                    value: dayCount.toString(),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                    ),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n >= 1) onDayCountChanged(n);
                    },
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTimeLabel(String value) {
  return value
      .split('_')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
