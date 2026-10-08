// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';

Map<String, dynamic> _workflow({
  List<Object?>? widgets,
  Map<String, Object?>? named,
  bool externalWidth = false,
}) => {
  'nodes': [
    {
      'id': 1,
      'type': 'PrimitiveInt',
      'widgets_values': [640],
    },
    {
      'id': 88,
      'type': 'dimensions',
      'properties': {
        'proxyWidgets': [
          [71, 'width'],
          [71, 'height'],
          [90, 'string_a'],
        ],
      },
      'widgets_values': ?widgets,
      'widgets_values_named': ?named,
      'inputs': [
        {'name': 'width', 'link': externalWidth ? 1 : null},
        {'name': 'height', 'link': null},
        {'name': 'prompt', 'link': null},
      ],
    },
    {
      'id': 99,
      'type': 'SaveImage',
      'inputs': [
        {'name': 'images', 'link': 2},
      ],
      'widgets_values': ['out'],
    },
  ],
  'links': [
    if (externalWidth) [1, 1, 0, 88, 0, 'INT'],
    [2, 88, 0, 99, 0, 'IMAGE'],
  ],
  'definitions': {
    'subgraphs': [
      {
        'id': 'dimensions',
        'inputs': [
          {'name': 'width', 'type': 'INT'},
          {'name': 'height', 'type': 'INT'},
          {'name': 'prompt', 'type': 'STRING'},
        ],
        'nodes': [
          {
            'id': 71,
            'type': 'EmptySD3LatentImage',
            'inputs': [
              {'name': 'width', 'link': 104},
              {'name': 'height', 'link': 105},
            ],
            'widgets_values': [1024, 768, 1],
          },
          for (final entry in [(92, 113), (93, 114)])
            {
              'id': entry.$1,
              'type': 'PreviewAny',
              'inputs': [
                {'name': 'source', 'link': entry.$2},
              ],
              'widgets_values': [null, null, null],
            },
          {
            'id': 90,
            'type': 'StringConcatenate',
            'inputs': [
              {'name': 'string_a', 'link': 115},
            ],
            'widgets_values': ['saved prompt', ''],
          },
          {
            'id': 94,
            'type': 'StringReplace',
            'inputs': [
              {'name': 'string', 'link': 123},
              {'name': 'replace', 'link': 116},
              {'name': 'find', 'link': null},
            ],
            'widgets_values': ['saved prompt', '', '{width}'],
          },
          {
            'id': 95,
            'type': 'TextGenerate',
            'inputs': [
              {'name': 'prompt', 'link': 117},
            ],
            'widgets_values': ['saved prompt', 512, 'off', false, true, 'auto'],
          },
          {
            'id': 96,
            'type': 'ComfySwitchNode',
            'inputs': [
              {'name': 'on_true', 'link': 118},
            ],
            'widgets_values': [true],
          },
          {
            'id': 97,
            'type': 'CLIPTextEncode',
            'inputs': [
              {'name': 'text', 'link': 119},
            ],
            'widgets_values': [''],
          },
          {
            'id': 98,
            'type': 'KSampler',
            'inputs': [
              {'name': 'positive', 'link': 120},
              {'name': 'latent_image', 'link': 121},
            ],
            'widgets_values': [123, 'randomize', 20, 7, 'euler', 'normal', 1],
          },
        ],
        'links': [
          // The non-owner consumers precede the promoted widget owners.
          [113, -10, 0, 92, 0, 'INT'],
          [114, -10, 1, 93, 0, 'INT'],
          [104, -10, 0, 71, 0, 'INT'],
          [105, -10, 1, 71, 1, 'INT'],
          [115, -10, 2, 90, 0, 'STRING'],
          [123, 90, 0, 94, 0, 'STRING'],
          [116, 92, 0, 94, 1, 'STRING'],
          [117, 94, 0, 95, 0, 'STRING'],
          [118, 95, 0, 96, 0, 'STRING'],
          [119, 96, 0, 97, 0, 'STRING'],
          [120, 97, 0, 98, 0, 'CONDITIONING'],
          [121, 71, 0, 98, 1, 'LATENT'],
          [122, 98, 0, -20, 0, 'IMAGE'],
        ],
      },
    ],
  },
};

Map<String, dynamic> _objectInfo() => {
  'PrimitiveInt': {
    'input': {
      'required': {
        'value': ['INT', {}],
      },
    },
  },
  'PreviewAny': {
    'input': {
      'required': {
        'source': ['*', {}],
      },
      'optional': {
        'mode': ['STRING', {}],
        'label': ['STRING', {}],
      },
    },
  },
  'StringReplace': {
    'input': {
      'required': {
        'string': ['STRING', {}],
        'replace': ['STRING', {}],
        'find': ['STRING', {}],
      },
    },
  },
};

Map _inputs(Map<String, dynamic> graph, String id) =>
    graph[id]['inputs'] as Map;

void _expectDimensions(
  Map<String, dynamic> graph,
  Object width,
  Object height,
) {
  expect(_inputs(graph, '88_71')['width'], width);
  expect(_inputs(graph, '88_71')['height'], height);
  expect(_inputs(graph, '88_92')['source'], width);
  expect(_inputs(graph, '88_93')['source'], height);
}

void main() {
  test(
    'promoted defaults reach every consumer and retain the prompt chain',
    () {
      final graph = convertComfyUiToApi(_workflow(), objectInfo: _objectInfo());
      _expectDimensions(graph, 1024, 768);
      expect(_inputs(graph, '88_90')['string_a'], '%PROMPT%');
      expect(_inputs(graph, '88_94')['string'], ['88_90', 0]);
      expect(_inputs(graph, '88_94')['replace'], ['88_92', 0]);
      expect(_inputs(graph, '88_95')['prompt'], ['88_94', 0]);
      expect(_inputs(graph, '88_96')['on_true'], ['88_95', 0]);
      expect(_inputs(graph, '88_97')['text'], ['88_96', 0]);
      expect(_inputs(graph, '88_98')['positive'], ['88_97', 0]);
      expect(_inputs(graph, '88_98')['latent_image'], ['88_71', 0]);
      expect(_inputs(graph, '99')['images'], ['88_98', 0]);
    },
  );

  test('positional and named parent overrides reach non-owner consumers', () {
    final graph = convertComfyUiToApi(
      _workflow(widgets: [896, 512], named: {'width': 1152}),
      objectInfo: _objectInfo(),
    );
    _expectDimensions(graph, 1152, 512);
  });

  test('external links win over promoted widget defaults and overrides', () {
    final graph = convertComfyUiToApi(
      _workflow(widgets: [896, 512], externalWidth: true),
      objectInfo: _objectInfo(),
    );
    _expectDimensions(graph, ['1', 0], 512);
  });

  test('fallback widget order also propagates dimension defaults', () {
    _expectDimensions(convertComfyUiToApi(_workflow()), 1024, 768);
  });
  test(
    'promoted defaults use serialized slots after seed and dynamic controls',
    () {
      final ui = _workflow();
      final parent = (ui['nodes'] as List)[1] as Map;
      parent['properties']['proxyWidgets'] = [
        [71, 'mode.width'],
        [71, 'mode.height'],
        [90, 'string_a'],
      ];
      final sg = ui['definitions']['subgraphs'][0] as Map;
      final owner = (sg['nodes'] as List).first as Map;
      owner['type'] = 'DimensionSelector';
      owner['inputs'][0]['name'] = 'mode.width';
      owner['inputs'][1]['name'] = 'mode.height';
      owner['widgets_values'] = [123, 'randomize', 'on', 1280, 720, 1];
      final info = _objectInfo();
      info['DimensionSelector'] = {
        'input': {
          'required': {
            'seed': ['INT', {}],
            'mode': [
              'COMFY_DYNAMICCOMBO_V3',
              {
                'options': [
                  {
                    'key': 'on',
                    'inputs': {
                      'required': {
                        'width': ['INT', {}],
                        'height': ['INT', {}],
                      },
                    },
                  },
                ],
              },
            ],
            'batch_size': ['INT', {}],
          },
        },
      };
      final graph = convertComfyUiToApi(ui, objectInfo: info);
      expect(_inputs(graph, '88_71')['mode.width'], 1280);
      expect(_inputs(graph, '88_71')['mode.height'], 720);
      expect(_inputs(graph, '88_71')['seed'], 123);
      expect(_inputs(graph, '88_71')['batch_size'], 1);
      expect(_inputs(graph, '88_92')['source'], 1280);
      expect(_inputs(graph, '88_93')['source'], 720);
    },
  );
  test('without proxies null preview widgets do not shadow real defaults', () {
    final ui = _workflow();
    ((ui['nodes'] as List)[1] as Map).remove('properties');
    final graph = convertComfyUiToApi(ui, objectInfo: _objectInfo());
    _expectDimensions(graph, 1024, 768);
  });
}
