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
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// ElevenLabs stability / similarity / style sliders. Holds the in-flight
/// drag values itself and saves to [settings] when a drag ends.
class ElevenLabsVoiceSliders extends StatefulWidget {
  const ElevenLabsVoiceSliders({super.key, required this.settings});

  final TtsSettings settings;

  @override
  State<ElevenLabsVoiceSliders> createState() => _ElevenLabsVoiceSlidersState();
}

class _ElevenLabsVoiceSlidersState extends State<ElevenLabsVoiceSliders> {
  double? _dragElevenlabsStability;
  double? _dragElevenlabsSimilarity;
  double? _dragElevenlabsStyle;

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(color: AppColors.borderOf(context)),
        const SizedBox(height: 8),
        Text(
          'Voice Settings',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        // Stability
        Row(
          children: [
            Text(
              'Stability',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              (_dragElevenlabsStability ?? settings.elevenlabsStability)
                  .toStringAsFixed(2),
              style: const TextStyle(
                color: AppColors.formMasterAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: _dragElevenlabsStability ?? settings.elevenlabsStability,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          activeColor: AppColors.formMasterAccent,
          inactiveColor: AppColors.borderOf(context),
          onChanged: (val) => setState(() => _dragElevenlabsStability = val),
          onChangeEnd: (val) {
            _dragElevenlabsStability = null;
            settings.setElevenlabsStability(val);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Expressive',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 9,
                ),
              ),
              Text(
                'Consistent',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Similarity Boost
        Row(
          children: [
            Text(
              'Similarity',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              (_dragElevenlabsSimilarity ?? settings.elevenlabsSimilarity)
                  .toStringAsFixed(2),
              style: const TextStyle(
                color: AppColors.formMasterAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: _dragElevenlabsSimilarity ?? settings.elevenlabsSimilarity,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          activeColor: AppColors.formMasterAccent,
          inactiveColor: AppColors.borderOf(context),
          onChanged: (val) => setState(() => _dragElevenlabsSimilarity = val),
          onChangeEnd: (val) {
            _dragElevenlabsSimilarity = null;
            settings.setElevenlabsSimilarity(val);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Creative',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 9,
                ),
              ),
              Text(
                'Faithful',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Style
        Row(
          children: [
            Text(
              'Style',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              (_dragElevenlabsStyle ?? settings.elevenlabsStyle)
                  .toStringAsFixed(2),
              style: const TextStyle(
                color: AppColors.formMasterAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: _dragElevenlabsStyle ?? settings.elevenlabsStyle,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          activeColor: AppColors.formMasterAccent,
          inactiveColor: AppColors.borderOf(context),
          onChanged: (val) => setState(() => _dragElevenlabsStyle = val),
          onChangeEnd: (val) {
            _dragElevenlabsStyle = null;
            settings.setElevenlabsStyle(val);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtle',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 9,
                ),
              ),
              Text(
                'Expressive',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
