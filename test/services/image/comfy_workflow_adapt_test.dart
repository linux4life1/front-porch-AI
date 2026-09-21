// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Token/slot adapter over stock Comfy API JSON (same fill as Edit BYO).

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/image.dart';

void main() {
  test('adapt tokenizes prompt, seed, size, and model drawers', () {
    final adapted = adaptComfyApiWorkflow(kComfyStarterZit);
    expect(
      adapted.slots.map((s) => s.folderHint).toSet(),
      containsAll(['diffusion_models', 'text_encoders', 'vae']),
    );
    expect(adapted.template.toString(), contains('%PROMPT%'));
    expect(adapted.template.toString(), contains('%SEED%'));
    expect(adapted.template.toString(), contains('%WIDTH%'));
    expect(adapted.requiredNodes, contains('UNETLoader'));
    final clip = adapted.template.values.cast<Map>().firstWhere(
      (n) => n['class_type'] == 'CLIPLoader',
    );
    expect(clip['inputs']['type'], 'lumina2');
  });

  test('Flux keeps KSampler cfg at 1 and maps %CFG% onto FluxGuidance', () {
    final adapted = adaptComfyApiWorkflow(kComfyStarterFlux);
    final sampler = adapted.template.values.cast<Map>().firstWhere(
      (n) => n['class_type'] == 'KSampler',
    );
    expect(sampler['inputs']['cfg'], 1.0);
    final guide = adapted.template.values.cast<Map>().firstWhere(
      (n) => n['class_type'] == 'FluxGuidance',
    );
    expect(guide['inputs']['guidance'], '%CFG%');
  });

  test('already-tokened BYO graph is not double-wrapped', () {
    final byo = {
      'pos': {
        'class_type': 'CLIPTextEncode',
        'inputs': {
          'text': '%PROMPT%',
          'clip': ['c', 0],
        },
      },
    };
    final adapted = adaptComfyApiWorkflow(byo);
    expect(adapted.template['pos']['inputs']['text'], '%PROMPT%');
  });

  test('template index keeps ZIT and drops ControlNet / paid API', () {
    final all = parseComfyTemplateIndex([
      {
        'templates': [
          {
            'name': 'image_z_image_turbo',
            'title': 'Z-Image-Turbo: Text to Image',
            'tags': ['Image', 'Text to Image'],
          },
          {
            'name': 'image_qwen_image_instantx_controlnet',
            'title': 'Qwen ControlNet',
            'tags': ['Text to Image', 'ControlNet'],
          },
          {
            'name': 'api_nano_banana_pro',
            'title': 'Nano Banana Pro',
            'tags': ['API', 'Image Edit'],
            'openSource': false,
          },
          {
            'name': 'image_qwen_image_edit',
            'title': 'Qwen-Image-Edit',
            'tags': ['Image Edit'],
          },
        ],
      },
    ]);
    expect(comfyCreateTemplates(all).map((e) => e.name), [
      'image_z_image_turbo',
    ]);
    expect(comfyEditTemplates(all).map((e) => e.name), [
      'image_qwen_image_edit',
    ]);
  });
}
