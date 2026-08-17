// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Perspective + tense chips for AI Create output settings.
///
/// Two required single-select rows (First/Third, Present/Past). Clicking the
/// selected chip does not clear it — a generation always has a voice, and the
/// default is first-person present. Optional [sexController] is shown when
/// third person is selected so Quick mode can still feed pronouns.
class NarrativeVoiceSelector extends StatelessWidget {
  const NarrativeVoiceSelector({
    super.key,
    required this.perspective,
    required this.tense,
    required this.accentColor,
    required this.onPerspectiveChanged,
    required this.onTenseChanged,
    this.sexController,
    this.onSexChanged,
  });

  /// `'first'` or `'third'`.
  final String perspective;

  /// `'present'` or `'past'`.
  final String tense;
  final Color accentColor;
  final ValueChanged<String> onPerspectiveChanged;
  final ValueChanged<String> onTenseChanged;
  final TextEditingController? sexController;
  final VoidCallback? onSexChanged;

  static const perspectives = [
    ('first', 'First person'),
    ('third', 'Third person'),
  ];
  static const tenses = [('present', 'Present'), ('past', 'Past')];

  @override
  Widget build(BuildContext context) {
    final isThird = perspective == 'third';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chipRow(
          context,
          label: 'Perspective',
          value: perspective,
          options: perspectives,
          onChanged: onPerspectiveChanged,
        ),
        const SizedBox(height: 12),
        _chipRow(
          context,
          label: 'Tense',
          value: tense,
          options: tenses,
          onChanged: onTenseChanged,
        ),
        if (isThird) ...[
          const SizedBox(height: 8),
          Text(
            sexController == null
                ? 'Third person uses the Sex field for he/she/they. Blank Sex defaults to they/them.'
                : 'Third person uses Sex for he/she/they. Leave blank for they/them.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
            ),
          ),
          if (sexController != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: sexController,
              onChanged: (_) => onSexChanged?.call(),
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. Female, Male, they/them',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderOf(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderOf(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.formMasterAccent,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _chipRow(
    BuildContext context, {
    required String label,
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final selected = value == opt.$1;
            return ChoiceChip(
              label: Text(opt.$2),
              selected: selected,
              onSelected: (_) => onChanged(opt.$1),
              selectedColor: accentColor,
              backgroundColor: AppColors.surfaceContainerOf(context),
              labelStyle: TextStyle(
                color: selected
                    ? AppColors.resolve(context, Colors.white, Colors.black87)
                    : AppColors.textSecondary(context),
                fontSize: 13,
              ),
              side: BorderSide(
                color: selected ? accentColor : AppColors.borderOf(context),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
