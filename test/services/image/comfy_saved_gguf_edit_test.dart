// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';

void main() {
  test('saved and built-in workflows with the same name stay distinct', () {
    const saved = ComfyTemplateEntry(
      name: 'image_qwen_image_2_1_image_edit',
      title: 'Qwen edit',
      source: 'userdata',
    );
    const builtIn = ComfyTemplateEntry(
      name: 'image_qwen_image_2_1_image_edit',
      title: 'Qwen edit',
    );
    expect(saved.pickerId, isNot(builtIn.pickerId));
    expect(comfyTemplateNameFor(saved.pickerId), saved.name);
    expect(comfyTemplatePrefersUserdata(saved.pickerId), isTrue);
    expect(comfyTemplatePrefersUserdata(builtIn.pickerId), isFalse);
    expect(
      comfyTemplatePrefersUserdata('comfy:image_qwen_image_2_1_image_edit'),
      isTrue,
    );
  });

  test('saved GGUF edit workflow fills its loader slots and edit inputs', () {
    final request = resolveComfyEditRequest(
      workflowId: 'comfy:userdata:qwen_edit',
      uploadedWorkflowJson: '',
      liveTemplate: {
        '1': {
          'class_type': 'LoadImage',
          'inputs': {'image': 'reference.png'},
        },
        '2': {
          'class_type': 'CLIPLoaderGGUF',
          'inputs': {'clip_name': 'encoder.gguf', 'type': 'qwen_image'},
        },
        '3': {
          'class_type': 'UnetLoaderGGUFAdvanced',
          'inputs': {'unet_name': 'diffusion.gguf'},
        },
        '4': {
          'class_type': 'TextEncodeQwenImage21',
          'inputs': {'prompt': 'Edit this', 'negative_prompt': 'bad'},
        },
      },
      modelChoices: {
        'comfy:userdata:qwen_edit/%MODEL_CLIP%': 'chosen-encoder.gguf',
        'comfy:userdata:qwen_edit/%MODEL_DIFFUSION%': 'chosen-diffusion.gguf',
      },
      prompt: 'Remove the towels',
      negative: '',
      seed: 1,
      steps: 20,
      cfg: 4,
      denoise: 1,
      shift: 1,
    );
    expect(request, isNotNull);
    expect(request!.values['%MODEL_CLIP%'], 'chosen-encoder.gguf');
    expect(request.values['%MODEL_DIFFUSION%'], 'chosen-diffusion.gguf');
    final graph = substituteComfyWorkflow(request.template, {
      ...request.values,
      ComfyEditTokens.image: 'uploaded.png',
    });
    expect(unresolvedComfyTokens(graph), isEmpty);
  });
}
