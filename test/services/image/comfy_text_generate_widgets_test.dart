// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TextGenerate's widgets_values are stored in ComfyUI's own order: seed, then
// presence_penalty. A conversion that swaps them, or that reads a live
// /object_info without knowing sampling_mode is a dynamic combo, hands the
// wrong number to the wrong input.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/comfy_workflow_convert.dart';

Map<String, dynamic> _ui(List<Object?> widgets) => {
  'nodes': [
    {
      'id': 1,
      'type': 'TextGenerate',
      'inputs': [
        {'name': 'prompt', 'link': null},
      ],
      'widgets_values': widgets,
    },
  ],
  'links': <Object>[],
};

/// `TextGenerate` as ComfyUI's /object_info reports it: sampling_mode is a
/// V3 dynamic combo whose "on" option carries the sampling widgets, and
/// image/video/audio are sockets that sit before the trailing widgets.
Map<String, dynamic> _objectInfo() {
  List<Object> f(String kind) => [kind, <String, Object>{}];
  return {
    'TextGenerate': {
      'input': {
        'required': {
          'clip': f('CLIP'),
          'prompt': f('STRING'),
          'max_length': f('INT'),
          'sampling_mode': [
            'COMFY_DYNAMICCOMBO_V3',
            {
              'options': [
                {
                  'key': 'on',
                  'inputs': {
                    'required': {
                      'temperature': f('FLOAT'),
                      'top_k': f('INT'),
                      'top_p': f('FLOAT'),
                      'min_p': f('FLOAT'),
                      'repetition_penalty': f('FLOAT'),
                      'seed': f('INT'),
                    },
                    'optional': {'presence_penalty': f('FLOAT')},
                  },
                },
                {
                  'key': 'off',
                  'inputs': {'required': <String, Object>{}},
                },
              ],
            },
          ],
        },
        'optional': {
          'image': f('IMAGE'),
          'video': f('IMAGE'),
          'audio': f('AUDIO'),
          'thinking': f('BOOLEAN'),
          'use_default_template': f('BOOLEAN'),
          'mtp': [
            ['auto', 'off'],
            <String, Object>{},
          ],
        },
      },
    },
  };
}

Map<String, dynamic> _inputs(Map<String, dynamic> api) =>
    ((api['1'] as Map)['inputs'] as Map).cast<String, dynamic>();

void main() {
  const sampled = <Object?>[
    'a porch',
    512,
    'on',
    0.7,
    64,
    0.95,
    0.05,
    1.05,
    123456,
    'randomize',
    0.5,
    false,
    true,
    'auto',
  ];

  test('seed and presence_penalty land on their own inputs', () {
    final inputs = _inputs(convertComfyUiToApi(_ui(sampled)));
    expect(inputs['sampling_mode.seed'], 123456);
    expect(inputs['sampling_mode.presence_penalty'], 0.5);
    expect(inputs['sampling_mode.repetition_penalty'], 1.05);
  });

  test('with a live object_info the same values land the same way', () {
    final inputs = _inputs(
      convertComfyUiToApi(_ui(sampled), objectInfo: _objectInfo()),
    );
    expect(inputs['prompt'], 'a porch');
    expect(inputs['sampling_mode'], 'on');
    expect(inputs['sampling_mode.seed'], 123456);
    expect(inputs['sampling_mode.presence_penalty'], 0.5);
    expect(inputs['thinking'], false);
    expect(inputs['use_default_template'], true);
    expect(inputs['mtp'], 'auto');
    expect(inputs.containsKey('audio'), isFalse);
  });

  test('sampling off leaves out the sampling widgets', () {
    final inputs = _inputs(
      convertComfyUiToApi(
        _ui(const ['a porch', 512, 'off', true, false, 'auto']),
        objectInfo: _objectInfo(),
      ),
    );
    expect(inputs['sampling_mode'], 'off');
    expect(inputs['thinking'], true);
    expect(inputs['use_default_template'], false);
    expect(inputs['mtp'], 'auto');
    expect(inputs.keys.where((k) => k.startsWith('sampling_mode.')), isEmpty);
  });

  test('the official Qwen-Image 2.1 template converts the same both ways', () {
    final raw = jsonDecode(
      File(
        'test/fixtures/comfy_templates/image_qwen_image_2_1_t2i.json',
      ).readAsStringSync(),
    );
    final ui = (raw as Map).cast<String, dynamic>();
    final plain = convertComfyUiToApi(ui);
    final live = convertComfyUiToApi(ui, objectInfo: _objectInfo());
    Map<String, dynamic> textGenerate(Map<String, dynamic> api) =>
        (api.values.whereType<Map>().firstWhere(
                  (n) => n['class_type'] == 'TextGenerate',
                )['inputs']
                as Map)
            .cast<String, dynamic>();
    for (final api in [plain, live]) {
      final inputs = textGenerate(api);
      expect(inputs['max_length'], 16256);
      expect(inputs['sampling_mode'], 'on');
      expect(inputs['sampling_mode.top_k'], 20);
      expect(inputs['sampling_mode.repetition_penalty'], 1.05);
      expect(inputs['mtp'], 'auto');
    }
  });
}
