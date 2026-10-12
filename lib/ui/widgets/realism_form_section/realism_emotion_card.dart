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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/synced_text_field.dart';

const _intensityOptions = ['mild', 'moderate', 'strong'];

/// Starting emotion text and intensity picker.
class RealismEmotionCard extends StatelessWidget {
  const RealismEmotionCard({
    super.key,
    required this.emotion,
    required this.onEmotionChanged,
    required this.emotionIntensity,
    required this.onEmotionIntensityChanged,
    required this.labelStyle,
  });

  final String emotion;
  final ValueChanged<String> onEmotionChanged;
  final String emotionIntensity;
  final ValueChanged<String> onEmotionIntensityChanged;
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
          // Emotion text field
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Emotion', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  // See the Day Number field: the controller must be
                  // owned, or mid-word edits jump to the end of the text.
                  child: SyncedTextField(
                    value: emotion,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                    ),
                    onChanged: onEmotionChanged,
                    decoration: InputDecoration(
                      hintText: 'e.g. curious, guarded, amused',
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary(
                          context,
                        ).withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Intensity selector
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Intensity', style: labelStyle),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: DropdownButton<String>(
                    value: emotionIntensity,
                    isExpanded: true,
                    dropdownColor: AppColors.surfaceContainerOf(context),
                    underline: const SizedBox(),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                    ),
                    items: _intensityOptions
                        .map(
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text(i[0].toUpperCase() + i.substring(1)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onEmotionIntensityChanged(v);
                    },
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
