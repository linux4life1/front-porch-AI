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

import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class DeskModeBar extends StatelessWidget {
  const DeskModeBar({
    super.key,
    required this.mode,
    required this.onChanged,
    this.enabled = true,
  });

  final DeskMode mode;
  final ValueChanged<DeskMode> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final m in DeskMode.values)
                ChoiceChip(
                  key: Key('desk-mode-${m.name}'),
                  label: Text(m.name[0].toUpperCase() + m.name.substring(1)),
                  selected: mode == m,
                  onSelected: !enabled || mode == m
                      ? null
                      : (_) => onChanged(m),
                  selectedColor: amber.withValues(alpha: 0.3),
                ),
            ],
          ),
          if (mode == DeskMode.yolo) ...[
            const SizedBox(height: 6),
            Text(
              kDeskYoloWarning,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
