// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// #338: a saved ComfyUI workflow that wires a link through a Reroute node
// must keep that connection when converted to the /prompt API graph. A
// Reroute's only input has an empty name, and the node reader used to
// drop it — so the follow-through found a Reroute with no inputs and the
// consumer lost its wire.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/image.dart';

Map<String, dynamic> _reroute(int id, int inLink, int outLink) => {
  'id': id,
  'type': 'Reroute',
  'widgets_values': <Object?>[],
  'inputs': [
    {'name': '', 'type': '*', 'link': inLink},
  ],
  'outputs': [
    {
      'name': '',
      'type': '*',
      'links': [outLink],
    },
  ],
};

void main() {
  test('a link through one Reroute reaches the consumer', () {
    final ui = {
      'nodes': [
        {
          'id': 1,
          'type': 'CheckpointLoaderSimple',
          'widgets_values': ['sdxl.safetensors'],
          'inputs': <Map>[],
          'outputs': [
            {
              'name': 'CLIP',
              'links': [1],
            },
          ],
        },
        _reroute(5, 1, 2),
        {
          'id': 2,
          'type': 'CLIPTextEncode',
          'widgets_values': ['hello porch'],
          'inputs': [
            {'name': 'clip', 'type': 'CLIP', 'link': 2},
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
        [1, 1, 1, 5, 0, '*'],
        [2, 5, 0, 2, 0, 'CLIP'],
      ],
    };
    final api = convertComfyUiToApi(ui.cast<String, dynamic>());
    expect(api.containsKey('5'), isFalse, reason: 'Reroute is not a node');
    expect(api['2']['inputs']['clip'], ['1', 1]);
  });

  test('a link through two chained Reroutes still reaches the consumer', () {
    final ui = {
      'nodes': [
        {
          'id': 1,
          'type': 'CheckpointLoaderSimple',
          'widgets_values': ['sdxl.safetensors'],
          'inputs': <Map>[],
          'outputs': [
            {
              'name': 'CLIP',
              'links': [1],
            },
          ],
        },
        _reroute(5, 1, 2),
        _reroute(6, 2, 3),
        {
          'id': 2,
          'type': 'CLIPTextEncode',
          'widgets_values': ['hello porch'],
          'inputs': [
            {'name': 'clip', 'type': 'CLIP', 'link': 3},
          ],
        },
      ],
      'links': [
        [1, 1, 1, 5, 0, '*'],
        [2, 5, 0, 6, 0, '*'],
        [3, 6, 0, 2, 0, 'CLIP'],
      ],
    };
    final api = convertComfyUiToApi(ui.cast<String, dynamic>());
    expect(api['2']['inputs']['clip'], ['1', 1]);
  });
}
