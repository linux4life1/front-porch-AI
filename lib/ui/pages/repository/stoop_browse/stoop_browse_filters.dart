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

import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Newest / Top / Downloads sort pill.
class StoopBrowseSortMenu extends StatelessWidget {
  final String sort;
  final ValueChanged<String> onSelected;

  const StoopBrowseSortMenu({
    super.key,
    required this.sort,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const labels = {'newest': 'Newest', 'top': 'Top', 'downloads': 'Downloads'};
    return PopupMenuButton<String>(
      initialValue: sort,
      color: stoopCard2(context),
      onSelected: onSelected,
      itemBuilder: (_) => labels.entries
          .map(
            (e) => PopupMenuItem(
              value: e.key,
              child: Text(
                e.value,
                style: TextStyle(color: stoopCream2(context)),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 7, 8, 7),
        decoration: BoxDecoration(
          color: stoopBg1(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: stoopBorderHi(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labels[sort]!,
              style: TextStyle(color: stoopCream2(context), fontSize: 13),
            ),
            Icon(Icons.arrow_drop_down, color: stoopMute(context), size: 20),
          ],
        ),
      ),
    );
  }
}

/// Hub filter chips (.hub-chip): quiet pills; the active one lights up on the
/// amber gradient with dark ink.
class StoopBrowseTypeChips extends StatelessWidget {
  final String type;
  final ValueChanged<String> onSelected;

  const StoopBrowseTypeChips({
    super.key,
    required this.type,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const types = [
      ('all', 'All'),
      ('solo', 'Singles'),
      ('group', 'Groups'),
      ('world', 'Worlds'),
    ];
    return Wrap(
      spacing: 6,
      children: [
        for (final (value, label) in types)
          _chip(context, label, type == value, () => onSelected(value)),
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    bool on,
    VoidCallback onTap,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: on ? stoopAmberGradient : null,
          color: on ? null : stoopBg1(context),
          borderRadius: BorderRadius.circular(999),
          border: on ? null : Border.all(color: stoopBorderHi(context)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? AppColors.stoopAmberInk : stoopCream2(context),
            fontSize: 13,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
