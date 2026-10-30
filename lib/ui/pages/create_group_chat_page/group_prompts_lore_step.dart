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

import 'package:front_porch_ai/ui/theme/theme.dart';

import 'create_group_chat_page.dart';

/// Wizard step: the two optional extras on one page, the group and
/// per-member system prompts, then the group lorebook and Inherit switch.
class GroupPromptsLoreStep extends StatelessWidget {
  const GroupPromptsLoreStep({
    super.key,
    required this.draft,
    required this.actions,
  });

  final GroupWizardDraft draft;
  final GroupWizardActions actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Both are optional. Skip ahead if the cards already say enough.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 16),
        GroupPromptsStep(draft: draft, actions: actions, showNav: false),
        const SizedBox(height: 32),
        Divider(color: AppColors.borderOf(context)),
        const SizedBox(height: 24),
        GroupLoreStep(draft: draft, actions: actions, showNav: false),
        GroupWizardNavButtons(
          draft: draft,
          actions: actions,
          currentStep: GroupWizardSteps.promptsLore,
        ),
      ],
    );
  }
}
