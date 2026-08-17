// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life switch for Planner. Default off. Not Plans / Wings it.
// Hard deps Joe named: Passage of Time, Objectives, the Journal.
// This row reports them. It does not invent the wiring.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/settings/widgets/feature_row.dart';

/// Settings row. [value] default false. [satisfied] is the three real flags.
class PlannerFeatureRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool timeOn;
  final bool objectivesOn;
  final bool journalOn;

  const PlannerFeatureRow({
    super.key,
    this.value = false,
    required this.onChanged,
    this.timeOn = false,
    this.objectivesOn = false,
    this.journalOn = false,
  });

  @override
  Widget build(BuildContext context) {
    return FeatureRow(
      icon: Icons.event_note_outlined,
      label: 'Planner',
      need: FeatureNeed.needs,
      dependsOn: 'Passage of Time, Objectives, and the Journal',
      satisfied: timeOn && objectivesOn && journalOn,
      blurb:
          'They plan from personality; you only add or delete the line. '
          'The character will later remember if it got done (needs time, '
          'objectives, journal).',
      value: value,
      onChanged: onChanged,
    );
  }
}
