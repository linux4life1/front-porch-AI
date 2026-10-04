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

import 'package:front_porch_ai/services/services.dart'
    show kKoboldIdleUnloadChoices, koboldIdleUnloadLabel;
import 'package:front_porch_ai/services/storage/storage.dart'
    show BackendSettings;
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// "Free graphics memory when idle", in Advanced Launch Options: off, or how
/// long KoboldCpp may sit with nothing to do before its model is unloaded.
/// Chips like the Prefill Batch Size row above it. Takes effect at once.
class KoboldIdleUnloadRow extends StatelessWidget {
  const KoboldIdleUnloadRow({
    super.key,
    required this.settings,
    required this.accent,
  });

  final BackendSettings settings;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Free graphics memory when idle',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Unloads the model when KoboldCpp has had nothing to do for '
                'this long, so other programs can use the graphics memory. '
                'The first reply after that takes longer to start.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Wrap(
          spacing: 6,
          children: [
            for (final minutes in kKoboldIdleUnloadChoices)
              _chip(context, minutes),
          ],
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, int minutes) {
    final selected = settings.idleUnloadMinutes == minutes;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () => settings.setIdleUnloadMinutes(minutes),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? accent
                : AppColors.textPrimary(context).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? accent : AppColors.borderOf(context),
            ),
          ),
          child: Text(
            koboldIdleUnloadLabel(minutes),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: selected
                  ? AppColors.onChaosAccent
                  : AppColors.textTertiary(context),
            ),
          ),
        ),
      ),
    );
  }
}
