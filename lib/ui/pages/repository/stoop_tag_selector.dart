// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Tag picker for the Stoop upload flow. The card's tags (plus any the creator
/// adds) are shown as toggle chips; the creator chooses up to [max] to publish.
/// When a card carries more than [max] tags this is how they pick which ones
/// appear on the Stoop. The parent owns the [pool]/[selected] lists and applies
/// the cap inside [onToggle]/[onAdd]; this widget is pure presentation.
///
/// Typing is comma-driven: every time the creator types a comma (or presses
/// enter) the text before it becomes a tag pill and bumps the N/[max] counter.
class StoopTagSelector extends StatelessWidget {
  final List<String> pool;
  final List<String> selected;
  final int max;
  final TextEditingController controller;
  final ValueChanged<String> onToggle;

  /// Commit a single finished tag (already split out of any comma list). The
  /// parent dedupes (case-insensitively) and enforces the [max] cap.
  final ValueChanged<String> onAdd;

  /// The upload page's shared input decoration, so the add-tag field matches the
  /// name/summary fields above it.
  final InputDecoration Function(String hint) decorate;

  const StoopTagSelector({
    super.key,
    required this.pool,
    required this.selected,
    required this.max,
    required this.controller,
    required this.onToggle,
    required this.onAdd,
    required this.decorate,
  });

  /// Live comma handling: commit every complete token (everything before the
  /// last comma) and leave the in-progress fragment in the field.
  void _handleChanged(String value) {
    if (!value.contains(',')) return;
    final parts = value.split(',');
    for (var i = 0; i < parts.length - 1; i++) {
      final t = parts[i].trim();
      if (t.isNotEmpty) onAdd(t);
    }
    final remainder = parts.last;
    controller.value = TextEditingValue(
      text: remainder,
      selection: TextSelection.collapsed(offset: remainder.length),
    );
  }

  /// Enter commits whatever's left (also splitting a pasted comma list).
  void _handleSubmitted(String value) {
    for (final part in value.split(',')) {
      final t = part.trim();
      if (t.isNotEmpty) onAdd(t);
    }
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.resolve(context, Colors.tealAccent, Colors.teal);
    final atCap = selected.length >= max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Tags',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${selected.length}/$max',
              style: TextStyle(
                color: atCap ? accent : AppColors.textTertiary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (pool.length > max) ...[
          const SizedBox(height: 4),
          Text(
            'This character has ${pool.length} tags — pick the $max to show on '
            'the Stoop.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (pool.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in pool)
                FilterChip(
                  label: Text(t),
                  selected: selected.contains(t),
                  showCheckmark: false,
                  // At the cap, only already-selected chips stay tappable (to
                  // deselect); unselected ones are disabled so you can't exceed.
                  onSelected: (selected.contains(t) || !atCap)
                      ? (_) => onToggle(t)
                      : null,
                  backgroundColor: AppColors.surfaceContainerOf(context),
                  selectedColor: accent.withValues(alpha: 0.22),
                  labelStyle: TextStyle(
                    color: selected.contains(t)
                        ? AppColors.textPrimary(context)
                        : AppColors.textTertiary(context),
                    fontWeight: selected.contains(t)
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: selected.contains(t)
                        ? accent.withValues(alpha: 0.5)
                        : AppColors.borderOf(context),
                  ),
                ),
            ],
          ),
        if (pool.isNotEmpty) const SizedBox(height: 10),
        TextField(
          controller: controller,
          enabled: !atCap,
          style: TextStyle(color: AppColors.textPrimary(context)),
          decoration: decorate(
            atCap
                ? 'Tag limit reached ($max)'
                : 'Type tags, separated by commas',
          ),
          onChanged: _handleChanged,
          onSubmitted: _handleSubmitted,
        ),
      ],
    );
  }
}
