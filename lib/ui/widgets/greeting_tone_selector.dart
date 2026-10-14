import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/creator_palette.dart';

class GreetingToneSelector extends StatelessWidget {
  const GreetingToneSelector({
    super.key,
    required this.selectedTones,
    required this.greetingCount,
    required this.nsfwEnabled,
    required this.accentColor,
    required this.onChanged,
    this.subtitle,
  });

  final List<String> selectedTones;
  final int greetingCount;
  final bool nsfwEnabled;
  final Color accentColor;
  final ValueChanged<List<String>> onChanged;
  final String? subtitle;

  static const _greetingTones = [
    'Neutral',
    'Romantic',
    'Spicy/NSFW',
    'Flirty/Playful',
    'Wholesome',
    'Slice of Life',
    'Story/Narrative',
    'Adventure',
    'Dark/Mystery',
    'Humorous',
    'Philosophical',
  ];

  @override
  Widget build(BuildContext context) {
    final p = CreatorPalette.maybeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subtitle ??
              (greetingCount == 0
                  ? 'Tone for the first message.'
                  : 'Select up to ${greetingCount + 1} \u2014 one per greeting.'),
          style: TextStyle(
            color:
                context.creatorPalette?.muted ??
                AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _greetingTones
              .where((tone) => tone != 'Spicy/NSFW' || nsfwEnabled)
              .map((tone) {
                final isSelected = selectedTones.contains(tone);
                final maxTones = greetingCount + 1;
                final atLimit = selectedTones.length >= maxTones && !isSelected;
                return FilterChip(
                  label: Text(tone),
                  selected: isSelected,
                  onSelected: (selected) {
                    final updated = List<String>.from(selectedTones);
                    if (selected) {
                      if (atLimit) {
                        updated.remove(updated.last);
                      }
                      updated.add(tone);
                    } else if (updated.length > 1) {
                      updated.remove(tone);
                    }
                    onChanged(updated);
                  },
                  // Inside the AI Character Creator a selected chip is
                  // solid amber.
                  selectedColor:
                      p?.chipSelectedFill ??
                      accentColor.withValues(alpha: 0.15),
                  backgroundColor:
                      p?.raise ?? AppColors.surfaceContainerOf(context),
                  checkmarkColor: p?.chipSelectedInk ?? accentColor,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? p?.chipSelectedInk ?? accentColor
                        : p?.ink ?? AppColors.textSecondary(context),
                    fontSize: 13,
                  ),
                  side: p != null
                      ? BorderSide.none
                      : BorderSide(
                          color: isSelected
                              ? accentColor
                              : AppColors.borderOf(context),
                        ),
                );
              })
              .toList(),
        ),
      ],
    );
  }
}
