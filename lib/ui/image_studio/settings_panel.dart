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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'generation_options_tab.dart';

/// Collapsible "Generation Settings" panel for the Image Studio.
///
/// Wraps the shared [GenerationOptionsTab] (backend / model / size / steps /
/// CFG / sampler / scheduler / seed / LoRA picker + the connection-status card)
/// in an [ExpansionTile] so the default studio view stays focused on the
/// creative flow. Expanded by default when image generation is not yet
/// configured, so the connection status and backend selector are immediately
/// visible.
class StudioSettingsPanel extends StatelessWidget {
  final bool initiallyExpanded;

  /// Forwarded to [GenerationOptionsTab]: when true the per-generation knobs
  /// (Steps / CFG / DT Sampler / Shift / SeedMode) are edit-scoped so an edit
  /// never clobbers the Create/txt2img settings. Used by the Edit tab.
  final bool editScoped;

  const StudioSettingsPanel({
    super.key,
    this.initiallyExpanded = false,
    this.editScoped = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Strip the default ExpansionTile divider lines so it reads as a card.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(Icons.tune, color: AppColors.iconSecondary(context)),
          title: Text(
            'Generation Settings',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            'Backend, model, size, steps, sampler, scheduler, LoRA…',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
            ),
          ),
          iconColor: AppColors.iconSecondary(context),
          collapsedIconColor: AppColors.iconSecondary(context),
          children: [
            GenerationOptionsTab(
              showEnableToggle: false,
              showStyleControls: false,
              editScoped: editScoped,
            ),
          ],
        ),
      ),
    );
  }
}
