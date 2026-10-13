// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A rounded size choice. The current size is filled; the others are outlines.
class StudioSizePill extends StatelessWidget {
  const StudioSizePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.tall = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  /// The Remote API stove's 40-pixel pills; the local stoves stay compact.
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formMasterAccent;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: selected ? AppColors.onChaosAccent : accent,
        backgroundColor: selected ? accent : null,
        padding: tall
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: tall ? const Size(0, 40) : Size.zero,
        visualDensity: tall ? VisualDensity.standard : null,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: StadiumBorder(side: BorderSide(color: accent)),
        textStyle: TextStyle(
          fontSize: tall ? 14 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}
