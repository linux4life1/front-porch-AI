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
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Shared layout constants for the warm-porch chat sidebar so every card,
/// panel, and inset well agrees on geometry (the old sidebar had per-section
/// ad-hoc radii/paddings — this is the single source).
class SidebarTokens {
  SidebarTokens._();

  /// Accordion / card corner radius.
  static const double cardRadius = 12;

  /// Inset well (settings flyouts, sub-panels) corner radius.
  static const double wellRadius = 8;

  /// Vertical gap between accordion groups.
  static const double sectionGap = 12;

  /// Horizontal body padding inside an accordion.
  static const EdgeInsets bodyPadding = EdgeInsets.fromLTRB(12, 0, 12, 12);

  /// Padding inside inset wells.
  static const EdgeInsets wellPadding = EdgeInsets.all(10);
}

/// The one sub-section header used INSIDE accordion bodies (Objectives,
/// Chaos Mode, Memory, Lorebook, …) — icon + 12px semibold label + optional
/// trailing control. Replaces the per-section ad-hoc header rows.
class SidebarSubHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final Widget? trailing;

  const SidebarSubHeader({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: accent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Per-character color palette for group chats (avatars, roster rings,
/// member accents). Moved from chat_page's private static so sidebar widgets
/// can share it.
Color groupCharacterColor(int index) {
  const colors = [
    Color(0xFF8B5CF6), // Purple
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFFEF4444), // Red
    Color(0xFF3B82F6), // Blue
    Color(0xFFEC4899), // Pink
    Color(0xFF14B8A6), // Teal
    Color(0xFFF97316), // Orange
  ];
  return colors[index % colors.length];
}
