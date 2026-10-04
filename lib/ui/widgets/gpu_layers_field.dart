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

/// How much of the model goes on the graphics card: "Automatic" (KoboldCpp
/// fits it), or a layer count the user sets. Shared by Settings, the Model
/// Settings dialog and the character creator's setup step.
class GpuLayersField extends StatelessWidget {
  const GpuLayersField({
    super.key,
    required this.manual,
    required this.onManualChanged,
    required this.controller,
    this.onLayersChanged,
    this.dense = false,
    this.retiredLayers,
    this.onDismissRetired,
  });

  final bool manual;
  final ValueChanged<bool> onManualChanged;
  final TextEditingController controller;
  final ValueChanged<String>? onLayersChanged;
  final bool dense;

  /// The layer count that was in use before the move to Automatic, while
  /// the user has not yet acknowledged the move. Shows a one-time note.
  final int? retiredLayers;
  final VoidCallback? onDismissRetired;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manual
                        ? 'Graphics memory: set by you'
                        : 'Graphics memory: Automatic',
                    style: TextStyle(
                      fontSize: dense ? 13 : 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    manual
                        ? 'You choose how many layers of the model go on the '
                              'graphics card. Too many and it will not load, '
                              'or will run very slowly.'
                        : 'KoboldCpp works out how much of the model fits on '
                              'your graphics card and puts the rest in system '
                              'memory.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Set layers myself',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
            Switch(
              key: const ValueKey('gpu-layers-manual-switch'),
              value: manual,
              onChanged: onManualChanged,
              activeTrackColor: AppColors.porchAmberOf(context),
            ),
          ],
        ),
        if (!manual && retiredLayers != null) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('gpu-layers-retired-note'),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Before this update GPU layers was set to $retiredLayers. '
                    'KoboldCpp now works out the fit by itself, so that '
                    'number is no longer sent. It is kept: switch on '
                    '“Set layers myself” to use it again.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('gpu-layers-retired-dismiss'),
                  onPressed: onDismissRetired,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.porchAmberOf(context),
                  ),
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
        ],
        if (manual) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 260,
            child: TextField(
              key: const ValueKey('gpu-layers-number'),
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: onLayersChanged,
              style: TextStyle(color: AppColors.textPrimary(context)),
              decoration: InputDecoration(
                labelText: 'GPU layers',
                labelStyle: TextStyle(color: AppColors.textSecondary(context)),
                floatingLabelStyle: TextStyle(
                  color: AppColors.textSecondary(context),
                ),
                helperText: '0 keeps the model off the card',
                helperStyle: TextStyle(color: AppColors.textTertiary(context)),
                isDense: true,
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
