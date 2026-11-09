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

import 'package:front_porch_ai/services/prompt_slots.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Settings → General → Default Prompts & Instructions.
///
/// Option A layout: 3 stacked card wells hosting the 1:1 Fallback System
/// Prompt, Group Chat System Prompt, and Global Prompt Additions.
class PromptsSection extends StatelessWidget {
  const PromptsSection({super.key, required this.systemPromptController});

  final TextEditingController systemPromptController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Default Prompts & Instructions'),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
              height: 1.45,
            ),
            children: const [
              TextSpan(
                text:
                    'Base instructions for chats without their own prompt. Both fields support ',
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _MacroChip('{{char}}'),
              ),
              TextSpan(text: ' and '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _MacroChip('{{user}}'),
              ),
              TextSpan(text: ' macros.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PromptSlotCard(
          slot: PromptSlot.oneToOne,
          controller: systemPromptController,
          title: 'Fallback system prompt',
          fieldLabel: 'Fallback system prompt',
          helper:
              'Used in one-to-one chats whose character card has no system '
              'prompt of its own. Group chats use the Group system prompt '
              'further down instead.',
        ),
        const SizedBox(height: 16),
        const GroupSystemPromptField(),
        const SizedBox(height: 16),
        const GlobalPromptAdditions(),
      ],
    );
  }
}

class _MacroChip extends StatelessWidget {
  const _MacroChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          color: AppColors.porchAmberOf(context),
        ),
      ),
    );
  }
}
