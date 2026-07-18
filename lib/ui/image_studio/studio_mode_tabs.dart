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

/// The Create | Edit switch under the Image Studio header. These are INTENT tabs
/// — "make a new portrait" vs "change this one" — never pipeline names. The
/// single [ImageReferenceRole] router still decides what actually happens.
class StudioModeTabs extends StatelessWidget {
  /// 0 = Create, 1 = Edit.
  final int selected;
  final ValueChanged<int> onChanged;
  final bool enabled;

  const StudioModeTabs({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: _tab(context, 0, 'Create', 'make a new portrait'),
          ),
          const SizedBox(width: 8),
          Expanded(child: _tab(context, 1, 'Edit', 'change this portrait')),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int index, String label, String sub) {
    final active = selected == index;
    final accent = AppColors.formMasterAccent;
    return Material(
      color: active
          ? accent.withValues(alpha: 0.14)
          : AppColors.surfaceContainerOf(context),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: (enabled && !active) ? () => onChanged(index) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: active ? accent : AppColors.borderOf(context),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: active ? accent : AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 11,
                  color: active
                      ? accent.withValues(alpha: 0.85)
                      : AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
