// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/gen_presets/gen_presets.dart';

import 'slider_setting.dart';

/// Settings → Generation's sampler sliders, each with a ↺ back to the chat
/// model's recommended value (or the app default) when it differs.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SliderSetting(
          label: 'Temperature',
          value: storage.generationSettings.temperature,
          min: 0.0,
          max: 2.0,
          onChanged: (val) => storage.generationSettings.setTemperature(val),
          divisions: 20,
          showInput: true,
          decimalPlaces: 1,
          reset: r((v) => v.temperature),
        ),
        if (knobs.contains(SamplerKnob.minP))
          SliderSetting(
            label: 'Min-P',
            value: storage.generationSettings.minP,
            min: 0.0,
            max: 1.0,
            onChanged: (val) => storage.generationSettings.setMinP(val),
            divisions: 100,
            showInput: true,
            decimalPlaces: 2,
            reset: r((v) => v.minP),
          ),
        SliderSetting(
          label: 'Top-P',
          value: storage.generationSettings.topP,
          min: 0.1,
          max: 1.0,
          onChanged: (val) => storage.generationSettings.setTopP(val),
          divisions: 90,
          showInput: true,
          decimalPlaces: 2,
          reset: r((v) => v.topP),
        ),
        if (knobs.contains(SamplerKnob.topK))
          SliderSetting(
            label: 'Top-K',
            value: storage.generationSettings.topK.toDouble(),
            min: 0,
            max: 200,
            onChanged: (val) => storage.generationSettings.setTopK(val.toInt()),
            divisions: 200,
            showInput: true,
            isInteger: true,
            reset: r((v) => v.topK),
          ),
        if (knobs.contains(SamplerKnob.repeatPenalty))
          SliderSetting(
            label: 'Repeat Penalty',
            value: storage.generationSettings.repeatPenalty,
            min: 1.0,
            max: 3.0,
            onChanged: (val) =>
                storage.generationSettings.setRepeatPenalty(val),
            divisions: 200,
            showInput: true,
            decimalPlaces: 2,
            reset: r((v) => v.repeatPenalty),
          ),
        if (knobs.contains(SamplerKnob.repeatPenaltyTokens))
          SliderSetting(
            label: 'Repeat Penalty Tokens',
            value: storage.generationSettings.repeatPenaltyTokens.toDouble(),
            min: 0,
            max: 2048,
            onChanged: (val) =>
                storage.generationSettings.setRepeatPenaltyTokens(val.toInt()),
            divisions: 256,
            showInput: true,
            isInteger: true,
            reset: r((v) => v.repeatPenaltyTokens),
          ),
        if (knobs.contains(SamplerKnob.xtc)) ...[
          SliderSetting(
            label: 'XTC Threshold',
            value: storage.generationSettings.xtcThreshold,
            min: 0.0,
            max: 0.5,
            onChanged: (val) => storage.generationSettings.setXtcThreshold(val),
            divisions: 50,
            showInput: true,
            decimalPlaces: 2,
            reset: r((v) => v.xtcThreshold),
          ),
          SliderSetting(
            label: 'XTC Probability',
            value: storage.generationSettings.xtcProbability,
            min: 0.0,
            max: 1.0,
            onChanged: (val) =>
                storage.generationSettings.setXtcProbability(val),
            divisions: 20,
            showInput: true,
            decimalPlaces: 2,
            reset: r((v) => v.xtcProbability),
          ),
        ],
        if (knobs.contains(SamplerKnob.dry))
          SliderSetting(
            label: 'DRY Strength',
            value: storage.generationSettings.dryMultiplier,
            min: 0.0,
            max: 3.0,
            onChanged: (val) =>
                storage.generationSettings.setDryMultiplier(val),
            divisions: 60,
            showInput: true,
            decimalPlaces: 2,
            reset: r((v) => v.dryMultiplier),
          ),
        if (knobs.contains(SamplerKnob.dynamicTemp)) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Dynamic Temperature',
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
              const Spacer(),
              Switch(
                value: storage.generationSettings.dynamicTempEnabled,
                onChanged: (val) =>
                    storage.generationSettings.setDynamicTempEnabled(val),
                activeTrackColor: accent,
              ),
            ],
          ),
          if (storage.generationSettings.dynamicTempEnabled)
            SliderSetting(
              label: 'Dynatemp Range',
              value: storage.generationSettings.dynamicTempRange,
              min: 0.0,
              max: 2.0,
              onChanged: (val) =>
                  storage.generationSettings.setDynamicTempRange(val),
              divisions: 20,
              showInput: true,
              decimalPlaces: 1,
              reset: r((v) => v.dynamicTempRange),
            ),
        ],
      ],
    );
  }
}
