// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life switch for Planner. Default off. Not Plans / Wings it.
// Hard deps Joe named: Passage of Time, Objectives, the Journal.
// This row reports the cross-subgroup ones (Passage of Time and the Journal).

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/settings/widgets/feature_row.dart';

/// Settings row. [value] default false. [satisfied] is the three real flags.
class PlannerFeatureRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool timeOn;
  final bool objectivesOn;
  final bool journalOn;
  final VoidCallback? onDependencyTap;
  final ExpandSignal? expandDetailsSignal;
  final bool highlighted;

  const PlannerFeatureRow({
    super.key,
    this.value = false,
    required this.onChanged,
    this.timeOn = false,
    this.objectivesOn = false,
    this.journalOn = false,
    this.onDependencyTap,
    this.expandDetailsSignal,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return FeatureRow(
      icon: Icons.event_note_outlined,
      label: 'Planner',
      subtitle:
          'Characters plan ahead from personality and recall what got done.',
      need: FeatureNeed.needs,
      dependsOn: 'Passage of Time and the Journal',
      satisfied: timeOn && objectivesOn && journalOn,
      showDependencyBadge: true,
      blurb:
          'They plan from personality; you only add or delete the line. '
          'The character will later remember if it got done (needs time, '
          'objectives, journal).',
      value: value,
      onChanged: onChanged,
      onDependencyTap: onDependencyTap,
      expandDetailsSignal: expandDetailsSignal,
      highlighted: highlighted,
    );
  }
}
