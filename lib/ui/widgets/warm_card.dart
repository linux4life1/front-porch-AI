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

/// A non-collapsing warm-porch card — the flat-card twin of the sidebar's
/// `PorchAccordion`. The sidebar overhaul introduced one card look (fill +
/// 12px radius + near-invisible hairline border, no shadow) but only for the
/// collapsible accordion; this is the same container for plain cards, so
/// screens like the home info panels stop hand-rolling `Card`/`Container`
/// decorations with mismatched radii and hardcoded colors.
class WarmCard extends StatelessWidget {
  const WarmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.accent,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// When set, tints the hairline border (matching the accordion's expanded
  /// state). Pass an `AppColors.*Of(context)` so it resolves for light/dark.
  final Color? accent;

  /// Optional tap handler (wraps the card in an [InkWell] with matching radius).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decorated = Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent?.withValues(alpha: 0.25) ??
              AppColors.borderOf(context).withValues(alpha: 0.15),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return decorated;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: decorated,
    );
  }
}
