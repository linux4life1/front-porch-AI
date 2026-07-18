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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The "image coming to life" bubble shown at the bottom of the chat while an
/// /image run is live. Watches [ImageGenService] for live progress: A1111 and
/// ComfyUI stream in-progress preview frames (the picture literally forms in
/// place), Draw Things reports sampling steps (moving bar), remote APIs show
/// an indeterminate bar. Before the backend starts (crafting / prompt
/// review), it reads as "getting ready".
class GeneratingImageBubble extends StatelessWidget {
  const GeneratingImageBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ImageGenService>(
      builder: (context, igs, _) {
        final preview = igs.genPreview;
        final progress = igs.genProgress;
        final painting = igs.isGenerating;
        final label = !painting
            ? 'Getting the prompt ready…'
            : progress != null
            ? 'Painting… ${(progress * 100).round()}%'
            : 'Painting…';

        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.formMasterAccent.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (preview != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        // gaplessPlayback keeps the previous frame while the
                        // next decodes, so the image visibly sharpens instead
                        // of flickering.
                        child: Image.memory(
                          preview,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 120,
                      width: 200,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.brush_outlined,
                        size: 32,
                        color: AppColors.iconSecondary(context),
                      ),
                    ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: painting ? progress : null,
                      minHeight: 4,
                      backgroundColor: AppColors.surfaceContainerOf(context),
                      color: AppColors.formMasterAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
