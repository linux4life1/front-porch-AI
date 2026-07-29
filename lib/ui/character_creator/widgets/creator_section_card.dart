// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A collapsible, accent-bordered section card used by the Guided creator.
/// Restored from the god file's `_guidedSection`.
class CreatorSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;
  final Color accentColor;
  final bool initiallyExpanded;

  const CreatorSectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
    this.accentColor = Colors.tealAccent,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      // Material, not a decorated Container. ExpansionTile builds an internal
      // ListTile for its header, and a ListTile paints its background and ink
      // splashes onto the nearest Material ancestor — so a coloured
      // DecoratedBox sitting between them hides the tap ripple entirely.
      // Flutter 3.44 added a debug assertion for exactly this ("ListTile
      // background color or ink splashes may be invisible"), which is how it
      // was found. Giving the card its own Material keeps the identical
      // colour, radius and accent border while letting the header ripple
      // actually render.
      child: Material(
        // Darker than the surfaceContainer chips/fields inside so they read as
        // crisp pills/boxes (surfaceContainer-on-surfaceContainer is invisible
        // in dark mode — borderOf ≈ surfaceContainer).
        color: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: accentColor.withValues(alpha: 0.15)),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            iconColor: accentColor,
            collapsedIconColor: AppColors.textTertiary(context),
            leading: Icon(icon, color: accentColor, size: 18),
            title: Text(
              title,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
            ),
            children: children,
          ),
        ),
      ),
    );
  }
}
