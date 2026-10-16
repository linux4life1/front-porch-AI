import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/creator_palette.dart';

class AvatarArtStyleSelector extends StatelessWidget {
  const AvatarArtStyleSelector({
    super.key,
    required this.selectedStyle,
    required this.accentColor,
    required this.onChanged,
  });

  final String? selectedStyle;
  final Color accentColor;
  final ValueChanged<String> onChanged;

  static const _artStyles = [
    'Anime',
    'Realistic',
    'Painterly',
    'Pixel Art',
    'Comic Book',
    'Watercolor',
    'Fantasy Illustration',
  ];

  @override
  Widget build(BuildContext context) {
    // Inside the AI Character Creator a selected chip is solid amber.
    final p = CreatorPalette.maybeOf(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _artStyles.map((style) {
        final isSelected = selectedStyle == style;
        return ChoiceChip(
          label: Text(style),
          selected: isSelected,
          onSelected: (_) => onChanged(style),
          selectedColor:
              p?.chipSelectedFill ?? accentColor.withValues(alpha: 0.15),
          backgroundColor: p?.raise ?? AppColors.surfaceContainerOf(context),
          labelStyle: TextStyle(
            color: isSelected
                ? p?.chipSelectedInk ?? accentColor
                : p?.ink ?? AppColors.textSecondary(context),
            fontSize: 13,
          ),
          side: p != null
              ? BorderSide.none
              : BorderSide(
                  color: isSelected ? accentColor : AppColors.borderOf(context),
                ),
        );
      }).toList(),
    );
  }
}
