// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Author seeds occupation and hours. Not a weekday grid. Not an at-work switch.
// At work is derived in chat (occupation + hours + not-with-user).

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Two short fields next to Plan lines. Identity, not a schedule.
class WorkRow extends StatelessWidget {
  final String occupation;
  final String hours;
  final ValueChanged<String> onOccupationChanged;
  final ValueChanged<String> onHoursChanged;

  const WorkRow({
    super.key,
    required this.occupation,
    required this.hours,
    required this.onOccupationChanged,
    required this.onHoursChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WORK',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'What they do, and when. Not a calendar.',
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _field(
                context,
                label: 'Occupation',
                value: occupation,
                hint: 'e.g. librarian',
                onChanged: onOccupationChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _field(
                context,
                label: 'Hours',
                value: hours,
                hint: 'e.g. 9–5',
                onChanged: onHoursChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(
    BuildContext context, {
    required String label,
    required String value,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    final amber = AppColors.porchAmberOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: value,
          onChanged: onChanged,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary(context),
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary(context),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: amber),
            ),
          ),
        ),
      ],
    );
  }
}
