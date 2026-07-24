// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/dynamic_macros_toggle.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Blue-bordered "Auto-generate World Lore" card: a master switch, lore depth
/// selector (Light/Standard/Deep), and optional focus-area filter chips.
/// Restored from the pre-refactor automated config step.
class LorebookGenerationCard extends StatelessWidget {
  final CreatorState state;
  final Color accent;

  const LorebookGenerationCard({
    super.key,
    required this.state,
    required this.accent,
  });

  void _save() {
    state.saveState();
    state.notify();
  }

  String _depthCount(String depth) => depth == 'Light'
      ? '3-4'
      : depth == 'Deep'
      ? '10-15'
      : '5-8';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Auto-generate World Lore',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                value: state.generateLorebook,
                activeTrackColor: accent,
                onChanged: (val) {
                  state.generateLorebook = val;
                  _save();
                },
              ),
            ],
          ),
          if (state.generateLorebook) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Depth:',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message:
                      'Controls how many consecutive generation steps the Lore '
                      'Engine processes. Deep = more expansive lore structure '
                      'but longer wait time.',
                  child: Icon(
                    Icons.info_outline,
                    size: 14,
                    color: AppColors.textTertiary(context),
                  ),
                ),
                const SizedBox(width: 8),
                ...CreatorState.loreDepths.map((depth) {
                  final isSelected = state.loreDepth == depth;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        '$depth (${_depthCount(depth)})',
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: isSelected,
                      onSelected: (_) {
                        state.loreDepth = depth;
                        _save();
                      },
                      selectedColor: accent,
                      backgroundColor: AppColors.surfaceContainerOf(context),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? AppColors.resolve(
                                context,
                                Colors.white,
                                Colors.black87,
                              )
                            : AppColors.textSecondary(context),
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? accent
                            : AppColors.borderOf(context),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Focus areas (optional):',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CreatorState.loreCategoryOptions.map((cat) {
                final isSelected = state.selectedLoreCategories.contains(cat);
                return FilterChip(
                  label: Text(cat, style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      state.selectedLoreCategories.add(cat);
                    } else {
                      state.selectedLoreCategories.remove(cat);
                    }
                    _save();
                  },
                  selectedColor: accent.withValues(alpha: 0.3),
                  backgroundColor: AppColors.surfaceContainerOf(context),
                  checkmarkColor: accent,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? accent
                        : AppColors.textTertiary(context),
                  ),
                  side: BorderSide(
                    color: isSelected ? accent : AppColors.borderOf(context),
                  ),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
          DynamicMacrosToggle(
            value: state.includeDynamicMacros,
            accentColor: accent,
            onChanged: (val) {
              state.includeDynamicMacros = val;
              _save();
            },
          ),
        ],
      ),
    );
  }
}
