import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class DescriptionDetailChipRow extends StatelessWidget {
  const DescriptionDetailChipRow({
    super.key,
    this.options = _defaultOptions,
    this.subtitle,
    this.accentColor,
    required this.selectedDetail,
    required this.onChanged,
  });

  final List<String> options;
  final String? subtitle;
  final Color? accentColor;
  final String selectedDetail;
  final ValueChanged<String> onChanged;

  static const _defaultOptions = [
    'Brief',
    'Standard',
    'Detailed',
    'Comprehensive',
  ];

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Colors.blueAccent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subtitle != null) ...[
          Text(
            subtitle!,
            style: TextStyle(color: AppColors.textTertiary(context), fontSize: 11),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((label) {
            final isSelected = selectedDetail == label;
            return ChoiceChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) => onChanged(label),
              selectedColor: accent,
              backgroundColor: AppColors.surfaceContainerOf(context),
              labelStyle: TextStyle(
                color: isSelected
                    ? AppColors.resolve(context, Colors.white, Colors.black87)
                    : AppColors.textSecondary(context),
                fontSize: 13,
              ),
              side: BorderSide(
                color: isSelected ? accent : AppColors.borderOf(context),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
