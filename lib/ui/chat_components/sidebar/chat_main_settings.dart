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

/// The "Main Settings" outlined popup Chat and Waifu Coder both sit under
/// the portrait. Callers pass their own items so Waifu Coder can keep
/// model / temp / UI and omit Edit Character / realism.
class ChatMainSettingsButton extends StatelessWidget {
  const ChatMainSettingsButton({
    super.key,
    required this.onSelected,
    required this.items,
    this.label = 'Main Settings',
  });

  final ValueChanged<String> onSelected;
  final List<PopupMenuEntry<String>> items;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: PopupMenuButton<String>(
          color: AppColors.surfaceContainerOf(context),
          elevation: 8,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary(context),
            side: BorderSide(
              color: AppColors.borderOf(context).withValues(alpha: 0.4),
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: AppColors.borderOf(context).withValues(alpha: 0.3),
            ),
          ),
          offset: const Offset(0, 8),
          onSelected: onSelected,
          itemBuilder: (context) => items,
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
