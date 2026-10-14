// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The single, shared "bubble" used across every character-creation mode
/// (Quick / Guided / Automated). One look, themed per mode by [accent] — so
/// the modes feel like one polished family but are visually distinguishable.
///
/// Light/dark safe: unselected uses surfaceContainer + a real border; selected
/// uses an accent tint + accent border + accent label (which resolve to deep
/// colours in light mode), so it never blinds and always reads.
class CreatorPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final IconData? icon;

  const CreatorPill({
    super.key,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    // The spec's chip: `raise` fill, 13px ink; selected is a solid accent
    // fill with amber-ink text.
    final fg = selected
        ? StudioColors.amberInkOf(context)
        : StudioColors.inkOf(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? accent : StudioColors.raiseOf(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
