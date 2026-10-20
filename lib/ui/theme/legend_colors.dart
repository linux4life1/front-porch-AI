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

import 'app_colors.dart';

/// Identity hues that tell one thing from another: prompt sections, group
/// members, voices. They are data, so every theme keeps them; only the ones
/// used as text get a deeper light tone.
class LegendColors {
  LegendColors._();

  /// Context viewer sections: the stacked bar and its rows. Shared verbatim
  /// with the web ContextBudgetModal.
  static const Map<String, Color> contextSections = {
    'System Prompt': Color(0xFF3B82F6),
    'Lorebook': Color(0xFF8B5CF6),
    'Persona': Color(0xFF06B6D4),
    'Scenario': Color(0xFF10B981),
    'Examples': Color(0xFFF59E0B),
    'Chat History': Color(0xFF6366F1),
    'Post-History': Color(0xFFEF4444),
    'Journal': Color(0xFFF97316),
    'Realism Mode': Color(0xFFEC4899),
    'Memories': Color(0xFF14B8A6),
    'Speaker Card': Color(0xFF7C3AED),
  };

  /// A section the legend does not know.
  static const Color unknownSection = Colors.grey;

  /// Group member avatars in the Realism and Needs tabs.
  static const List<Color> groupMembers = [
    Color(0xFF14B8A6),
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF3B82F6),
  ];

  /// Group member avatars in the Prompt tab, matching the chat sidebar.
  static const List<Color> groupMembersWide = [
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF3B82F6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
  ];

  /// A voice's gender mark in the TTS voice lists.
  static Color voiceFemaleOf(BuildContext context) =>
      AppColors.resolve(context, Colors.pinkAccent, const Color(0xFFC2185B));
  static Color voiceMaleOf(BuildContext context) =>
      AppColors.resolve(context, Colors.cyanAccent, const Color(0xFF155E75));

  /// A feature that works on its own, beside the amber of coupled ones.
  static Color independentOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF9FD49F),
    const Color(0xFF1B5E20),
  );

  /// Image Studio caveats: the group-shot note and expression pack QC.
  static Color caveatOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFFDAA83F),
    const Color(0xFF92400E),
  );
}
