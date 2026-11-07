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

/// A pill naming where the generation values came from. [strong] fills it
/// (a saved preset); otherwise it is outlined.
class GenPresetBadge extends StatelessWidget {
  const GenPresetBadge(this.label, {super.key, this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? accent : null,
        border: Border.all(
          color: strong ? accent : AppColors.textTertiary(context),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: strong
              ? AppColors.onAccentOf(context)
              : AppColors.textPrimary(context),
        ),
      ),
    );
  }
}
