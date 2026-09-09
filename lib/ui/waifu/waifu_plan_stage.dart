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

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/waifu/waifu_plan_panel.dart';

/// Main-stage Plan surface — above the work strip, not sidebar-only.
class WaifuPlanStage extends StatelessWidget {
  const WaifuPlanStage({
    super.key,
    required this.session,
    this.harness,
    this.onChanged,
    this.initialPlan,
  });

  final WaifuSession session;
  final WaifuHarness? harness;
  final VoidCallback? onChanged;
  final WaifuPlan? initialPlan;

  @override
  Widget build(BuildContext context) {
    if (!waifuPlanStageVisible(session)) return const SizedBox.shrink();
    final amber = AppColors.porchAmberOf(context);
    return SizedBox(
      height: 280,
      child: Container(
        key: const Key('waifu-plan-stage'),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: amber.withValues(alpha: 0.45)),
        ),
        child: WaifuPlanPanel(
          session: session,
          harness: harness,
          onChanged: onChanged,
          initialPlan: initialPlan,
        ),
      ),
    );
  }
}
