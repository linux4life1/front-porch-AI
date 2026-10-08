// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A setting in Advanced Launch Options picked from a few chips, like the
/// Prefill Batch Size row: its name and what it does on the left, the
/// choices on the right, the chosen one filled with [accent].
class LaunchChoiceRow extends StatelessWidget {
  const LaunchChoiceRow({
    super.key,
    required this.title,
    required this.blurb,
    required this.choices,
    required this.chosen,
    required this.label,
    required this.onChoose,
    required this.accent,
  });

  final String title;
  final String blurb;
  final List<int> choices;
  final int chosen;
  final String Function(int choice) label;
  final ValueChanged<int> onChoose;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                blurb,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Wrap(
          spacing: 6,
          children: [for (final c in choices) _chip(context, c)],
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, int choice) {
    final selected = chosen == choice;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () => onChoose(choice),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? accent
                : AppColors.textPrimary(context).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? accent : AppColors.borderOf(context),
            ),
          ),
          child: Text(
            label(choice),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: selected
                  ? AppColors.onChaosAccent
                  : AppColors.textTertiary(context),
            ),
          ),
        ),
      ),
    );
  }
}
