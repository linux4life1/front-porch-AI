// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Shared presentational widgets for the Story Setup wizard steps — one warm
/// honey accent throughout (the old page used a different rainbow color per
/// section) and AppColors everywhere so light mode actually works.

class SetupSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;

  const SetupSectionHeader(this.title, this.icon, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.porchHoneyOf(context), size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

/// Selectable chip for multi-select option sets (genres, moods).
class SetupChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SetupChip(
    this.label, {
    super.key,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchHoneyOf(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.16)
              : AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? accent
                : AppColors.borderOf(context).withValues(alpha: 0.6),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? accent : AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Radio-style chip for single-select options (POV, pace, dialogue, style).
class SetupRadioChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? subtitle;

  const SetupRadioChip(
    this.label, {
    super.key,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchHoneyOf(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? accent
                : AppColors.borderOf(context).withValues(alpha: 0.6),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: selected
                      ? accent
                      : AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? AppColors.textPrimary(context)
                        : AppColors.textSecondary(context),
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Radio-style tile for single-select options that need a description line
/// (prose length, maturity, prompt style).
class SetupRadioTile extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const SetupRadioTile(
    this.label,
    this.description, {
    super.key,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchHoneyOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.1)
                : AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? accent
                  : AppColors.borderOf(context).withValues(alpha: 0.5),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? accent : AppColors.iconSecondary(context),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: selected
                            ? AppColors.textPrimary(context)
                            : AppColors.textSecondary(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card-style switch row (chat history integration, persona).
class SetupToggleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SetupToggleTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchHoneyOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? accent.withValues(alpha: 0.5)
              : AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? accent : AppColors.iconSecondary(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, activeThumbColor: accent, onChanged: onChanged),
        ],
      ),
    );
  }
}
