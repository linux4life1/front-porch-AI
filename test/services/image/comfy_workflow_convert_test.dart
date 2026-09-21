// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// UI (litegraph) → /prompt API, including official subgraph wrappers.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/image.dart';

void main() {
  test('flat UI workflow becomes API nodes with named widgets + links', () {
    final ui = {
      'nodes': [
        {
          'id': 1,
          'type': 'CheckpointLoaderSimple',
          'widgets_values': ['sdxl.safetensors'],
          'inputs': <Map>[],
          'outputs': [
            {
              'name': 'MODEL',
              'links': [1],
            },
          ],
        },
        {
          'id': 2,
          'type': 'CLIPTextEncode',
          'widgets_values': ['hello porch'],
          'inputs': [
            {'name': 'clip', 'type': 'CLIP', 'link': 1},
            {
              'name': 'text',
              'type': 'STRING',
              'widget': {'name': 'text'},
              'link': null,
            },
          ],
        },
      ],
      'links': [
        [1, 1, 1, 2, 0, 'CLIP'],
      ],
    };
    final api = convertComfyUiToApi(ui.cast<String, dynamic>());
    expect(api['1']['class_type'], 'CheckpointLoaderSimple');
    expect(api['1']['inputs']['ckpt_name'], 'sdxl.safetensors');
    expect(api['2']['inputs']['text'], 'hello porch');
    expect(api['2']['inputs']['clip'], ['1', 1]);
  });

  test('subgraph wrapper exposes the inner UNET + CLIP + SaveImage link', () {
    final ui = {
      'nodes': [
        {
          'id': 9,
          'type': 'SaveImage',
          'widgets_values': ['out'],
          'inputs': [
            {'name': 'images', 'type': 'IMAGE', 'link': 62},
          ],
        },
        {
          'id': 57,
          'type': 'sg-zit',
          'widgets_values': <Object>[],
          'inputs': <Map>[],
          'outputs': [
            {
              'name': 'IMAGE',
              'links': [62],
            },
          ],
        },
        {'id': 35, 'type': 'MarkdownNote', 'widgets_values': ['docs'], 'inputs': <Map>[]},
      ],
      'links': [
        [62, 57, 0, 9, 0, 'IMAGE'],
      ],
      'definitions': {
        'subgraphs': [
          {
            'id': 'sg-zit',
            'nodes': [
              {
                'id': 28,
                'type': 'UNETLoader',
                'widgets_values': ['z_image_turbo_bf16.safetensors', 'default'],
                'inputs': <Map>[],
              },
              {
                'id': 8,
                'type': 'VAEDecode',
                'widgets_values': <Object>[],
                'inputs': [
                  {'name': 'samples', 'type': 'LATENT', 'link': 14},
                  {'name': 'vae', 'type': 'VAE', 'link': null},
                ],
              },
              {
                'id': 3,
                'type': 'KSampler',
                'widgets_values': [0, 'randomize', 8, 1, 'euler', 'simple', 1],
                'inputs': [
                  {'name': 'model', 'type': 'MODEL', 'link': 26},
                  {'name': 'positive', 'type': 'CONDITIONING', 'link': null},
                  {'name': 'negative', 'type': 'CONDITIONING', 'link': null},
                  {'name': 'latent_image', 'type': 'LATENT', 'link': null},
                ],
              },
            ],
            'links': [
              {'id': 26, 'origin_id': 28, 'origin_slot': 0, 'target_id': 3, 'target_slot': 0},
              {'id': 14, 'origin_id': 3, 'origin_slot': 0, 'target_id': 8, 'target_slot': 0},
              {'id': 16, 'origin_id': 8, 'origin_slot': 0, 'target_id': -20, 'target_slot': 0},
            ],
          },
        ],
      },
    };
    final api = convertComfyUiToApi(ui.cast<String, dynamic>());
    expect(api.containsKey('35'), isFalse, reason: 'notes must drop');
    expect(api['57_28']['class_type'], 'UNETLoader');
    expect(api['57_28']['inputs']['unet_name'], 'z_image_turbo_bf16.safetensors');
    expect(api['57_3']['inputs']['steps'], 8);
    expect(api['57_3']['inputs']['model'], ['57_28', 0]);
    expect(api['9']['inputs']['images'], ['57_8', 0]);
  });

  test('ensureComfyApiGraph is a no-op on API format', () {
    final api = ensureComfyApiGraph({
      '1': {
        'class_type': 'SaveImage',
        'inputs': {'filename_prefix': 'x'},
      },
    });
    expect(api!['1']['class_type'], 'SaveImage');
  });
}
