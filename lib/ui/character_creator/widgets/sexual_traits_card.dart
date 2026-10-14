// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/chip_select_row.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_hint_field.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Terracotta-edged "Sexual Traits" card shown only when NSFW is enabled. Restored
/// from the pre-refactor automated config step: experience, dominance, kinks
/// (+ custom), and outfit vibe.
class SexualTraitsCard extends StatelessWidget {
  final CreatorState state;

  /// Accepted for API symmetry with the other automated cards, but this card is
  /// intrinsically nsfw (NSFW) and ignores the mode accent for its theming.
  final Color accent;

  const SexualTraitsCard({
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
    final nsfw = StudioColors.terraOf(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: nsfw.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department, color: nsfw, size: 18),
              const SizedBox(width: 8),
              Text(
                'Sexual Traits',
                style: TextStyle(
                  color: nsfw,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'All optional',
                style: TextStyle(
                  color: StudioColors.mutedOf(context),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleSelectChipRow(
            label: 'Experience',
            value: state.experience,
            options: CreatorOptions.experienceOptions,
            accent: nsfw,
            onChanged: (v) => _set(() => state.experience = v),
            isNsfw: true,
          ),
          SingleSelectChipRow(
            label: 'Dominance',
            value: state.dominance,
            options: CreatorOptions.dominanceOptions,
            accent: nsfw,
            onChanged: (v) => _set(() => state.dominance = v),
            isNsfw: true,
          ),
          MultiSelectChipRow(
            label: 'Kinks',
            selected: state.selectedKinks,
            options: CreatorOptions.kinkOptions,
            accent: nsfw,
            onChanged: (v) => _set(() => state.selectedKinks = v),
            isNsfw: true,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_fire_department, size: 12, color: nsfw),
                    const SizedBox(width: 4),
                    Text(
                      'Custom Kinks',
                      style: TextStyle(
                        color: nsfw,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                CreatorHintField(
                  state: state,
                  controller: state.customKinksController,
                  hint: 'e.g. foot worship, roleplay, praise kink...',
                ),
              ],
            ),
          ),
          SingleSelectChipRow(
            label: 'Outfit Vibe',
            value: state.outfitVibe,
            options: CreatorOptions.outfitVibes,
            accent: nsfw,
            onChanged: (v) => _set(() => state.outfitVibe = v),
            isNsfw: true,
          ),
        ],
      ),
    );
  }
}
