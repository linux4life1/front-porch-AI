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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'acceleration_section.dart';

/// The top of Advanced Launch Options: what a preset already sets, the
/// acceleration backend, flash attention and memory lock.
/// These are what auto mode launches with; a preset is launched as written.
///
/// Returned as a list because the rows sit directly in the caller's Column.
List<Widget> launchEngineRows(
  BuildContext context, {
  required StorageService storage,
  required Color accent,
  required VoidCallback onRocmChanged,
}) {
  return [
    if (storage.backendSettings.presetOwnsContext) ...[
      LaunchOptionsNotice(
        key: const ValueKey('preset-owns-launch-options'),
        text: kPresetOwnsLaunchOptions,
        accent: accent,
      ),
      const SizedBox(height: 12),
    ],
    AccelerationSection(
      hardwareService: Provider.of<HardwareService>(context),
      onRocmChanged: onRocmChanged,
    ),
    const SizedBox(height: 4),
    const SizedBox(height: 12),
    Divider(color: AppColors.borderOf(context), height: 1),
    const SizedBox(height: 12),
    _launchToggle(
      context,
      accent: accent,
      label: 'Flash Attention',
      tooltip:
          'Faster attention math, and less memory. ~20–40% speed boost on RTX/Apple Silicon. AMD (ROCm) follows this switch too: if KoboldCpp stops while answering with it on, the app turns it off and starts again. Gemma 4 on Vulkan always runs without it.',
      value: storage.backendSettings.flashAttentionEnabled,
      recommended: true,
      onChanged: (v) => storage.backendSettings.setFlashAttentionEnabled(v),
    ),
    // Switched off, it still runs with a compressed cache.
    if (!storage.backendSettings.flashAttentionEnabled &&
        storage.backendSettings.kvQuant.needsFlashAttention)
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          kKoboldCompressedTurnsFlashOn,
          key: const ValueKey('flash-attention-compressed-note'),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
        ),
      ),
    _launchToggle(
      context,
      accent: accent,
      label: 'Lock Weights in RAM (mlock)',
      tooltip: Platform.isLinux
          ? 'Prevents paging to disk. Requires root or ulimit ‑l unlimited on Linux — off by default.'
          : 'Prevents OS from paging model weights to disk. Avoids catastrophic slowdown under memory pressure.',
      value: storage.backendSettings.mlockEnabled,
      recommended: !Platform.isLinux,
      onChanged: (v) => storage.backendSettings.setMlockEnabled(v),
    ),
  ];
}

Widget _launchToggle(
  BuildContext context, {
  required Color accent,
  required String label,
  required String tooltip,
  required bool value,
  required ValueChanged<bool> onChanged,
  bool recommended = false,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  if (recommended) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'RECOMMENDED',
                        style: TextStyle(
                          fontSize: 9,
                          color: accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                tooltip,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeTrackColor: accent),
      ],
    ),
  );
}
