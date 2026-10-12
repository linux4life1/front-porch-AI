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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/group_alternate_greetings_editor.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Dialogue tab of the group editor: First Message + alternate greetings
/// with opening seeds. No Example Dialogue section exists by design
/// (GroupChat has no mes_example).
class EditGroupDialogueTab extends StatelessWidget {
  const EditGroupDialogueTab({
    super.key,
    required this.firstMessageController,
    required this.altGreetings,
    required this.altGreetingSeeds,
    required this.onAltGreetingsChanged,
  });

  final TextEditingController firstMessageController;
  final List<String> altGreetings;
  final List<GreetingRealismSeed?> altGreetingSeeds;
  final void Function(List<String> greetings, List<GreetingRealismSeed?> seeds)
  onAltGreetingsChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.porchAmberOf(context),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Dialogue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.porchAmberOf(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Text(
                  'First Message (optional)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: firstMessageController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: 'The scene opens with...',
                  ),
                ),

                const SizedBox(height: 20),
                GroupAlternateGreetingsEditor(
                  greetings: altGreetings,
                  seeds: altGreetingSeeds,
                  showNeeds: true,
                  onChanged: onAltGreetingsChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
