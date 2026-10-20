// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Shared helpers for the Group Settings tab files (extracted from the old
/// 4,251-line group_settings_dialog.dart god file — these were byte-identical
/// private copies in two or more tabs).

/// Section header row (icon + colored bold label). Was _buildSectionHeader,
/// duplicated in the General and Lorebook & Worlds tabs.
class GroupSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const GroupSectionHeader(this.title, this.icon, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

/// Simple accent palette for per-char avatars (subset of Prompt tab palette).
/// Was _charColors/_charAccentColor, duplicated in the Realism and Needs tabs.
const List<Color> kGroupCharColors = LegendColors.groupMembers;

Color groupCharAccentColor(int index) =>
    kGroupCharColors[index % kGroupCharColors.length];

/// Persists one per-character key into the group's defaultMemberRealismState
/// JSON blob. Was _persistMemberVerificationPref, byte-identical in the
/// Realism and Needs tabs.
void persistGroupMemberPref(
  ChatService chatService,
  String id,
  String key,
  dynamic value,
) {
  try {
    final group = chatService.activeGroup;
    if (group != null) {
      final map =
          group.defaultMemberRealismState.isNotEmpty &&
              group.defaultMemberRealismState != '{}'
          ? (jsonDecode(group.defaultMemberRealismState)
                    as Map<String, dynamic>? ??
                {})
          : <String, dynamic>{};
      final perChar = (map['perChar'] as Map<String, dynamic>? ?? {})
          .cast<String, dynamic>();
      final current = (perChar[id] as Map<String, dynamic>? ?? {})
          .cast<String, dynamic>();
      current[key] = value;
      perChar[id] = current;
      map['perChar'] = perChar;
      group.defaultMemberRealismState = jsonEncode(map);
    }
  } catch (_) {
    // Non-fatal
  }
}
