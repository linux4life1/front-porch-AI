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

/// Plan / Build / Yolo, each chip saying what the mode allows on hover.
/// The wizard and the session sidebar share it so the two never drift.
class WaifuModeChips extends StatelessWidget {
  const WaifuModeChips({
    super.key,
    required this.mode,
    required this.onChanged,
    this.enabled = true,
  });

  final WaifuMode mode;
  final ValueChanged<WaifuMode> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in WaifuMode.values)
          ChoiceChip(
            key: Key('waifu-mode-${m.name}'),
            label: Text(waifuModeLabel(m)),
            tooltip: waifuModeTooltip(m),
            selected: mode == m,
            onSelected: !enabled || mode == m ? null : (_) => onChanged(m),
            selectedColor: amber.withValues(alpha: 0.3),
          ),
      ],
    );
  }
}

/// This folder only / Whole disk.
class WaifuScopeChips extends StatelessWidget {
  const WaifuScopeChips({
    super.key,
    required this.pathMode,
    required this.onChanged,
    this.enabled = true,
  });

  final WaifuPathMode pathMode;
  final ValueChanged<WaifuPathMode>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final pick = onChanged;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final scope in WaifuPathMode.values)
          ChoiceChip(
            key: Key('waifu-path-mode-${scope.name}'),
            label: Text(waifuPathModeTitle(scope)),
            tooltip: waifuPathModeBlurb(scope),
            selected: pathMode == scope,
            onSelected: !enabled || pick == null || pathMode == scope
                ? null
                : (_) => pick(scope),
            selectedColor: amber.withValues(alpha: 0.3),
          ),
      ],
    );
  }
}
