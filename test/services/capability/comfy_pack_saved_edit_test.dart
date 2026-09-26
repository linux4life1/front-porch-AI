// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/capability/image_reference_resolver.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

void main() {
  test('expression pack uses a ready saved GGUF edit workflow', () async {
    final settings = ImageGenSettings();
    SharedPreferences.setMockInitialValues({
      settings.k('image_gen_backend'): 'comfyui',
      settings.k('comfy_edit_workflow_id'):
          'comfy:userdata:image_qwen_image_2_1_image_edit',
    });
    settings.initializeBase(await SharedPreferences.getInstance(), () {});
    settings.load();
    const workflowId = 'comfy:userdata:image_qwen_image_2_1_image_edit';
    await settings.setComfyEditModelChoice(
      workflowId,
      '%MODEL_DIFFUSION%',
      'edit.gguf',
    );
    await settings.setComfyEditModelChoice(
      workflowId,
      '%MODEL_CLIP%',
      'encoder.gguf',
    );
    await settings.setComfyEditModelChoice(
      workflowId,
      '%MODEL_VAE%',
      'vae.safetensors',
    );
    final live = <String, dynamic>{
      'diffusion': {
        'class_type': 'UnetLoaderGGUFAdvanced',
        'inputs': {'unet_name': 'edit.gguf'},
      },
      'clip': {
        'class_type': 'CLIPLoaderGGUF',
        'inputs': {'clip_name': 'encoder.gguf'},
      },
      'vae': {
        'class_type': 'VAELoader',
        'inputs': {'vae_name': 'vae.safetensors'},
      },
      'image': {
        'class_type': 'LoadImage',
        'inputs': {'image': 'portrait.png'},
      },
      'text': {
        'class_type': 'CLIPTextEncode',
        'inputs': {
          'text': 'change expression',
          'clip': ['clip', 0],
        },
      },
      'canvas': {
        'class_type': 'EmptyLatentImage',
        'inputs': {'width': 1024, 'height': 1024},
      },
    };

    expect(ImageReferenceResolver.packEditMode(settings), isFalse);
    expect(
      ImageReferenceResolver.packEditMode(settings, liveTemplate: live),
      isTrue,
    );
    final request = resolveComfyEditRequest(
      workflowId: workflowId,
      uploadedWorkflowJson: '',
      modelChoices: settings.comfyEditModelChoices,
      liveTemplate: live,
      prompt: 'smile',
      negative: '',
      seed: 7,
      steps: 25,
      cfg: 1,
      denoise: 0.7,
      shift: 1,
      width: 768,
      height: 1024,
    )!;
    final graph = substituteComfyWorkflow(request.template, {
      ...request.values,
      ComfyEditTokens.image: 'uploaded-portrait.png',
    });
    expect(unresolvedComfyTokens(graph), isEmpty);
    expect((graph['canvas'] as Map)['inputs'], {'width': 768, 'height': 1024});
    expect((graph['image'] as Map)['inputs'], {
      'image': 'uploaded-portrait.png',
    });
    await settings.setComfyEditModelChoice(workflowId, '%MODEL_CLIP%', '');
    expect(
      ImageReferenceResolver.packEditMode(settings, liveTemplate: live),
      isFalse,
    );
  });
}
