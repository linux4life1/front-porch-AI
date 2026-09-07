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
// along with Front Porch AI. If not, see https://www.gnu.org/licenses/.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/waifu/waifu_brand.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Home toolbar mode: Chats, Porch Stories, or Waifu Coder.
enum HomeMode { chats, stories, waifu }

/// Chats / Porch Stories / Waifu Coder switch. Drops the labels when the parent
/// gives it less than the labeled trio's intrinsic width so a resized
/// window never overflows the home toolbar.
///
/// [showStories] / [onShowChats] / [onShowStories] stay required so the
/// existing overflow test still compiles. Waifu Coder is additive.
class HomeModeToggle extends StatelessWidget {
  const HomeModeToggle({
    super.key,
    required this.showStories,
    required this.onShowChats,
    required this.onShowStories,
    this.showWaifu = false,
    this.onShowWaifu,
  });

  final bool showStories;
  final VoidCallback onShowChats;
  final VoidCallback onShowStories;
  final bool showWaifu;
  final VoidCallback? onShowWaifu;

  /// Labeled "Chats" + "Porch Stories" + "Waifu Coder" is wide. Drop to
  /// icons before the 651px toolbar overflow case (and the 360px squeeze).
  static const double labeledMinWidth = 720;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showLabels =
            !constraints.hasBoundedWidth ||
            constraints.maxWidth >= labeledMinWidth;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ModeButton(
                label: 'Chats',
                icon: Icons.chat_bubble_outline,
                isActive: !showStories && !showWaifu,
                showLabel: showLabels,
                onTap: onShowChats,
              ),
              _ModeButton(
                label: 'Porch Stories',
                icon: Icons.auto_stories,
                isActive: showStories,
                showLabel: showLabels,
                onTap: onShowStories,
              ),
              _ModeButton(
                label: kWaifuCoderName,
                icon: Icons.code,
                isActive: showWaifu,
                showLabel: showLabels,
                onTap: onShowWaifu ?? () {},
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.showLabel,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 16 : 10,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isActive ? amber.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? Border.all(color: amber.withValues(alpha: 0.45))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? amber : AppColors.iconSecondary(context),
            ),
            if (showLabel) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? AppColors.textPrimary(context)
                      : AppColors.textSecondary(context),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (showLabel) return child;
    return Tooltip(message: label, child: child);
  }
}
