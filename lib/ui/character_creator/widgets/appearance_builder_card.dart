// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/chip_select_row.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Blue-bordered "Character Appearance" card. Restored from the pre-refactor
/// automated config step: race (+ custom), body/hair/skin, notable features,
/// proportion chips, and NSFW-gated chest/butt rows.
class AppearanceBuilderCard extends StatelessWidget {
  final CreatorState state;
  final Color accent;

  const AppearanceBuilderCard({
    super.key,
    required this.state,
    required this.accent,
  });

  void _set(VoidCallback apply) {
    apply();
    state.saveState();
    state.notify();
  }

  @override
  Widget build(BuildContext context) {
    final pink = AppColors.resolve(
      context,
      Colors.pinkAccent,
      const Color(0xFF9D174D),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Character Appearance',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'All optional',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleSelectChipRow(
            label: 'Race / Species',
            value: state.race,
            options: CreatorOptions.raceOptions,
            accent: accent,
            onChanged: (v) => _set(() => state.race = v),
          ),
          _customRaceField(context),
          SingleSelectChipRow(
            label: 'Body Type',
            value: state.bodyType,
            options: CreatorOptions.bodyTypes,
            accent: accent,
            onChanged: (v) => _set(() => state.bodyType = v),
          ),
          SingleSelectChipRow(
            label: 'Hair Length',
            value: state.hairLength,
            options: CreatorOptions.hairLengths,
            accent: accent,
            onChanged: (v) => _set(() => state.hairLength = v),
          ),
          SingleSelectChipRow(
            label: 'Hair Style',
            value: state.hairStyle,
            options: CreatorOptions.hairStyles,
            accent: accent,
            onChanged: (v) => _set(() => state.hairStyle = v),
          ),
          SingleSelectChipRow(
            label: 'Skin Tone',
            value: state.skinTone,
            options: CreatorOptions.skinTones,
            accent: accent,
            onChanged: (v) => _set(() => state.skinTone = v),
          ),
          MultiSelectChipRow(
            label: 'Notable Features',
            selected: state.notableFeatures,
            options: CreatorOptions.notableFeatureOptions,
            accent: accent,
            onChanged: (v) => _set(() => state.notableFeatures = v),
          ),
          Divider(color: AppColors.borderOf(context), height: 16),
          SingleSelectChipRow(
            label: 'Abs / Core',
            value: state.absCore,
            options: CreatorOptions.absCoreOptions,
            accent: accent,
            onChanged: (v) => _set(() => state.absCore = v),
          ),
          SingleSelectChipRow(
            label: 'Thighs',
            value: state.thighs,
            options: CreatorOptions.thighOptions,
            accent: accent,
            onChanged: (v) => _set(() => state.thighs = v),
          ),
          SingleSelectChipRow(
            label: 'Hips',
            value: state.hips,
            options: CreatorOptions.hipOptions,
            accent: accent,
            onChanged: (v) => _set(() => state.hips = v),
          ),
          SingleSelectChipRow(
            label: 'Shoulders',
            value: state.shoulders,
            options: CreatorOptions.shoulderOptions,
            accent: accent,
            onChanged: (v) => _set(() => state.shoulders = v),
          ),
          SingleSelectChipRow(
            label: 'Waist',
            value: state.waist,
            options: CreatorOptions.waistOptions,
            accent: accent,
            onChanged: (v) => _set(() => state.waist = v),
          ),
          if (state.nsfwEnabled) ...[
            Divider(color: pink, height: 24),
            SingleSelectChipRow(
              label: 'Chest Size',
              value: state.chestSize,
              options: CreatorOptions.chestSizes,
              accent: pink,
              onChanged: (v) => _set(() => state.chestSize = v),
              isNsfw: true,
            ),
            SingleSelectChipRow(
              label: 'Butt Size',
              value: state.buttSize,
              options: CreatorOptions.buttSizes,
              accent: pink,
              onChanged: (v) => _set(() => state.buttSize = v),
              isNsfw: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _customRaceField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            'Custom: ',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: state.customRaceController,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. Kitsune, Arachnid, Void-born...',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.borderOf(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.borderOf(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accent),
                ),
              ),
              onChanged: (_) {
                if (state.customRaceController.text.trim().isNotEmpty &&
                    state.race.isNotEmpty) {
                  state.race = '';
                  state.notify();
                }
                state.scheduleSave();
              },
            ),
          ),
        ],
      ),
    );
  }
}
