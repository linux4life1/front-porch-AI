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
  test(
    'Qwen 2.1 edit keeps its sampler denoise when the pack asks for 0.7',
    () {
      final request = resolveComfyEditRequest(
        workflowId: 'comfy:userdata:qwen_edit',
        uploadedWorkflowJson: '',
        modelChoices: const {},
        liveTemplate: {
          'image': {
            'class_type': 'LoadImage',
            'inputs': {'image': 'reference.png'},
          },
          'encode': {
            'class_type': 'TextEncodeQwenImage21',
            'inputs': {
              'prompt': 'Change the expression',
              'images.image_1': ['image', 0],
            },
          },
          'latent': {
            'class_type': 'ComfySwitchNode',
            'inputs': {
              'on_false': ['encode', 2],
              'on_true': ['empty', 0],
              'switch': false,
            },
          },
          'empty': {
            'class_type': 'EmptyLatentImage',
            'inputs': <String, Object>{},
          },
          'sampler': {
            'class_type': 'KSampler',
            'inputs': {
              'latent_image': ['latent', 0],
              'denoise': 1.0,
            },
          },
        },
        prompt: 'Make her smile',
        negative: '',
        seed: 42,
        steps: 25,
        cfg: 1,
        denoise: 0.7,
        shift: 1,
      );

      expect(request, isNotNull);
      final graph = substituteComfyWorkflow(request!.template, {
        ...request.values,
        ComfyEditTokens.image: 'uploaded.png',
      });
      expect((graph['sampler'] as Map)['inputs']['denoise'], 1.0);
      expect((graph['image'] as Map)['inputs']['image'], 'uploaded.png');
    },
  );

  test('ordinary img2img sampler still follows the pack strength', () {
    final adapted = adaptComfyApiWorkflow({
      'sampler': {
        'class_type': 'KSampler',
        'inputs': {
          'latent_image': ['encoded_source', 0],
          'denoise': 1.0,
        },
      },
    });
    expect(
      (adapted.template['sampler'] as Map)['inputs']['denoise'],
      ComfyEditTokens.denoise,
    );
  });

  test('selected VAE latent branch keeps denoise tunable', () {
    final adapted = adaptComfyApiWorkflow({
      'qwen': {
        'class_type': 'TextEncodeQwenImage21',
        'inputs': <String, Object>{},
      },
      'source': {'class_type': 'VAEEncode', 'inputs': <String, Object>{}},
      'latent': {
        'class_type': 'ComfySwitchNode',
        'inputs': {
          'on_false': ['qwen', 2],
          'on_true': ['source', 0],
          'switch': true,
        },
      },
      'sampler': {
        'class_type': 'KSampler',
        'inputs': {
          'latent_image': ['latent', 0],
          'denoise': 1.0,
        },
      },
    });
    expect(
      (adapted.template['sampler'] as Map)['inputs']['denoise'],
      ComfyEditTokens.denoise,
    );
  });
}
