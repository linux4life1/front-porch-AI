// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// A collapsible, accent-bordered section card used by the Guided creator.
/// Restored from the god file's `_guidedSection`.
class CreatorSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  /// The header icon's colour; amber when not given.
  final Color? accentColor;
  final bool initiallyExpanded;

  const CreatorSectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
    this.accentColor,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? StudioColors.amberOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      // Material, not a decorated Container. ExpansionTile builds an internal
      // ListTile for its header, and a ListTile paints its background and ink
      // splashes onto the nearest Material ancestor — so a coloured
      // DecoratedBox sitting between them hides the tap ripple entirely.
      // Flutter 3.44 added a debug assertion for exactly this ("ListTile
      // background color or ink splashes may be invisible"), which is how it
      // was found. Giving the card its own Material keeps the colour, radius
      // and border while letting the header ripple actually render.
      child: Material(
        color: StudioColors.cardOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: StudioColors.lineOf(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          // No divider lines above and below the open tile.
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          iconColor: StudioColors.proseOf(context),
          collapsedIconColor: StudioColors.proseOf(context),
          leading: Icon(icon, color: accent, size: 18),
          title: Text(
            title,
            style: TextStyle(
              color: StudioColors.inkOf(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: StudioColors.mutedOf(context),
              fontSize: 12,
            ),
          ),
          children: children,
        ),
      ),
    );
  }
}
