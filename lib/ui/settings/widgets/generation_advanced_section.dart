// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'section_header.dart';
import 'slider_setting.dart';

/// Settings → Generation: Model transport and Display Output engine options,
/// laid out responsively in two side-by-side columns when room permits.
class GenerationAdvancedSection extends StatelessWidget {
  const GenerationAdvancedSection({
    super.key,
    required this.storage,
    required this.accent,
  });

  final StorageService storage;
  final Color accent;

  /// One bordered tile per option group, matching the slider cards.
  Widget _tile(BuildContext context, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.hairlineOf(context, 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.hairlineOf(context, 0.12)),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final transportCol = _tile(
      context,
      Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Model transport'),
        const SizedBox(height: 6),
        Text(
          'How the engine evaluations (Realism, Journal, Growth Rings) '
          'talk to the model.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'Native tool calling',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            const Spacer(),
            Switch(
              value: !storage.realismSettings.preferTextEvals,
              onChanged: (val) =>
                  storage.realismSettings.setPreferTextEvals(!val),
              activeTrackColor: accent,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'When on, Realism, Journal and Growth use native tool calls if '
          'this model supports them — cleaner structured results, and on '
          'the common local templates no slower than the JSON floor. When '
          'off, every eval uses the JSON/XML floor even if the model can '
          'speak tools. Default on.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
      ],
      ),
    );

    final displayCol = _tile(
      context,
      Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Display Output'),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'Smooth Output Buffer',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            const Spacer(),
            Switch(
              value: storage.uiSettings.displayBufferEnabled,
              onChanged: (val) =>
                  storage.uiSettings.setDisplayBufferEnabled(val),
              activeTrackColor: accent,
            ),
          ],
        ),
        if (storage.uiSettings.displayBufferEnabled) ...[
          const SizedBox(height: 6),
          SliderSetting(
            label: 'Target Display Speed (t/s)',
            value: storage.uiSettings.targetDisplayTps,
            min: 5.0,
            max: 60.0,
            onChanged: (val) => storage.uiSettings.setTargetDisplayTps(val),
            divisions: 55,
          ),
          SliderSetting(
            label: 'Buffer Duration (seconds)',
            value: storage.uiSettings.bufferDurationSeconds,
            min: 1.0,
            max: 10.0,
            onChanged: (val) =>
                storage.uiSettings.setBufferDurationSeconds(val),
            divisions: 9,
          ),
        ],
      ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: transportCol),
              const SizedBox(width: 16),
              Expanded(child: displayCol),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            transportCol,
            const SizedBox(height: 16),
            displayCol,
          ],
        );
      },
    );
  }
}
