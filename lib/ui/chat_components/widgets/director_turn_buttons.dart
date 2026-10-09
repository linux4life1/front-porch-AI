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

/// The group input row's turn buttons: auto-chat Play/Pause (Director Mode
/// only) and Next Character.
///
/// The input row is right-aligned behind an expanding text field, so removing
/// a button slides everything to its left one slot right. Next Character
/// therefore keeps its slot while auto-chat runs, greyed out, so Pause lands
/// exactly where Play was and Impersonate never slides under it.
///
/// The caller passes the accent colours so they stay on the input row's
/// palette.
class DirectorTurnButtons extends StatelessWidget {
  const DirectorTurnButtons({
    super.key,
    required this.showAutoPlay,
    required this.autoPlayActive,
    required this.nextTooltip,
    required this.onToggleAutoPlay,
    required this.onNextCharacter,
    required this.playColor,
    required this.pauseColor,
    required this.nextColor,
  });

  /// Director Mode is on, so the auto-chat toggle is shown.
  final bool showAutoPlay;
  final bool autoPlayActive;
  final String nextTooltip;
  final VoidCallback onToggleAutoPlay;
  final VoidCallback onNextCharacter;
  final Color playColor;
  final Color pauseColor;
  final Color nextColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showAutoPlay)
          Tooltip(
            message: autoPlayActive ? 'Pause auto-chat' : 'Start auto-chat',
            child: IconButton(
              icon: Icon(
                autoPlayActive
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: autoPlayActive ? pauseColor : playColor,
              ),
              onPressed: onToggleAutoPlay,
            ),
          ),
        Tooltip(
          message: autoPlayActive
              ? 'Auto-chat picks who speaks next'
              : nextTooltip,
          child: IconButton(
            icon: Icon(
              Icons.group,
              color: autoPlayActive
                  ? AppColors.iconSecondary(context)
                  : nextColor,
            ),
            onPressed: autoPlayActive ? null : onNextCharacter,
          ),
        ),
      ],
    );
  }
}
