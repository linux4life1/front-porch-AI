// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Amber-bordered "Quick Start" card of archetype preset chips. Tapping a chip
/// auto-fills the concept + personality keywords (and name if empty) from the
/// selected preset. Restored from the pre-refactor automated config step.
class ArchetypePresetCard extends StatelessWidget {
  final CreatorState state;
  final Color accent;

  const ArchetypePresetCard({
    super.key,
    required this.state,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final selectedFg = StudioColors.amberInkOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: accent, size: 18),
              const SizedBox(width: 6),
              Text(
                'Quick Start — Archetype Presets',
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to auto-fill concept & personality',
            style: TextStyle(
              color: StudioColors.mutedOf(context),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CreatorOptions.archetypePresets.entries.map((entry) {
              final isSelected = state.selectedArchetype == entry.key;
              return ChoiceChip(
                label: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected
                        ? selectedFg
                        : StudioColors.proseOf(context),
                  ),
                ),
                avatar: Icon(
                  isSelected ? Icons.check : Icons.auto_awesome,
                  size: 14,
                  color: isSelected ? selectedFg : accent,
                ),
                selected: isSelected,
                selectedColor: accent,
                backgroundColor: StudioColors.raiseOf(context),
                side: BorderSide(
                  color: isSelected ? accent : StudioColors.lineOf(context),
                ),
                checkmarkColor: accent,
                showCheckmark: false,
                onSelected: (_) {
                  if (isSelected) {
                    state.selectedArchetype = '';
                  } else {
                    state.selectedArchetype = entry.key;
                    state.conceptController.text = entry.value['concept'] ?? '';
                    state.keywordsController.text =
                        entry.value['keywords'] ?? '';
                    if (state.nameController.text.isEmpty) {
                      state.nameController.text = entry.key;
                    }
                  }
                  state.saveState();
                  state.notify();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
