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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Prominent deliberate "Generate Image" control + progress/status (per spec).
/// Disabled until prompt looks sane. Clear messages, no hidden auto-gen.
class GenerationPanel extends StatelessWidget {
  final VoidCallback? onGenerate;
  final bool isGenerating;
  final bool isCrafting;
  final String error;
  final bool promptIsSane;

  const GenerationPanel({
    super.key,
    required this.onGenerate,
    required this.isGenerating,
    required this.isCrafting,
    required this.error,
    required this.promptIsSane,
  });

  @override
  Widget build(BuildContext context) {
    if (isCrafting) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.resolve(
                    context,
                    AppColors.formMasterAccent,
                    AppColors.formMasterAccent,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Crafting prompt...',
                style: TextStyle(
                  color: AppColors.resolve(
                    context,
                    AppColors.formMasterAccent,
                    AppColors.formMasterAccent,
                  ),
                  fontSize: 13,
                ),
              ),
              Text(
                'Using AI to refine visuals',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isGenerating) {
      // Live progress from ImageGenService: A1111/ComfyUI stream in-progress
      // preview frames (the image forms in place), Draw Things reports step
      // percent, remote APIs stay indeterminate.
      return Consumer<ImageGenService>(
        builder: (context, igs, _) {
          final preview = igs.genPreview;
          final progress = igs.genProgress;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (preview != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: Image.memory(
                          preview,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: 220,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: AppColors.surfaceContainerOf(context),
                        color: AppColors.formMasterAccent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    progress != null
                        ? 'Painting… ${(progress * 100).round()}%'
                        : 'Generating image...',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'This may take 10-30 seconds',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (error.isNotEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.resolve(
            context,
            AppColors.resolve(
              context,
              AppColors.logError,
              AppColors.lightBorder,
            ),
            AppColors.resolve(
              context,
              AppColors.logError,
              AppColors.lightBorder,
            ),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: AppColors.resolve(
                context,
                AppColors.logError,
                AppColors.logError,
              ),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error,
                style: TextStyle(
                  color: AppColors.resolve(
                    context,
                    AppColors.logError,
                    AppColors.logError,
                  ),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Idle / ready state with prominent deliberate button
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ElevatedButton.icon(
          onPressed: (promptIsSane && onGenerate != null) ? onGenerate : null,
          icon: const Icon(Icons.play_arrow, size: 20),
          label: const Text('Generate Image'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.resolve(
              context,
              AppColors.formMasterAccent,
              AppColors.formMasterAccent,
            ),
            foregroundColor: AppColors.textPrimary(context),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
