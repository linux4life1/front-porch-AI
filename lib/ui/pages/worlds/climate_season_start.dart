// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Matches kClimateDanger on the climate editor cards.
const Color _clash = Color(0xFFE0644C); // theme-keep: mockup danger

bool _isLeap(int year) => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

/// Month + day start for one season. Opens the same [showDatePicker]
/// Story begins uses. Year in the picker is which page you are on —
/// only month and day are stored. Leap years included; year length is
/// still Gregorian (not a custom 400-day year).
class SeasonStartRow extends StatelessWidget {
  const SeasonStartRow({
    super.key,
    required this.month,
    required this.day,
    required this.onStart,
    this.clash = false,
  });

  final int month;
  final int day;
  final void Function(int month, int day) onStart;
  final bool clash;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final color = clash
        ? StatusColors.climateDangerOf(context)
        : AppColors.textSecondary(context);
    final cap = daysInMonth365(month);
    final safeDay = day.clamp(1, cap);
    final label = '${kMonthShort[month - 1]} $safeDay';
    return Material(
      color: AppColors.surfaceContainerOf(context),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _pick(context, safeDay),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: clash ? _clash : amber.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 13, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, int safeDay) async {
    var year = DateTime.now().year;
    var initialDay = safeDay;
    if (month == 2 && safeDay == 29) {
      while (!_isLeap(year)) {
        year++;
      }
    } else {
      final last = DateTime(year, month + 1, 0).day;
      initialDay = safeDay.clamp(1, last);
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(year, month, initialDay),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: 'Season starts',
    );
    if (picked == null) return;
    onStart(picked.month, picked.day);
  }
}
