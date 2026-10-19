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

/// The prompt-reading bar: a solid fill for tokens the backend confirmed and
/// a lighter fill ahead of it for the estimate, so a guess never reads as
/// fact. Tweened so the 250ms rebuild ticks glide; keyed by [passEpoch] so a
/// new pass rebuilds at its start instead of sweeping backwards.
class PromptProgressBar extends StatelessWidget {
  const PromptProgressBar({
    super.key,
    required this.confirmed,
    required this.estimated,
    required this.passEpoch,
    required this.color,
  });

  final double confirmed;
  final double estimated;
  final int passEpoch;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(passEpoch),
      tween: Tween<double>(end: estimated),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: AppColors.borderOf(context).withValues(alpha: 0.08),
            ),
            _fill(animated, color.withValues(alpha: 0.35)),
            _fill(confirmed, color),
          ],
        ),
      ),
    );
  }

  Widget _fill(double value, Color fill) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: FractionallySizedBox(
      widthFactor: value.clamp(0.0, 1.0),
      heightFactor: 1,
      child: ColoredBox(color: fill),
    ),
  );
}
