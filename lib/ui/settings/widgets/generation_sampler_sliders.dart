// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/gen_presets/gen_presets.dart';

import 'studio_slider_card.dart';

/// Settings → Generation's sampler sliders:
/// Responsive dual-column studio console grouping Creativity & Probability
/// on the left and Flow & Anti-Repetition on the right.
/// Each slider features constrained ranges, danger boundary highlights,
/// and a graphical default pip on the track.
class GenerationSamplerSliders extends StatelessWidget {
  const GenerationSamplerSliders({
    super.key,
    required this.storage,
    required this.knobs,
    required this.accent,
  });

  final StorageService storage;

  /// Only what this backend's requests carry; a hidden value is kept.
  final Set<SamplerKnob> knobs;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return RecommendedSamplersBuilder(
      storage: storage,
      builder: (context, rec) => _sliders(context, rec),
    );
  }

  Widget _sliders(BuildContext context, RecommendedSamplers? rec) {
    ResetTarget? r(num? Function(SamplerValues v) pick) =>
        resetTargetFor(rec, pick);

    final g = storage.generationSettings;

    // Column 1: Creativity & Probability
    final col1 = <Widget>[
      Text(
        'CREATIVITY & PROBABILITY',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: AppColors.formAccentOf(context),
        ),
      ),
      const SizedBox(height: 8),
      StudioSliderCard(
        label: 'Temperature',
        value: g.temperature,
        min: 0.0,
        max: 2.0,
        defaultVal: 0.70,
        dangerMax: 1.60,
        divisions: 40,
        decimalPlaces: 2,
        reset: r((v) => v.temperature),
        onChanged: (val) => g.setTemperature(val),
        tooltip:
            'Controls randomness. 0.70 is balanced; values above 1.60 risk extreme incoherence.',
      ),
      if (knobs.contains(SamplerKnob.minP)) ...[
        const SizedBox(height: 10),
        StudioSliderCard(
          label: 'Min-P',
          value: g.minP,
          min: 0.0,
          max: 0.25,
          defaultVal: 0.10,
          dangerMax: 0.15,
          divisions: 25,
          decimalPlaces: 2,
          reset: r((v) => v.minP),
          onChanged: (val) => g.setMinP(val),
          tooltip:
              'Probability threshold relative to top token. Above 0.15 heavily starves vocabulary.',
        ),
      ],
      const SizedBox(height: 10),
      StudioSliderCard(
        label: 'Top-P',
        value: g.topP,
        min: 0.50,
        max: 1.00,
        defaultVal: 0.90,
        dangerMin: 0.65,
        divisions: 50,
        decimalPlaces: 2,
        reset: r((v) => v.topP),
        onChanged: (val) => g.setTopP(val),
        tooltip:
            'Nucleus sampling: cumulative probability pool. 0.90 is standard; below 0.65 risks over-pruning.',
      ),
      if (knobs.contains(SamplerKnob.topK)) ...[
        const SizedBox(height: 10),
        StudioSliderCard(
          label: 'Top-K',
          value: g.topK.toDouble(),
          min: 0,
          max: 100,
          defaultVal: 0,
          dangerMax: 80,
          divisions: 100,
          isInteger: true,
          reset: r((v) => v.topK),
          onChanged: (val) => g.setTopK(val.toInt()),
          tooltip: 'Limits candidate pool to K words. 0 = disabled.',
        ),
      ],
      if (knobs.contains(SamplerKnob.dynamicTemp)) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.hairlineOf(context, 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.hairlineOf(context, 0.12),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Dynamic Temperature',
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: g.dynamicTempEnabled,
                    onChanged: (val) => g.setDynamicTempEnabled(val),
                    activeTrackColor: accent,
                  ),
                ],
              ),
              if (g.dynamicTempEnabled) ...[
                const SizedBox(height: 6),
                StudioSliderCard(
                  label: 'Dynatemp Range',
                  value: g.dynamicTempRange,
                  min: 0.0,
                  max: 2.0,
                  defaultVal: 0.70,
                  dangerMax: 1.60,
                  divisions: 40,
                  decimalPlaces: 2,
                  embedded: true,
                  reset: r((v) => v.dynamicTempRange),
                  onChanged: (val) => g.setDynamicTempRange(val),
                  tooltip:
                      'Variance range around base temperature based on entropy.',
                ),
              ],
            ],
          ),
        ),
      ],
    ];

    // Column 2: Flow & Anti-Repetition
    final col2Widgets = <Widget>[];

    if (knobs.contains(SamplerKnob.dry)) {
      col2Widgets.add(
        StudioSliderCard(
          label: 'DRY Strength',
          value: g.dryMultiplier,
          min: 0.0,
          max: 1.60,
          defaultVal: 0.0,
          dangerMax: 1.20,
          divisions: 32,
          decimalPlaces: 2,
          reset: r((v) => v.dryMultiplier),
          onChanged: (val) => g.setDryMultiplier(val),
          tooltip:
              'Don\'t Repeat Yourself: catches repeated n-gram phrases. 0.80 is recommended when active; >1.20 over-penalizes.',
        ),
      );
    }

    if (knobs.contains(SamplerKnob.repeatPenalty)) {
      if (col2Widgets.isNotEmpty) col2Widgets.add(const SizedBox(height: 10));
      col2Widgets.add(
        StudioSliderCard(
          label: 'Repeat Penalty',
          value: g.repeatPenalty,
          min: 1.00,
          max: 1.35,
          defaultVal: 1.10,
          dangerMax: 1.20,
          divisions: 35,
          decimalPlaces: 2,
          reset: r((v) => v.repeatPenalty),
          onChanged: (val) => g.setRepeatPenalty(val),
          tooltip:
              'Token-level penalty. 1.10 is gentle; values above 1.20 cause severe syntax breakdown and synonym hunting.',
        ),
      );
    }

    if (knobs.contains(SamplerKnob.repeatPenaltyTokens)) {
      if (col2Widgets.isNotEmpty) col2Widgets.add(const SizedBox(height: 10));
      col2Widgets.add(
        StudioSliderCard(
          label: 'Repeat Penalty Tokens',
          value: g.repeatPenaltyTokens.toDouble(),
          min: 0,
          max: 2048,
          defaultVal: 1024,
          dangerMin: 128,
          divisions: 256,
          isInteger: true,
          reset: r((v) => v.repeatPenaltyTokens),
          onChanged: (val) => g.setRepeatPenaltyTokens(val.toInt()),
          tooltip:
              'How many tokens back the repetition penalty checks. 1024 is community standard.',
        ),
      );
    }

    if (knobs.contains(SamplerKnob.xtc)) {
      if (col2Widgets.isNotEmpty) col2Widgets.add(const SizedBox(height: 10));
      col2Widgets.add(
        StudioSliderCard(
          label: 'XTC Threshold',
          value: g.xtcThreshold,
          min: 0.0,
          max: 1.00,
          defaultVal: 0.10,
          dangerMax: 0.80,
          divisions: 50,
          decimalPlaces: 2,
          reset: r((v) => v.xtcThreshold),
          onChanged: (val) => g.setXtcThreshold(val),
          tooltip:
              'Exclude Top Choices threshold. Removes obvious clichés if top token probability exceeds this.',
        ),
      );
      col2Widgets.add(const SizedBox(height: 10));
      col2Widgets.add(
        StudioSliderCard(
          label: 'XTC Probability',
          value: g.xtcProbability,
          min: 0.0,
          max: 1.00,
          defaultVal: 0.0,
          dangerMax: 0.60,
          divisions: 20,
          decimalPlaces: 2,
          reset: r((v) => v.xtcProbability),
          onChanged: (val) => g.setXtcProbability(val),
          tooltip: 'How frequently XTC activates. 0 = off, 0.30–0.50 is balanced.',
        ),
      );
    }

    final col2 = <Widget>[
      if (col2Widgets.isNotEmpty) ...[
        Text(
          'FLOW & ANTI-REPETITION',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: AppColors.formAccentOf(context),
          ),
        ),
        const SizedBox(height: 8),
        ...col2Widgets,
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 680 && col2.isNotEmpty;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: col1,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: col2,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...col1,
            if (col2.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...col2,
            ],
          ],
        );
      },
    );
  }
}
