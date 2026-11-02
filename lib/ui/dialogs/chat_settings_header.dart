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

/// Chat Settings' title row: the Custom badge and reset when this chat has
/// its own values, and close.
class ChatSettingsHeader extends StatelessWidget {
  const ChatSettingsHeader({
    super.key,
    required this.hasOverrides,
    required this.onReset,
  });

  final bool hasOverrides;

  /// Back to the global values for everything.
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Chat Settings',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                if (hasOverrides) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.porchAmberOf(
                        context,
                      ).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.porchAmberOf(
                          context,
                        ).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Custom',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.porchAmberOf(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasOverrides)
                  Tooltip(
                    message: 'Reset to global defaults',
                    child: IconButton(
                      icon: Icon(
                        Icons.restart_alt,
                        color: AppColors.porchAmberOf(context),
                        size: 20,
                      ),
                      onPressed: onReset,
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: AppColors.iconSecondary(context),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
        if (hasOverrides)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'This chat has custom generation settings that override global defaults.',
              style: TextStyle(
                color: AppColors.porchAmberOf(context).withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}
