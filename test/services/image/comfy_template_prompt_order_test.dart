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

void main() {
  test('official relight and layered-control keep prompt order', () {
    final relight = _adapt('image_qwen_image_edit_2509_relight.json');
    final layered = _adapt('image_qwen_image_layered_control.json');
    final relightTokens = _samplerPromptTokens(relight);
    final layeredTokens = _samplerPromptTokens(layered);
    final dtype = _weightDtype(layered);
    final lines = [
      'relight positive=${relightTokens.positive} negative=${relightTokens.negative}',
      'layered positive=${layeredTokens.positive} negative=${layeredTokens.negative} '
          'weight_dtype=$dtype',
    ];
    // ignore: avoid_print
    print(lines.join('\n'));
    expect(relightTokens.positive, '%PROMPT%');
    expect(relightTokens.negative, '%NEGATIVE%');
    expect(layeredTokens.positive, '%PROMPT%');
    expect(layeredTokens.negative, '%NEGATIVE%');
    expect(dtype, 'fp8_e4m3fn');
  });
}

Map<String, dynamic> _adapt(String name) {
  final file = File('test/fixtures/comfy_templates/$name');
  final raw = jsonDecode(file.readAsStringSync());
  final api = convertComfyUiToApi(Map<String, dynamic>.from(raw as Map));
  return adaptComfyApiWorkflow(api).template;
}

({String positive, String negative}) _samplerPromptTokens(
  Map<String, dynamic> graph,
) {
  Map<dynamic, dynamic>? sampler;
  for (final value in graph.values) {
    if (value is Map && value['class_type'] == 'KSampler') {
      sampler = value;
      break;
    }
  }
  expect(sampler, isNotNull);
  final inputs = sampler!['inputs'] as Map;
  return (
    positive: _promptToken(graph, inputs['positive']),
    negative: _promptToken(graph, inputs['negative']),
  );
}

String _promptToken(Map<String, dynamic> graph, Object? link) {
  final seen = <String>{};
  var current = link;
  while (current is List && current.length == 2) {
    final id = '${current[0]}';
    if (!seen.add(id)) return 'cycle';
    final node = graph[id];
    if (node is! Map) return 'missing:$id';
    final inputs = node['inputs'];
    if (inputs is! Map) return 'no-inputs:$id';
    final type = '${node['class_type']}';
    if (type.startsWith('CLIPTextEncode') || type.startsWith('TextEncode')) {
      final value = inputs['text'] ?? inputs['prompt'];
      return '$value';
    }
    current = inputs['conditioning'] ?? inputs['cond'];
  }
  return 'unresolved:${current.runtimeType}';
}

String _weightDtype(Map<String, dynamic> graph) {
  for (final value in graph.values) {
    if (value is! Map || value['class_type'] != 'UNETLoader') continue;
    final inputs = value['inputs'];
    if (inputs is Map && inputs.containsKey('weight_dtype')) {
      return '${inputs['weight_dtype']}';
    }
  }
  return 'missing';
}
