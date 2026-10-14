// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Section heading label with an optional red required asterisk. Restored from
/// the pre-refactor creator step's `_inputLabel`.
class CreatorInputLabel extends StatelessWidget {
  final String text;
  final bool required;

  const CreatorInputLabel(this.text, {super.key, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            color: StudioColors.inkOf(context),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (required)
          Text(' *', style: TextStyle(color: StudioColors.badOf(context))),
      ],
    );
  }
}
