// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/prompt_engineering_tab/member_avatar.dart';

/// One member's author's-note editor (note text + 1-10 strength) on the
/// Group Settings Prompt Engineering tab.
class GroupCharacterNoteEditor extends StatelessWidget {
  final CharacterCard character;
  final Color accent;
  final StyledTextController controller;
  final int strength;
  final ValueChanged<String> onNoteChanged;
  final ValueChanged<int> onStrengthChanged;

  const GroupCharacterNoteEditor({
    super.key,
    required this.character,
    required this.accent,
    required this.controller,
    required this.strength,
    required this.onNoteChanged,
    required this.onStrengthChanged,
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
            ],
          ),
          const SizedBox(height: 8),

          // Note field
          AppTextField(
            controller: controller,
            maxLines: 3,
            minLines: 1,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText: "Author's note for ${c.name} (when they speak)...",
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
                borderSide: BorderSide(
                  color: AppColors.emotionAccentOf(context),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
            onChanged: onNoteChanged,
          ),
          const SizedBox(height: 8),

          // Compact strength slider (1-10)
          Row(
            children: [
              Text(
                'Strength',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                    activeTrackColor: accent,
                    inactiveTrackColor: AppColors.borderOf(context),
                    thumbColor: accent,
                  ),
                  child: Slider(
                    value: strength.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: (val) => onStrengthChanged(val.round()),
                  ),
                ),
              ),
              SizedBox(
                width: 22,
                child: Text(
                  '$strength',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
