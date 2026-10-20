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

import 'dart:io';
import 'package:flutter/material.dart';
import 'portrait_image_cache.dart';

/// Generates consistent, distinct colors for personas based on their ID.
/// Used for personas without avatars to provide visual distinction.
class PersonaColors {
  // Palette of distinct, vibrant colors
  static const List<Color> _palette = [
    Color(0xFF3B82F6), // Blue
    Color(0xFF64748B), // Slate
    Color(0xFF0EA5E9), // Sky Blue
    Color(0xFFEF4444), // Red
    Color(0xFFF59E0B), // Amber
    Color(0xFF10B981), // Green
    Color(0xFF06B6D4), // Cyan
    Color(0xFF2563EB), // Royal Blue
    Color(0xFFF97316), // Orange
    Color(0xFF84CC16), // Lime
    Color(0xFF14B8A6), // Teal
    Color(0xFF059669), // Emerald
  ];

  /// Get a consistent color for a given persona ID
  static Color getColorForPersona(String personaId) {
    // Use hash of ID to deterministically select a color
    final hash = personaId.hashCode.abs();
    return _palette[hash % _palette.length];
  }

  /// Get a CircleAvatar for a persona with color-coding when no avatar exists
  static Widget buildPersonaAvatar({
    required String? avatarPath,
    required String personaId,
    required double radius,
    IconData icon = Icons.person,
    double? iconSize,
  }) {
    if (avatarPath != null) {
      return CircleAvatar(
        radius: radius,
        // The persona page shows radius 44: past 64 px, decode at 256.
        backgroundImage: portraitAvatarImage(
          File(avatarPath),
          width: radius <= 32
              ? kPortraitAvatarDecodeWidth
              : kPortraitMontageDecodeWidth,
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: getColorForPersona(personaId),
      child: Icon(icon, size: iconSize ?? radius * 1.125, color: Colors.white),
    );
  }
}
