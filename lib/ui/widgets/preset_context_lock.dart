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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A control that sets chat's context, greyed out and closed to taps while
/// the chosen preset sets the context ([koboldPresetOwnsContext]), with the
/// reason under it in the words every place uses ([kPresetOwnsContext]).
/// Said on the page, not in a tooltip, as the phone does.
class PresetContextLock extends StatelessWidget {
  const PresetContextLock({
    super.key,
    required this.locked,
    required this.child,
  });

  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The same tree either way, so the control keeps its state.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        IgnorePointer(
          ignoring: locked,
          child: Opacity(opacity: locked ? 0.4 : 1, child: child),
        ),
        if (locked) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                size: 14,
                color: AppColors.porchAmberOf(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  kPresetOwnsContext,
                  key: const ValueKey('preset-owns-context'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
