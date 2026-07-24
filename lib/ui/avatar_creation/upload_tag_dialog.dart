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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

/// Sentinel returned by [showUploadTagDialog] for "gallery look" (no emotion).
const String kUploadTagLook = '__look__';

/// Look-or-emotion chooser for a pack-OFF extra upload in the Portrait &
/// Avatars step: [kUploadTagLook], an EmotionLabels value, or null (cancel).
Future<String?> showUploadTagDialog(BuildContext context, Uint8List bytes) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surfaceOf(ctx),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      bytes,
                      width: 48,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'What is this image?',
                      style: TextStyle(
                        color: AppColors.textPrimary(ctx),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ActionChip(
                avatar: const Icon(
                  Icons.checkroom,
                  size: 15,
                  color: AppColors.formMasterAccent,
                ),
                label: const Text('Gallery look (outfit / scene — no emotion)'),
                labelStyle: TextStyle(
                  color: AppColors.textPrimary(ctx),
                  fontSize: 12,
                ),
                backgroundColor: AppColors.surfaceContainerOf(ctx),
                onPressed: () => Navigator.of(ctx).pop(kUploadTagLook),
              ),
              const SizedBox(height: 12),
              Text(
                'Or tag it as an expression image:',
                style: TextStyle(
                  color: AppColors.textSecondary(ctx),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final emotion in EmotionLabels.all)
                        ActionChip(
                          label: Text(
                            '${EmotionLabels.emoji[emotion] ?? ''} $emotion',
                          ),
                          labelStyle: TextStyle(
                            color: AppColors.textSecondary(ctx),
                            fontSize: 11,
                          ),
                          backgroundColor: AppColors.surfaceContainerOf(ctx),
                          onPressed: () => Navigator.of(ctx).pop(emotion),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondary(ctx)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
