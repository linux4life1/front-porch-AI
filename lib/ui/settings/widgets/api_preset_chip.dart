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

/// Quick-connect preset chip for the remote-API config (LM Studio / OpenRouter
/// / Nano-GPT). Pure display; the parent supplies [active] and the [onPressed]
/// action that swaps the API URL + refetches models. Warm-porch amber for the
/// active state (was Colors.indigo / Color(0xFF2D3748)).
class ApiPresetChip extends StatelessWidget {
  const ApiPresetChip({
    super.key,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: active
              ? AppColors.textPrimary(context)
              : AppColors.textSecondary(context),
        ),
      ),
      backgroundColor: active
          ? accent.withValues(alpha: 0.22)
          : AppColors.surfaceContainerOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: active ? accent : AppColors.borderOf(context)),
      ),
      onPressed: onPressed,
    );
  }
}
