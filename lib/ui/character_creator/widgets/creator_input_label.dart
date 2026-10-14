// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The spec's label above a field (docs/design/creator-ui-spec.md): 11px /
/// 600, upper-cased, 0.4px tracking, `muted`, with an amber `*` when
/// [required].
class CreatorInputLabel extends StatelessWidget {
  final String text;
  final bool required;

  /// Overrides the `muted` colour (the 18+ rows label in terracotta).
  final Color? color;

  const CreatorInputLabel(
    this.text, {
    super.key,
    this.required = false,
    this.color,
  });

  /// The label style, for labels that sit in their own row layout.
  static TextStyle styleOf(BuildContext context, {Color? color}) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: color ?? StudioColors.mutedOf(context),
  );

  @override
  Widget build(BuildContext context) {
    final style = styleOf(context, color: color);
    return Text.rich(
      TextSpan(
        text: text.toUpperCase(),
        children: [
          if (required)
            TextSpan(
              text: ' *',
              style: style.copyWith(color: StudioColors.amberOf(context)),
            ),
        ],
      ),
      style: style,
    );
  }
}
