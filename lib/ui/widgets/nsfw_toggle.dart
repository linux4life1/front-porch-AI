import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class NsfwToggle extends StatelessWidget {
  const NsfwToggle({
    super.key,
    required this.value,
    required this.accentColor,
    required this.onChanged,
    this.title = 'Enable NSFW Options',
    this.subtitle = 'Unlock intimate character details',
    this.animated = false,
  });

  final bool value;
  final Color accentColor;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final container = AnimatedContainer(
      duration: animated ? const Duration(milliseconds: 180) : Duration.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: value
            ? accentColor.withValues(alpha: 0.08)
            : AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value
              ? accentColor.withValues(alpha: 0.5)
              : AppColors.borderOf(context),
          width: value ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.local_fire_department,
            color: value ? accentColor : AppColors.textTertiary(context),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: value ? accentColor : AppColors.textSecondary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: value
                        ? accentColor.withValues(alpha: 0.6)
                        : AppColors.textTertiary(context),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeTrackColor: accentColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );

    if (animated) {
      return InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(12),
        child: container,
      );
    }

    return container;
  }
}
