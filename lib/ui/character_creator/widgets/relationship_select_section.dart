// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_hint_field.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// "{{user}} Relationship" multi-select chips (NSFW dynamics hidden until the
/// toggle is on) plus a custom relationship field. Restored from the
/// pre-refactor automated config step.
class RelationshipSelectSection extends StatelessWidget {
  final CreatorState state;
  final Color accent;

  const RelationshipSelectSection({
    super.key,
    required this.state,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final selectedFg = StudioColors.amberInkOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select one or more dynamics',
          style: TextStyle(color: StudioColors.mutedOf(context), fontSize: 11),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: CreatorState.relationshipPresets
              .where(
                (rel) =>
                    state.nsfwEnabled ||
                    !CreatorState.nsfwRelationships.contains(rel),
              )
              .map((rel) {
                final isSelected = state.selectedRelationships.contains(rel);
                final isNsfw = CreatorState.nsfwRelationships.contains(rel);
                final relAccent = isNsfw
                    ? StudioColors.terraOf(context)
                    : accent;
                return FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isNsfw) ...[
                        Icon(
                          Icons.local_fire_department,
                          size: 12,
                          color: isSelected
                              ? selectedFg
                              : StudioColors.terraOf(context),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(rel),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      state.selectedRelationships.add(rel);
                    } else {
                      state.selectedRelationships.remove(rel);
                    }
                    state.saveState();
                    state.notify();
                  },
                  selectedColor: relAccent,
                  backgroundColor: StudioColors.raiseOf(context),
                  checkmarkColor: selectedFg,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? selectedFg
                        : StudioColors.proseOf(context),
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? relAccent
                        : StudioColors.lineOf(context),
                  ),
                );
              })
              .toList(),
        ),
        const SizedBox(height: 8),
        CreatorHintField(
          state: state,
          controller: state.relationshipController,
          hint: 'Or type a custom relationship...',
        ),
      ],
    );
  }
}
