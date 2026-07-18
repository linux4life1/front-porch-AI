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

import 'package:front_porch_ai/services/image/edit_profile.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The **Draw Things** edit-setup strip under the Generation Settings on the Edit
/// tab: makes clear the edit knobs are edit-only, offers a one-tap reset to the
/// field-tested recipe, and warns (without forcing) when the sampler/CFG stray
/// into the "no image" band Qwen-Image-Edit tends to return a blank for.
///
/// ComfyUI has its own panel ([ComfyEditPanel]); other backends show neither.
class EditRecipeStrip extends StatelessWidget {
  final bool busy;

  /// Reset the persisted edit knobs AND the Edit view's local strength slider,
  /// so "Use recommended" is honest end-to-end (the strip can't see that state).
  final VoidCallback onUseRecommended;

  const EditRecipeStrip({
    super.key,
    required this.busy,
    required this.onUseRecommended,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
      builder: (context, st, _) {
        final offRecipe =
            st.editSampler != kEditRecommendedSamplerInt ||
            st.editCfgScale > 5.0;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: offRecipe
                  ? AppColors.logWarn
                  : AppColors.borderOf(context),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    offRecipe ? Icons.warning_amber_rounded : Icons.tune,
                    size: 15,
                    color: offRecipe
                        ? AppColors.logWarn
                        : AppColors.iconSecondary(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'These settings are just for edits — Create keeps its own.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : onUseRecommended,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Use recommended',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.formMasterAccent,
                      ),
                    ),
                  ),
                ],
              ),
              if (offRecipe) ...[
                const SizedBox(height: 6),
                Text(
                  'Heads up: Qwen-Image-Edit usually needs the UniPC sampler and '
                  'a moderate CFG (~3.5). Other samplers or a high CFG can return '
                  'no image at all.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
