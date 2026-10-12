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

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The image crop dialog's bottom bar: Reset, the output-size readout,
/// Cancel, and Crop & Save (with its in-progress spinner).
class CropFooterBar extends StatelessWidget {
  final bool isCropping;

  /// Whether the image has decoded (Reset and Crop & Save need it).
  final bool ready;
  final String sizeReadout;
  final VoidCallback onReset;
  final VoidCallback onCancel;
  final VoidCallback onCropAndSave;

  const CropFooterBar({
    super.key,
    required this.isCropping,
    required this.ready,
    required this.sizeReadout,
    required this.onReset,
    required this.onCancel,
    required this.onCropAndSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: (isCropping || !ready) ? null : onReset,
            icon: Icon(
              Icons.restart_alt,
              size: 16,
              color: AppColors.porchAmberOf(context),
            ),
            label: Text(
              'Reset',
              style: TextStyle(color: AppColors.porchAmberOf(context)),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            sizeReadout,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary(context),
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: isCropping ? null : onCancel,
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: (isCropping || !ready) ? null : onCropAndSave,
            icon: isCropping
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onChaosAccent,
                    ),
                  )
                : const Icon(Icons.crop_sharp, size: 18),
            label: Text(isCropping ? 'Cropping...' : 'Crop & Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.porchAmberOf(context),
              foregroundColor: AppColors.onChaosAccent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
