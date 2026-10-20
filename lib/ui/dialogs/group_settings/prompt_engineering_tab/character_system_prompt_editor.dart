// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/prompt_engineering_tab/member_avatar.dart';

/// One member's group-only system prompt editor on the Group Settings
/// Prompt Engineering tab.
class GroupCharacterSystemPromptEditor extends StatelessWidget {
  final CharacterCard character;
  final Color accent;
  final StyledTextController controller;
  final ValueChanged<String> onPromptChanged;
  final VoidCallback onClear;

  const GroupCharacterSystemPromptEditor({
    super.key,
    required this.character,
    required this.accent,
    required this.controller,
    required this.onPromptChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final c = character;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name
          Row(
            children: [
              GroupPromptMemberAvatar(character: c, accent: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.name,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onClear,
                child: Text('Clear', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          AppTextField(
            controller: controller,
            maxLines: 4,
            minLines: 2,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText: 'Group-only system prompt for ${c.name}...',
              hintStyle: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AccentColors.tealOf(context)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
            onChanged: onPromptChanged,
          ),
        ],
      ),
    );
  }
}
