// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Year + month + day. February never offers 29.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/birthday.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Author a calendar birthday. Empty [iso] is unset. Feb 29 is unselectable.
class BirthdayRow extends StatelessWidget {
  final String iso;
  final ValueChanged<String> onChanged;
  final String helper;
  final DateTime? ageAsOf;

  const BirthdayRow({
    super.key,
    required this.iso,
    required this.onChanged,
    this.helper =
        'Story calendar, not today\'s date. February 29 is not allowed.',
    this.ageAsOf,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = BirthdayMath.parse(iso);
    final asOf = ageAsOf ?? DateTime.now().toUtc();
    final reading = parsed == null ? null : BirthdayMath.read(parsed.iso, asOf);
    final amber = AppColors.porchAmberOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                parsed == null
                    ? 'No birthday set'
                    : '${parsed.monthDay}, ${parsed.year}',
                style: TextStyle(
                  fontSize: 14,
                  color: parsed == null
                      ? AppColors.textTertiary(context)
                      : AppColors.textPrimary(context),
                ),
              ),
            ),
            TextButton(
              onPressed: () => _pick(context),
              child: Text(
                parsed == null ? 'Set' : 'Change',
                style: TextStyle(color: amber),
              ),
            ),
            if (parsed != null)
              TextButton(
                onPressed: () => onChanged(''),
                child: Text(
                  'Clear',
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
              ),
          ],
        ),
        if (reading != null)
          Text(
            'Age ${reading.age} on the story date.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(context),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          helper,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final parsed = BirthdayMath.parse(iso);
    final now = DateTime.now();
    final initial =
        parsed?.asUtc ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(1800, 1, 1),
      lastDate: DateTime(2200, 12, 31),
      selectableDayPredicate: (d) => !(d.month == 2 && d.day == 29),
      helpText: 'Birthday',
    );
    if (picked == null) return;
    if (picked.month == 2 && picked.day == 29) return;
    onChanged(
      BirthdayDate(year: picked.year, month: picked.month, day: picked.day).iso,
    );
  }
}
