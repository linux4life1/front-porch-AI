// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

// Shared section chrome for the greeting seed form: the same cards and
// headers as RealismFormSection.

Widget seedHeader(
  BuildContext context,
  IconData icon,
  String text,
  Color color,
) => Row(
  children: [
    Icon(icon, color: color, size: 18),
    const SizedBox(width: 8),
    Text(
      text,
      style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ],
);

Widget seedCard(BuildContext context, Widget child) => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: AppColors.cardOf(context),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: AppColors.borderOf(context)),
  ),
  child: child,
);

TextStyle seedLabelStyle(BuildContext context) => TextStyle(
  color: AppColors.textSecondary(context),
  fontSize: 12,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.5,
);

Widget seedDropdown(
  BuildContext context, {
  required String label,
  required String? value,
  required List<String> items,
  required String hint,
  required ValueChanged<String?> onChanged,
}) {
  final selected = value != null && items.contains(value) ? value : null;
  final inheritStyle = TextStyle(
    color: AppColors.textTertiary(context).withValues(alpha: 0.6),
    fontSize: 13,
  );
  return seedLabeledField(
    context,
    label: label,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-${selected ?? 'inherit'}'),
        initialValue: selected,
        hint: Text(hint, style: inheritStyle),
        items: [
          DropdownMenuItem<String>(
            value: null,
            child: Text(hint, style: inheritStyle),
          ),
          for (final i in items)
            DropdownMenuItem(value: i, child: Text(i.replaceAll('_', ' '))),
        ],
        onChanged: onChanged,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 10),
        ),
        dropdownColor: AppColors.surfaceContainerOf(context),
        style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
      ),
    ),
  );
}

Widget seedLabeledField(
  BuildContext context, {
  required String label,
  required Widget child,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: seedLabelStyle(context)),
      const SizedBox(height: 8),
      child,
    ],
  );
}

Widget seedBoxedField(BuildContext context, Widget child) {
  return Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerOf(context),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.borderOf(context)),
    ),
    child: child,
  );
}

InputDecoration seedDeco(BuildContext context, String? hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: AppColors.textTertiary(context).withValues(alpha: 0.6),
      fontSize: 13,
    ),
    border: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );
}
