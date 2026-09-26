// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';

void main() {
  test('linked subgraph prompt still becomes the user prompt', () {
    final ui = _subgraphUi(twoInstances: false);
    final graph = adaptComfyApiWorkflow(convertComfyUiToApi(ui)).template;
    expect((graph['2_11'] as Map)['inputs']['text'], '%PROMPT%');
    expect((graph['2_12'] as Map)['inputs']['text'], '%NEGATIVE%');
  });

  test('linked positive prompt keeps the negative token in order', () {
    final graph = adaptComfyApiWorkflow({
      'source': {
        'class_type': 'PrimitiveStringMultiline',
        'inputs': {'value': 'outside'},
      },
      'positive': {
        'class_type': 'CLIPTextEncode',
        'inputs': {
          'text': ['source', 0],
        },
      },
      'negative': {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': 'bad'},
      },
    }).template;
    expect((graph['positive'] as Map)['inputs']['text'], ['source', 0]);
    expect((graph['negative'] as Map)['inputs']['text'], '%NEGATIVE%');
  });

  test('primitive widget order skips linked image port', () {
    final graph = convertComfyUiToApi(_subgraphUi(twoInstances: false));
    expect((graph['2_13'] as Map)['inputs']['weight_dtype'], 'fp8_e4m3fn');
  });

  test('proxy widget order overrides subgraph input order', () {
    final ui = _subgraphUi(twoInstances: false);
    final instance =
        (ui['nodes'] as List).firstWhere((n) => n['id'] == 2) as Map;
    instance['properties'] = {
      'proxyWidgets': [
        [13, 'weight_dtype'],
        [13, 'unet_name'],
        [11, 'text'],
      ],
    };
    instance['widgets_values'] = ['fp8_e4m3fn', 'first.gguf', 'positive'];
    final graph = convertComfyUiToApi(ui);
    expect((graph['2_13'] as Map)['inputs']['weight_dtype'], 'fp8_e4m3fn');
    expect((graph['2_13'] as Map)['inputs']['unet_name'], 'first.gguf');
  });

  test('repeated subgraph instances retain their own links', () {
    final graph = convertComfyUiToApi(_subgraphUi(twoInstances: true));
    expect((graph['2_13'] as Map)['inputs']['unet_name'], 'first.gguf');
    expect((graph['3_13'] as Map)['inputs']['unet_name'], 'second.gguf');
    expect((graph['2_14'] as Map)['inputs']['image'], ['1', 0]);
    expect((graph['3_14'] as Map)['inputs']['image'], ['5', 0]);
  });

  test('negative subgraph port and target slots are ignored', () {
    final ui = _subgraphUi(twoInstances: false);
    final sg = ((ui['definitions'] as Map)['subgraphs'] as List).first as Map;
    (sg['links'] as List).addAll(<List<Object>>[
      [20, -10, -1, 13, 0, 'COMBO'],
      [21, -10, 0, 13, -1, 'IMAGE'],
    ]);
    expect(() => convertComfyUiToApi(ui), returnsNormally);
  });

  test('GGUF multi-encoder loaders expose every model slot', () {
    for (final count in [2, 3, 4]) {
      final kind = ['', '', 'Dual', 'Triple', 'Quadruple'][count];
      final loader = '${kind}CLIPLoaderGGUF';
      final inputs = {
        for (var i = 1; i <= count; i++) 'clip_name$i': 'clip$i.gguf',
      };
      final graph = adaptComfyApiWorkflow({
        '1': {'class_type': loader, 'inputs': inputs},
      });
      expect(graph.slots.length, count);
      for (var i = 1; i <= count; i++) {
        expect(
          (graph.template['1'] as Map)['inputs']['clip_name$i'],
          '%MODEL_CLIP$i%',
        );
      }
    }
  });

  test('unrelated string switch is not treated as a prompt', () {
    final graph = adaptComfyApiWorkflow({
      '1': {
        'class_type': 'ComfySwitchNode',
        'inputs': {'on_false': 'model.gguf'},
      },
    });
    expect((graph.template['1'] as Map)['inputs']['on_false'], 'model.gguf');
  });

  test('switch feeding a text encoder owns the user prompt', () {
    final graph = adaptComfyApiWorkflow({
      '1': {
        'class_type': 'ComfySwitchNode',
        'inputs': {'on_false': 'first'},
      },
      '2': {
        'class_type': 'CLIPTextEncode',
        'inputs': {
          'text': ['1', 0],
        },
      },
    });
    expect((graph.template['1'] as Map)['inputs']['on_false'], '%PROMPT%');
  });

  test('numeric switch value remains numeric', () {
    final graph = adaptComfyApiWorkflow({
      '1': {
        'class_type': 'ComfySwitchNode',
        'inputs': {'on_false': 4},
      },
    });
    expect((graph.template['1'] as Map)['inputs']['on_false'], 4);
  });
}

Map<String, dynamic> _subgraphUi({required bool twoInstances}) {
  final inputs = [
    {'name': 'image', 'type': 'IMAGE', 'link': 1},
    {'name': 'text', 'type': 'STRING', 'link': 3},
    {'name': 'unet_name', 'type': 'COMBO', 'link': null},
    {'name': 'weight_dtype', 'type': 'COMBO', 'link': null},
  ];
  Map<String, dynamic> instance(int id, List<Object> values) => {
    'id': id,
    'type': 'sg',
    'inputs': [
      for (final input in inputs)
        {...input, if (input['name'] == 'image') 'link': id == 2 ? 1 : 2},
    ],
    'widgets_values': values,
  };
  return {
    'nodes': [
      {
        'id': 1,
        'type': 'LoadImage',
        'widgets_values': ['image.png'],
      },
      {
        'id': 4,
        'type': 'PrimitiveStringMultiline',
        'widgets_values': ['outside'],
      },
      instance(2, ['positive', 'first.gguf', 'fp8_e4m3fn']),
      if (twoInstances)
        {
          'id': 5,
          'type': 'LoadImage',
          'widgets_values': ['other.png'],
        },
      if (twoInstances) instance(3, ['negative', 'second.gguf', 'default']),
    ],
    'links': [
      [1, 1, 0, 2, 0, 'IMAGE'],
      [3, 4, 0, 2, 1, 'STRING'],
      if (twoInstances) [2, 5, 0, 3, 0, 'IMAGE'],
    ],
    'definitions': {
      'subgraphs': [
        {
          'id': 'sg',
          'inputs': [
            {'name': 'image', 'type': 'IMAGE'},
            {'name': 'text', 'type': 'STRING'},
            {'name': 'unet_name', 'type': 'COMBO'},
            {'name': 'weight_dtype', 'type': 'COMBO'},
          ],
          'nodes': [
            {
              'id': 11,
              'type': 'CLIPTextEncode',
              'inputs': [
                {'name': 'text', 'link': 10},
              ],
              'widgets_values': ['inner positive'],
            },
            {
              'id': 12,
              'type': 'CLIPTextEncode',
              'inputs': [
                {'name': 'text', 'link': null},
              ],
              'widgets_values': ['inner negative'],
            },
            {
              'id': 14,
              'type': 'VAEEncode',
              'inputs': [
                {'name': 'image', 'link': 13},
              ],
            },
            {
              'id': 13,
              'type': 'UNETLoader',
              'inputs': [
                {'name': 'unet_name', 'link': 11},
                {'name': 'weight_dtype', 'link': 12},
              ],
              'widgets_values': ['inner.gguf', 'default'],
            },
          ],
          'links': [
            [10, -10, 1, 11, 0, 'STRING'],
            [13, -10, 0, 14, 0, 'IMAGE'],
            [11, -10, 2, 13, 0, 'COMBO'],
            [12, -10, 3, 13, 1, 'COMBO'],
          ],
        },
      ],
    },
  };
}
