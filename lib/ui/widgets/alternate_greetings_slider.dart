import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AlternateGreetingsSlider extends StatelessWidget {
  const AlternateGreetingsSlider({
    super.key,
    required this.value,
    required this.accentColor,
    required this.onChanged,
    this.formatLabel,
  });

  final int value;
  final Color accentColor;
  final ValueChanged<int> onChanged;

  /// Builds the visible label shown next to the slider (e.g. "1 + 3").
  /// Defaults to [`value`].
  final String Function(int value)? formatLabel;

  @override
  Widget build(BuildContext context) {
    final label = formatLabel != null ? formatLabel!(value) : '$value';
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 5,
            divisions: 5,
            activeColor: accentColor,
            inactiveColor: AppColors.borderOf(context),
            label: label,
            onChanged: (val) => onChanged(val.round()),
          ),
        ),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
