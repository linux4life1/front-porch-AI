// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One word under TimeStrip, above TodayLine.
// With you | Away | At work. At work is derived. Never a yes/no switch.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

enum PresenceWhere { withYou, away, atWork }

/// The glance. [where] is computed by the spec, not picked in chat.
class PresenceWord extends StatelessWidget {
  final PresenceWhere where;

  /// False on group cards — the word sits in the header, not under a strip.
  final bool padTop;

  const PresenceWord({
    super.key,
    required this.where,
    this.padTop = true,
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
    return Padding(
      padding: EdgeInsets.only(top: padTop ? 6 : 0),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: onScene
              ? AppColors.porchAmberOf(context)
              : AppColors.textSecondary(context),
        ),
      ),
    );
  }
}
