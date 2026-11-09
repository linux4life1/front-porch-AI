// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'section_header.dart';
import 'slider_setting.dart';

/// Settings → Generation: Advanced engine options (Model transport for
/// evaluations and Display Output typewriter streaming buffer).
class GenerationAdvancedSection extends StatefulWidget {
  const GenerationAdvancedSection({
    super.key,
    required this.storage,
    required this.accent,
  });

  final StorageService storage;
  final Color accent;

  @override
  State<GenerationAdvancedSection> createState() =>
      _GenerationAdvancedSectionState();
}

class _GenerationAdvancedSectionState extends State<GenerationAdvancedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final storage = widget.storage;
    final accent = widget.accent;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.hairlineOf(context, 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.hairlineOf(context, 0.12),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color: AppColors.textSecondary(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Advanced Engine Options',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _expanded ? 'Hide' : 'Show',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Model transport ────────────────────────────────────
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
                  const SizedBox(height: 4),
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
                  const SizedBox(height: 20),

                  // ── Display Output ─────────────────────────────────────
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
                    SliderSetting(
                      label: 'Target Display Speed (t/s)',
                      value: storage.uiSettings.targetDisplayTps,
                      min: 5.0,
                      max: 60.0,
                      onChanged: (val) =>
                          storage.uiSettings.setTargetDisplayTps(val),
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
            ),
          ],
        ],
      ),
    );
  }
}
