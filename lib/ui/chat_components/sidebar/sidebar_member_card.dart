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

// The lite-guest banner, split out of sidebar_body.dart to keep that file
// under the 500-line ratchet. (The group's focused member card lived here
// until the group sidebar became the 1:1 leaves for the focused member.)

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'sidebar_tokens.dart';

/// Status-only banner for a focused lite guest. Promote lives on the
/// cast avatar strip — do not add a second control here.
class LiteNpcBanner extends StatelessWidget {
  const LiteNpcBanner({super.key, this.dragHandle});

  /// The reorder grip when this banner sits in the reorderable body.
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: SidebarTokens.sectionGap),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          if (dragHandle != null)
            // Opaque so a grip tap never reaches the banner.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: dragHandle!,
            ),
          const SizedBox(width: 8),
          Icon(
            Icons.visibility_off,
            size: 16,
            color: AppColors.iconSecondary(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Lite NPC — no realism or needs tracking for this guest.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.porchAmberOf(context).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'GUEST',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: AppColors.porchAmberOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
