// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/draw_things_samplers.dart';

import 'studio_commit_field.dart';

/// Sampler label Draw Things already uses. The name includes the scheduler.
String studioDrawThingsLabel(int value) {
  for (final row in kDrawThingsSamplers) {
    if (row.value == value) return row.label;
  }
  return 'Draw Things';
}

/// Advanced knobs. Draw Things is one sampler list. Other backends are
/// steps, CFG, sampler, and scheduler.
class StudioStoveKnobs extends StatelessWidget {
  const StudioStoveKnobs({
    super.key,
    required this.drawThings,
    required this.drawThingsSampler,
    required this.onDrawThingsSampler,
    required this.steps,
    required this.cfg,
    required this.sampler,
    required this.scheduler,
    required this.onSteps,
    required this.onCfg,
    required this.onSampler,
    required this.onScheduler,
  });

  final bool drawThings;
  final int drawThingsSampler;
  final ValueChanged<int>? onDrawThingsSampler;
  final int steps;
  final double cfg;
  final String sampler;
  final String scheduler;
  final ValueChanged<String> onSteps;
  final ValueChanged<String> onCfg;
  final ValueChanged<String> onSampler;
  final ValueChanged<String> onScheduler;

  @override
  Widget build(BuildContext context) {
    if (drawThings) {
      return DropdownButton<int>(
        value: drawThingsSampler,
        isExpanded: true,
        items: [
          for (final row in kDrawThingsSamplers)
            DropdownMenuItem(value: row.value, child: Text(row.label)),
        ],
        onChanged: (value) {
          if (value != null) onDrawThingsSampler?.call(value);
        },
      );
    }
    return Column(
      children: [
        StudioCommitField(
          key: ValueKey('steps-$steps'),
          value: '$steps',
          label: 'Steps',
          onSubmit: onSteps,
        ),
        StudioCommitField(
          key: ValueKey('cfg-$cfg'),
          value: '$cfg',
          label: 'CFG',
          onSubmit: onCfg,
        ),
        StudioCommitField(
          key: ValueKey('sampler-$sampler'),
          value: sampler,
          label: 'Sampler',
          onSubmit: onSampler,
        ),
        StudioCommitField(
          key: ValueKey('scheduler-$scheduler'),
          value: scheduler,
          label: 'Scheduler',
          onSubmit: onScheduler,
        ),
      ],
    );
  }
}
