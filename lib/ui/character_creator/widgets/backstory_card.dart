// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/chip_select_row.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_hint_field.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Blue-bordered "Backstory" card: origin / tone / era chip rows plus a
/// free-form custom backstory notes field. Restored from the pre-refactor
/// automated config step.
class BackstoryCard extends StatelessWidget {
  final CreatorState state;
  final Color accent;

  const BackstoryCard({super.key, required this.state, required this.accent});

  void _set(VoidCallback apply) {
    apply();
    state.saveState();
    state.notify();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_stories, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Backstory',
                style: TextStyle(
                  color: StudioColors.inkOf(context),
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
            label: 'Origin',
            value: state.backstoryOrigin,
            options: CreatorOptions.backstoryOrigins,
            accent: accent,
            onChanged: (v) => _set(() => state.backstoryOrigin = v),
          ),
          SingleSelectChipRow(
            label: 'Tone',
            value: state.backstoryTone,
            options: CreatorOptions.backstoryTones,
            accent: accent,
            onChanged: (v) => _set(() => state.backstoryTone = v),
          ),
          SingleSelectChipRow(
            label: 'Era',
            value: state.backstoryEra,
            options: CreatorOptions.backstoryEras,
            accent: accent,
            onChanged: (v) => _set(() => state.backstoryEra = v),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custom Backstory Notes',
                  style: TextStyle(
                    color: StudioColors.proseOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                CreatorHintField(
                  state: state,
                  controller: state.backstoryNotesController,
                  hint: 'e.g. Was betrayed by their order, seeks revenge...',
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
