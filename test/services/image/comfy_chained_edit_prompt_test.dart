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
  test('exposed edit prompt survives concatenate, switch, and preview', () {
    final ui = <String, dynamic>{
      'nodes': [
        {
          'id': 1,
          'type': 'PrimitiveStringMultiline',
          'widgets_values': ['old'],
        },
        {
          'id': 2,
          'type': 'edit-subgraph',
          'inputs': [
            {'name': 'prompt', 'type': 'STRING', 'link': 1},
          ],
          'widgets_values': ['old'],
        },
      ],
      'links': [
        [1, 1, 0, 2, 0, 'STRING'],
      ],
      'definitions': {
        'subgraphs': [
          {
            'id': 'edit-subgraph',
            'inputs': [
              {'name': 'prompt', 'type': 'STRING'},
            ],
            'nodes': [
              {
                'id': 10,
                'type': 'StringConcatenate',
                'inputs': [
                  {'name': 'string_a', 'link': 10},
                  {'name': 'string_b', 'link': null},
                ],
                'widgets_values': ['', '<image1>'],
              },
              {
                'id': 11,
                'type': 'ComfySwitchNode',
                'inputs': [
                  {'name': 'on_false', 'link': 11},
                  {'name': 'on_true', 'link': null},
                  {'name': 'switch', 'link': null},
                ],
                'widgets_values': [false],
              },
              {
                'id': 12,
                'type': 'PreviewAny',
                'inputs': [
                  {'name': 'source', 'link': 12},
                ],
              },
              {
                'id': 13,
                'type': 'TextEncodeQwenImage21',
                'inputs': [
                  {'name': 'prompt', 'link': 13},
                  {'name': 'negative_prompt', 'link': null},
                ],
                'widgets_values': ['', 'bad'],
              },
              {
                'id': 14,
                'type': 'LoadImage',
                'widgets_values': ['portrait.png'],
              },
            ],
            'links': [
              [10, -10, 0, 10, 0, 'STRING'],
              [11, 10, 0, 11, 0, 'STRING'],
              [12, 11, 0, 12, 0, 'STRING'],
              [13, 12, 0, 13, 0, 'STRING'],
            ],
          },
        ],
      },
    };

    final graph = adaptComfyApiWorkflow(convertComfyUiToApi(ui)).template;
    expect((graph['2_10'] as Map)['inputs']['string_a'], '%PROMPT%');
    expect(
      comfyEditReady(
        workflowId: 'comfy:userdata:chained-edit',
        uploadedWorkflowJson: '',
        modelChoices: const {},
        liveTemplate: ui,
      ),
      isTrue,
    );
  });
}
