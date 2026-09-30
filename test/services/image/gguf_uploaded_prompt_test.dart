// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/comfy_workflow_adapt.dart';
import 'package:front_porch_ai/services/image/comfy_workflow_convert.dart';

void main() {
  test(
    'uploaded GGUF subgraph keeps its exposed prompt through both feeds',
    () {
      final ui = <String, dynamic>{
        'nodes': [
          {
            'id': 1,
            'type': 'sg',
            'inputs': [
              {'name': 'prompt', 'type': 'STRING', 'link': null},
            ],
            'widgets_values': ['Edit the image'],
          },
        ],
        'links': [],
        'definitions': {
          'subgraphs': [
            {
              'id': 'sg',
              'inputs': [
                {'name': 'prompt', 'type': 'STRING'},
              ],
              'nodes': [
                {
                  'id': 13,
                  'type': 'TextEncodeQwenImage21',
                  'inputs': [
                    {'name': 'prompt', 'link': 4},
                    {'name': 'negative_prompt', 'link': null},
                  ],
                  'widgets_values': ['', 'undesired'],
                },
                {
                  'id': 10,
                  'type': 'ComfySwitchNode',
                  'inputs': [
                    {'name': 'on_false', 'link': 1},
                    {'name': 'on_true', 'link': null},
                  ],
                  'widgets_values': ['', 'enhanced'],
                },
                {
                  'id': 11,
                  'type': 'TextGenerate',
                  'inputs': [
                    {'name': 'prompt', 'link': 2},
                  ],
                  'widgets_values': ['Edit the image'],
                },
                {
                  'id': 12,
                  'type': 'PreviewAny',
                  'inputs': [
                    {'name': 'source', 'link': 3},
                  ],
                },
                {
                  'id': 14,
                  'type': 'CLIPLoaderGGUF',
                  'widgets_values': ['encoder.gguf', 'qwen_image'],
                },
                {
                  'id': 15,
                  'type': 'UnetLoaderGGUFAdvanced',
                  'widgets_values': [
                    'diffusion.gguf',
                    'default',
                    'default',
                    false,
                  ],
                },
              ],
              'links': [
                [1, -10, 0, 10, 0, 'STRING'],
                [2, -10, 0, 11, 0, 'STRING'],
                [3, 10, 0, 12, 0, 'STRING'],
                [4, 12, 0, 13, 0, 'STRING'],
              ],
            },
          ],
        },
      };

      final adapted = adaptComfyApiWorkflow(convertComfyUiToApi(ui));
      final graph = adapted.template;
      expect((graph['1_10'] as Map)['inputs']['on_false'], '%PROMPT%');
      expect((graph['1_11'] as Map)['inputs']['prompt'], '%PROMPT%');
      expect((graph['1_13'] as Map)['inputs']['negative_prompt'], '%NEGATIVE%');
      expect(
        adapted.slots.map((slot) => slot.loaderClass),
        containsAll(['CLIPLoaderGGUF', 'UnetLoaderGGUFAdvanced']),
      );
    },
  );
}
