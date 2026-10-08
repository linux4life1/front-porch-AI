// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';

void main() {
  const graph = <String, dynamic>{
    'encoder': {
      'class_type': 'CLIPLoaderGGUF',
      'inputs': {'clip_name': 'qwen3vl_8b-Q4_K_M.gguf'},
    },
  };
  for (final raw in [
    '127.0.0.1:8188',
    'http://127.0.0.1:8188/',
    '  127.0.0.1:8188///  ',
  ]) {
    test('acknowledgement and submit URL agree for $raw', () async {
      var inspections = 0;
      final gate = City96Gate(
        locate: (_) async {
          inspections++;
          return null;
        },
      );
      gate.setExistingSupport(raw, confirmed: true);
      final submitUrl = ComfyUiService.ensureHttpScheme(raw);
      expect(
        (await gate.check(comfyUrl: raw, graph: graph)).state,
        City96State.ready,
      );
      await gate.ensureOrThrow(comfyUrl: submitUrl, graph: graph);
      expect(inspections, 0);
      for (final different in [
        'https://127.0.0.1:8188',
        'http://127.0.0.1:8189',
        '$submitUrl/path',
      ]) {
        expect(gate.hasExistingSupport(different), isFalse);
      }
      gate.setExistingSupport('$submitUrl/', confirmed: false);
      expect(gate.hasExistingSupport(raw), isFalse);
      await expectLater(
        gate.ensureOrThrow(comfyUrl: submitUrl, graph: graph),
        throwsA(isA<ComfyLoaderUpdateNeeded>()),
      );
    });
  }
}
