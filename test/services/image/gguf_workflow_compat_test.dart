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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';

void main() {
  test('GGUF UI workflow keeps loader widgets and exposes model slots', () {
    final api = convertComfyUiToApi({
      'nodes': [
        {
          'id': 1,
          'type': 'UnetLoaderGGUF',
          'inputs': <Object>[],
          'outputs': <Object>[],
          'widgets_values': ['diffusion.gguf'],
        },
        {
          'id': 2,
          'type': 'CLIPLoaderGGUF',
          'inputs': <Object>[],
          'outputs': <Object>[],
          'widgets_values': ['encoder.gguf', 'lumina2'],
        },
      ],
      'links': <Object>[],
    });
    expect((api['1'] as Map)['inputs']['unet_name'], 'diffusion.gguf');
    expect((api['2'] as Map)['inputs']['clip_name'], 'encoder.gguf');
    final adapted = adaptComfyApiWorkflow(api);
    expect(
      adapted.slots.map((s) => s.loaderClass),
      containsAll(['UnetLoaderGGUF', 'CLIPLoaderGGUF']),
    );
    expect(
      (adapted.template['1'] as Map)['inputs']['unet_name'],
      '%MODEL_DIFFUSION%',
    );
    expect(
      (adapted.template['2'] as Map)['inputs']['clip_name'],
      '%MODEL_CLIP%',
    );
  });

  test('Qwen prompt inputs remain available after adaptation', () {
    final adapted = adaptComfyApiWorkflow({
      'text': {
        'class_type': 'TextGenerate',
        'inputs': {'prompt': 'A porch at dusk'},
      },
      'qwen': {
        'class_type': 'TextEncodeQwenImage21',
        'inputs': {
          'prompt': ['text', 0],
          'negative_prompt': 'blurred',
        },
      },
    });
    expect((adapted.template['text'] as Map)['inputs']['prompt'], '%PROMPT%');
    expect((adapted.template['qwen'] as Map)['inputs']['prompt'], ['text', 0]);
    expect(
      (adapted.template['qwen'] as Map)['inputs']['negative_prompt'],
      '%NEGATIVE%',
    );
  });
}
