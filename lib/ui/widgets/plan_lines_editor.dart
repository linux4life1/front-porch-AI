// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Author can add or delete the character's plan lines. Hidden when the
// planner feature is off. Not a temperament switch.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/widgets/chip_list_editor.dart';

/// Sheet list of the character's plan sentences. Same density as Ambitions.
/// Cap is 4 so this cannot grow into a todo. [enabled] default off.
class PlanLinesEditor extends StatelessWidget {
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  const PlanLinesEditor({
    super.key,
    required this.values,
    required this.onChanged,
    this.enabled = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return ChipListEditor(
      label: 'Plan lines',
      helper:
          'They write the day from who they are. You only add or delete '
          'the line. Not a to-do.',
      hintText: 'e.g. finish the log before the tide',
      maxItems: 4,
      maxChars: 80,
      values: values,
      onChanged: onChanged,
    );
  }
}
