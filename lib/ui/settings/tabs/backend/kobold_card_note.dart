// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';

/// A tinted note on the Local model card: a context size's verdict, or a
/// warning. A warning ([warn]) has an outline and the warning sign; anything
/// else a round mark.
class KoboldCardNote extends StatelessWidget {
  const KoboldCardNote({
    super.key,
    required this.tint,
    required this.child,
    this.warn = false,
  });

  final Color tint;
  final Widget child;
  final bool warn;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: warn ? 0.14 : 0.12),
      borderRadius: BorderRadius.circular(10),
      border: warn ? Border.all(color: tint.withValues(alpha: 0.5)) : null,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: warn
              ? Icon(Icons.warning_rounded, color: tint, size: 18)
              : KeMark(tint, round: true, size: 12),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    ),
  );
}
