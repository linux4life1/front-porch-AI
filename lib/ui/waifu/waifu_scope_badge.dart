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

/// Compact Plan/Build/Yolo or Jail/Disk chip. Reused on AppBar and mode bar.
class WaifuChromeBadge extends StatelessWidget {
  const WaifuChromeBadge({
    super.key,
    required this.label,
    required this.tooltip,
    this.filled = true,
    this.warn = false,
  });

  final String label;
  final String tooltip;
  final bool filled;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final danger = AppColors.negativeAccentOf(context);
    final accent = warn ? danger : amber;
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: filled ? accent.withValues(alpha: warn ? 0.22 : 0.28) : null,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: accent.withValues(alpha: 0.7)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: warn ? danger : AppColors.textPrimary(context),
          ),
        ),
      ),
    );
  }
}

class WaifuModeBadge extends StatelessWidget {
  const WaifuModeBadge({super.key, required this.mode});

  final WaifuMode mode;

  @override
  Widget build(BuildContext context) {
    return WaifuChromeBadge(
      label: waifuModeLabel(mode),
      tooltip: 'Session mode: ${waifuModeLabel(mode)}',
    );
  }
}

class WaifuScopeBadge extends StatelessWidget {
  const WaifuScopeBadge({super.key, required this.pathMode});

  final WaifuPathMode pathMode;

  @override
  Widget build(BuildContext context) {
    return WaifuChromeBadge(
      label: waifuScopeBadgeLabel(pathMode),
      tooltip: waifuPathModeTitle(pathMode),
      warn: pathMode == WaifuPathMode.wholeDisk,
    );
  }
}
