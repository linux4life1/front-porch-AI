// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/draw_things_samplers.dart';

const List<String> kStudioSamplerChoices = [
  'Euler a',
  'Euler',
  'DPM++ 2M',
  'DPM++ 2M Karras',
  'DPM++ SDE Karras',
  'DPM++ 2M SDE Karras',
  'DDIM',
  'UniPC',
  'LCM',
];

const List<String> kStudioSchedulerChoices = [
  'Automatic',
  'normal',
  'karras',
  'exponential',
  'sgm_uniform',
  'simple',
  'beta',
];

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
    final stepValue = steps.clamp(1, 50).toDouble();
    final cfgValue = cfg.clamp(1.0, 20.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Steps'),
        Slider(
          value: stepValue,
          min: 1,
          max: 50,
          divisions: 49,
          label: '${stepValue.round()}',
          onChanged: (value) => onSteps('${value.round()}'),
        ),
        const Text('CFG'),
        Slider(
          value: cfgValue,
          min: 1,
          max: 20,
          divisions: 38,
          label: cfgValue.toStringAsFixed(1),
          onChanged: (value) => onCfg(value.toStringAsFixed(1)),
        ),
        const Text('Sampler'),
        _choice(sampler, kStudioSamplerChoices, onSampler),
        const Text('Scheduler'),
        _choice(scheduler, kStudioSchedulerChoices, onScheduler),
      ],
    );
  }

  Widget _choice(
    String value,
    List<String> choices,
    ValueChanged<String> onChanged,
  ) {
    final items = [
      if (value.isNotEmpty && !choices.contains(value)) value,
      ...choices,
    ];
    return DropdownButton<String>(
      isExpanded: true,
      value: items.contains(value) ? value : items.first,
      items: [
        for (final name in items)
          DropdownMenuItem(value: name, child: Text(name)),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}
