// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One word under TimeStrip, above TodayLine.
// With you | Away | At work. At work is derived from the clock; on group
// cards the user can also set Away / Back by hand ([onToggle]).

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

enum PresenceWhere { withYou, away, atWork }

/// The glance. [where] is computed by the spec, not picked in chat.
class PresenceWord extends StatelessWidget {
  final PresenceWhere where;

  /// False on group cards — the word sits in the header, not under a strip.
  final bool padTop;

  /// Group cards: tap to set Away (from With you) or bring back (from
  /// Away). Null shows the plain word. At work is never toggled.
  final VoidCallback? onToggle;

  const PresenceWord({
    super.key,
    required this.where,
    this.padTop = true,
    this.onToggle,
  });

  String get label => switch (where) {
    PresenceWhere.withYou => 'With you',
    PresenceWhere.away => 'Away',
    PresenceWhere.atWork => 'At work',
  };

  /// Compact cards dim when they are not in this scene.
  bool get dimCard => where != PresenceWhere.withYou;

  @override
  Widget build(BuildContext context) {
    final onScene = where == PresenceWhere.withYou;
    final color = onScene
        ? AppColors.porchAmberOf(context)
        : AppColors.textSecondary(context);
    final word = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
    final toggle = where == PresenceWhere.atWork ? null : onToggle;
    return Padding(
      padding: EdgeInsets.only(top: padTop ? 6 : 0),
      child: toggle == null
          ? word
          : Tooltip(
              message: onScene ? 'Mark as away' : 'Bring back',
              child: _ToggleWord(
                word: word,
                icon: onScene ? Icons.logout : Icons.login,
                color: color,
                onTap: toggle,
              ),
            ),
    );
  }
}

/// The tappable word, with an exit / enter icon so it reads as a switch.
class _ToggleWord extends StatelessWidget {
  final Widget word;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ToggleWord({
    required this.word,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('presence-toggle'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: word),
          const SizedBox(width: 2),
          Icon(icon, size: 12, color: color),
        ],
      ),
    );
  }
}
