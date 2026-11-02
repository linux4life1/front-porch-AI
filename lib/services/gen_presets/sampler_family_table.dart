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

import 'package:front_porch_ai/services/gen_presets/sampler_values.dart';

/// One model family's published samplers, for models whose file or host
/// carries none (older GGUFs, NanoGPT, oMLX).
class SamplerFamily {
  const SamplerFamily(this.label, this.pattern, this.values);

  /// The family as the user knows it, shown as the source of a reset.
  final String label;

  /// Matched against the lower-cased model file name or id.
  final String pattern;

  final SamplerValues values;
}

/// The model authors' own recommendations, from each family's model card or
/// `generation_config.json`. First match wins, so narrower patterns come
/// first. Families whose authors recommend assistant-only values (Mistral's
/// 0.15-0.3) are left out on purpose: the app defaults suit chat better.
const List<SamplerFamily> kSamplerFamilies = [
  SamplerFamily(
    'Qwen3 Instruct',
    r'qwen3.*(instruct|coder)',
    SamplerValues(temperature: 0.7, topP: 0.8, topK: 20, minP: 0.0),
  ),
  // Hybrid Qwen3 files think by default, so they get the thinking values.
  SamplerFamily(
    'Qwen3 (thinking)',
    r'qwen3',
    SamplerValues(temperature: 0.6, topP: 0.95, topK: 20, minP: 0.0),
  ),
  SamplerFamily(
    'QwQ',
    r'qwq',
    SamplerValues(temperature: 0.6, topP: 0.95, topK: 40, minP: 0.0),
  ),
  SamplerFamily(
    'Qwen2.5',
    r'qwen2\.5',
    SamplerValues(temperature: 0.7, topP: 0.8, topK: 20, repeatPenalty: 1.05),
  ),
  SamplerFamily(
    'DeepSeek R1',
    r'deepseek.*r1|r1.*distill',
    SamplerValues(temperature: 0.6, topP: 0.95),
  ),
  SamplerFamily(
    'Gemma 3',
    r'gemma[-_ ]?3',
    SamplerValues(temperature: 1.0, topP: 0.95, topK: 64, minP: 0.0),
  ),
  SamplerFamily(
    'Llama 3',
    r'llama[-_ ]?3',
    SamplerValues(temperature: 0.6, topP: 0.9),
  ),
  SamplerFamily(
    'GLM-4.6',
    r'glm[-_ ]?4\.6',
    SamplerValues(temperature: 1.0, topP: 0.95, topK: 40),
  ),
  SamplerFamily(
    'Kimi K2 Thinking',
    r'kimi[-_ ]?k2.*thinking',
    SamplerValues(temperature: 1.0),
  ),
  SamplerFamily('Kimi K2', r'kimi[-_ ]?k2', SamplerValues(temperature: 0.6)),
  SamplerFamily(
    'gpt-oss',
    r'gpt[-_ ]?oss',
    SamplerValues(temperature: 1.0, topP: 1.0, topK: 0),
  ),
];

/// The first family whose pattern matches [modelName], or null.
SamplerFamily? samplerFamilyFor(String modelName) {
  final name = modelName.toLowerCase();
  for (final f in kSamplerFamilies) {
    if (RegExp(f.pattern).hasMatch(name)) return f;
  }
  return null;
}
