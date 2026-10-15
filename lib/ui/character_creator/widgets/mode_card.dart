// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Mode selection card for the character creator (Automated / Guided / Quick),
/// one column of the Mode step's three (docs/design/creator-ui-spec.md, "Mode
/// card"): the icon tile, title, subtitle, description and feature list,
/// stacked. The chosen card takes a 2px [accentColor] border over an 8% wash.
class ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String description;
  final List<String> features;
  final IconData icon;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onTap;

  const ModeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.features,
    required this.icon,
    required this.accentColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final muted = StudioColors.mutedOf(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.08)
                : StudioColors.cardOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? accentColor : StudioColors.lineOf(context),
              width: isSelected ? 2 : 1,
            ),
          ),
          // The sketch's text: no tracking and the browser's line height.
          child: DefaultTextStyle.merge(
            style: const TextStyle(letterSpacing: 0, height: 1.2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accentColor, size: 28),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: StudioColors.inkOf(context),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: StudioColors.proseOf(context),
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, height: 1.5, color: muted),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    // The sketch's "✓", as an icon: not every font has
                    // the glyph.
                    for (final f in features)
                      Row(
                        spacing: 4,
                        children: [
                          Icon(Icons.check, size: 11, color: muted),
                          Flexible(
                            child: Text(
                              f,
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
