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

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';

/// Real weight names from the local Comfy folders. Override with
/// GGUF_DIFFUSION, GGUF_CLIP, and GGUF_LORA when the files differ.
const _kDiffusion = 'z-image-turbo-Q5_K_M.gguf';
const _kClip = 'Qwen3-4B-Q2_K.gguf';
const _kLora = 'z-image-turbo-realism.safetensors';
const _kVae = 'ae.safetensors';

void main() {
  test('GGUF loaders and the LoRA splice keep the downloaded filenames', () {
    final diffusion = Platform.environment['GGUF_DIFFUSION'] ?? _kDiffusion;
    final clip = Platform.environment['GGUF_CLIP'] ?? _kClip;
    final loraName = Platform.environment['GGUF_LORA'] ?? _kLora;
    final vae = Platform.environment['GGUF_VAE'] ?? _kVae;
    final lines = <String>[];

    final plain = _filledCreate(
      unetType: 'UnetLoaderGGUF',
      unetWidgets: [diffusion],
      diffusion: diffusion,
      clip: clip,
      vae: vae,
      seed: 31021,
    );
    lines.add(_loaderLine(plain, 'UnetLoaderGGUF'));
    lines.add(_loaderLine(plain, 'CLIPLoaderGGUF'));
    expect(_input(plain, 'UnetLoaderGGUF', 'unet_name'), diffusion);
    expect(_input(plain, 'CLIPLoaderGGUF', 'clip_name'), clip);
    expect(_input(plain, 'VAELoader', 'vae_name'), vae);

    final advanced = _filledCreate(
      unetType: 'UnetLoaderGGUFAdvanced',
      unetWidgets: [diffusion, 'default', 'default', false],
      diffusion: diffusion,
      clip: clip,
      vae: vae,
      seed: 31023,
    );
    lines.add(_loaderLine(advanced, 'UnetLoaderGGUFAdvanced'));
    expect(_input(advanced, 'UnetLoaderGGUFAdvanced', 'unet_name'), diffusion);
    expect(
      _input(advanced, 'UnetLoaderGGUFAdvanced', 'dequant_dtype'),
      'default',
    );

    _expectMultiClip(
      lines,
      classType: 'DualCLIPLoaderGGUF',
      widgets: [clip, clip, 'flux'],
      clip: clip,
      count: 2,
    );
    _expectMultiClip(
      lines,
      classType: 'TripleCLIPLoaderGGUF',
      widgets: [clip, clip, clip],
      clip: clip,
      count: 3,
    );
    _expectMultiClip(
      lines,
      classType: 'QuadrupleCLIPLoaderGGUF',
      widgets: [clip, clip, clip, clip],
      clip: clip,
      count: 4,
    );

    final adapted = _adaptCreate(
      unetType: 'UnetLoaderGGUF',
      unetWidgets: [diffusion],
      clip: clip,
      vae: vae,
    );
    final spliced = spliceComfyLoraChain(
      adapted.template,
      loras: [(name: loraName, weight: 0.8)],
      modelNodeId: adapted.modelNodeId,
      clipNodeId: adapted.clipNodeId,
      clipOutputIndex: adapted.clipOutputIndex,
    );
    final loraGraph = substituteComfyWorkflow(spliced, {
      ..._fillValues(diffusion: diffusion, clip: clip, vae: vae, seed: 31022),
    });
    final lora = (loraGraph['lora'] as Map)['inputs'] as Map;
    expect((loraGraph['lora'] as Map)['class_type'], 'LoraLoader');
    expect(lora['lora_name'], loraName);
    expect(lora['strength_model'], isNot(0));
    expect(lora['strength_model'], 0.8);
    expect(lora['model'], [adapted.modelNodeId, 0]);
    expect(lora['clip'], [adapted.clipNodeId, adapted.clipOutputIndex]);
    expect(_input(loraGraph, 'ModelSamplingAuraFlow', 'model'), ['lora', 0]);
    expect(_input(loraGraph, 'CLIPTextEncode', 'clip'), ['lora', 1]);
    expect(_input(loraGraph, 'UnetLoaderGGUF', 'unet_name'), diffusion);
    expect(_input(loraGraph, 'CLIPLoaderGGUF', 'clip_name'), clip);
    lines.add(
      'LORA LoraLoader lora_name=$loraName strength_model=${lora['strength_model']} '
      'model=${adapted.modelNodeId} clip=${adapted.clipNodeId}',
    );

    final dir = Platform.environment['GGUF_GRAPH_DIR'];
    if (dir != null && dir.isNotEmpty) {
      Directory(dir).createSync(recursive: true);
      File('$dir/plain.json').writeAsStringSync(_encode(plain));
      File('$dir/lora.json').writeAsStringSync(_encode(loraGraph));
      File('$dir/advanced.json').writeAsStringSync(_encode(advanced));
    }
    // ignore: avoid_print
    print(lines.join('\n'));
  });
}

void _expectMultiClip(
  List<String> lines, {
  required String classType,
  required List<Object?> widgets,
  required String clip,
  required int count,
}) {
  final api = convertComfyUiToApi({
    'nodes': [
      {
        'id': 1,
        'type': classType,
        'inputs': <Object>[],
        'outputs': <Object>[],
        'widgets_values': widgets,
      },
    ],
    'links': <Object>[],
  });
  final adapted = adaptComfyApiWorkflow(api);
  final values = <String, Object?>{
    for (var i = 1; i <= count; i++) '%MODEL_CLIP$i%': clip,
  };
  final filled = substituteComfyWorkflow(adapted.template, values);
  final inputs = (filled['1'] as Map)['inputs'] as Map;
  expect(
    adapted.slots.where((slot) => slot.loaderClass == classType),
    hasLength(count),
  );
  final names = <String>[];
  for (var i = 1; i <= count; i++) {
    expect(inputs['clip_name$i'], clip);
    expect(
      adapted.slots.where((slot) => slot.inputName == 'clip_name$i'),
      hasLength(1),
    );
    names.add('clip_name$i=$clip');
  }
  lines.add('LOADER $classType slots=$count ${names.join(' ')}');
}

Map<String, dynamic> _filledCreate({
  required String unetType,
  required List<Object?> unetWidgets,
  required String diffusion,
  required String clip,
  required String vae,
  required int seed,
}) {
  final adapted = _adaptCreate(
    unetType: unetType,
    unetWidgets: unetWidgets,
    clip: clip,
    vae: vae,
  );
  return substituteComfyWorkflow(
    adapted.template,
    _fillValues(diffusion: diffusion, clip: clip, vae: vae, seed: seed),
  );
}

AdaptedComfyGraph _adaptCreate({
  required String unetType,
  required List<Object?> unetWidgets,
  required String clip,
  required String vae,
}) {
  final api = convertComfyUiToApi(
    _createUi(
      unetType: unetType,
      unetWidgets: unetWidgets,
      clip: clip,
      vae: vae,
    ),
  );
  return adaptComfyApiWorkflow(api);
}

Map<String, Object?> _fillValues({
  required String diffusion,
  required String clip,
  required String vae,
  required int seed,
}) {
  return {
    '%MODEL_DIFFUSION%': diffusion,
    '%MODEL_CLIP%': clip,
    '%MODEL_VAE%': vae,
    '%PROMPT%': 'a red ceramic cup on a wooden table',
    '%SEED%': seed,
    '%STEPS%': 8,
    '%CFG%': 1,
    '%DENOISE%': 1.0,
    '%SAMPLER%': 'res_multistep',
    '%SCHEDULER%': 'simple',
    '%SHIFT%': 3,
    '%WIDTH%': 1024,
    '%HEIGHT%': 1024,
  };
}

Map<String, dynamic> _createUi({
  required String unetType,
  required List<Object?> unetWidgets,
  required String clip,
  required String vae,
}) {
  Map<String, dynamic> node(
    int id,
    String type,
    List<Object?> widgets, {
    List<Map<String, Object?>> inputs = const [],
  }) {
    return {
      'id': id,
      'type': type,
      'widgets_values': widgets,
      'inputs': inputs,
      'outputs': <Object>[],
    };
  }

  return {
    'nodes': [
      node(1, unetType, unetWidgets),
      node(2, 'CLIPLoaderGGUF', [clip, 'lumina2']),
      node(3, 'VAELoader', [vae]),
      node(
        4,
        'CLIPTextEncode',
        ['a red ceramic cup on a wooden table'],
        inputs: [
          {'name': 'clip', 'link': 1},
        ],
      ),
      node(
        5,
        'ConditioningZeroOut',
        const [],
        inputs: [
          {'name': 'conditioning', 'link': 2},
        ],
      ),
      node(
        6,
        'ModelSamplingAuraFlow',
        const [3],
        inputs: [
          {'name': 'model', 'link': 3},
        ],
      ),
      node(7, 'EmptySD3LatentImage', const [1024, 1024, 1]),
      node(
        8,
        'KSampler',
        const [1, 'randomize', 8, 1, 'res_multistep', 'simple', 1],
        inputs: [
          {'name': 'model', 'link': 4},
          {'name': 'positive', 'link': 5},
          {'name': 'negative', 'link': 6},
          {'name': 'latent_image', 'link': 7},
        ],
      ),
      node(
        9,
        'VAEDecode',
        const [],
        inputs: [
          {'name': 'samples', 'link': 8},
          {'name': 'vae', 'link': 9},
        ],
      ),
      node(
        10,
        'SaveImage',
        const ['fpai-gguf'],
        inputs: [
          {'name': 'images', 'link': 10},
        ],
      ),
    ],
    'links': [
      [1, 2, 0, 4, 0, 'CLIP'],
      [2, 4, 0, 5, 0, 'CONDITIONING'],
      [3, 1, 0, 6, 0, 'MODEL'],
      [4, 6, 0, 8, 0, 'MODEL'],
      [5, 4, 0, 8, 1, 'CONDITIONING'],
      [6, 5, 0, 8, 2, 'CONDITIONING'],
      [7, 7, 0, 8, 3, 'LATENT'],
      [8, 8, 0, 9, 0, 'LATENT'],
      [9, 3, 0, 9, 1, 'VAE'],
      [10, 9, 0, 10, 0, 'IMAGE'],
    ],
  };
}

String _loaderLine(Map<String, dynamic> graph, String classType) {
  final inputs = _node(graph, classType)['inputs'] as Map;
  final named = inputs.entries
      .where((entry) => entry.value is! List)
      .map((entry) => '${entry.key}=${entry.value}')
      .join(' ');
  return 'LOADER $classType $named';
}

Object? _input(Map<String, dynamic> graph, String classType, String key) {
  return (_node(graph, classType)['inputs'] as Map)[key];
}

Map<dynamic, dynamic> _node(Map<String, dynamic> graph, String classType) {
  for (final value in graph.values) {
    if (value is Map && value['class_type'] == classType) {
      return value;
    }
  }
  fail('missing $classType');
}

String _encode(Map<String, dynamic> graph) =>
    const JsonEncoder.withIndent('  ').convert(graph);
