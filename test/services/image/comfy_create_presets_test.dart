// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Create families are pointers at Comfy templates + the BYO token
// adapter — not Porch-authored node graphs. Live paint cannot run in CI.
// Mac poke: Image Studio → Comfy → pick each family, Generate, then
// img2img; Expression pack Edit-first, I2I fallback with ZIT selected.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/comfy_workflow.dart';
import 'package:front_porch_ai/services/image/image.dart';

void main() {
  group('family routing', () {
    test('ids are unique and cover SD + Flux + Qwen + ZIT', () {
      final ids = kComfyCreatePresets.map((p) => p.id).toSet();
      expect(ids, containsAll(['sd', 'flux', 'qwen_image', 'z_image_turbo']));
      expect(ids.length, kComfyCreatePresets.length);
      expect(comfyCreatePresetById('flux'), same(kFluxCreatePreset));
      expect(comfyCreatePresetById('nope'), isNull);
    });

    test('SD uses the checkpoint builder; others point at Comfy templates', () {
      expect(kSdCreatePreset.usesCheckpointBuilder, isTrue);
      expect(kFluxCreatePreset.comfyTemplateName, 'flux_schnell');
      expect(kQwenCreatePreset.comfyTemplateName, 'image_qwen_image');
      expect(kZitCreatePreset.comfyTemplateName, 'image_z_image_turbo');
      expect(kFluxCreatePreset.usesCheckpointBuilder, isFalse);
    });

    test('ZIT and Qwen read diffusion_models, not checkpoints', () {
      for (final p in [
        kZitCreatePreset,
        kQwenCreatePreset,
        kFluxCreatePreset,
      ]) {
        expect(
          p.modelSlots.any((s) => s.folderHint == 'diffusion_models'),
          isTrue,
          reason: '${p.id} must list a diffusion_models slot',
        );
        expect(
          p.modelSlots.any((s) => s.loaderClass == 'CheckpointLoaderSimple'),
          isFalse,
        );
      }
    });

    test('Krea rides the Flux stove (one create family, not a new graph)', () {
      expect(kFluxCreatePreset.label.toLowerCase(), contains('krea'));
      expect(kFluxCreatePreset.id, 'flux');
    });
  });

  group('resolveComfyCreateRequest', () {
    test('SD slot + fallback fill the checkpoint builder', () {
      final viaSlot = resolveComfyCreateRequest(
        workflowId: 'sd',
        uploadedWorkflowJson: '',
        modelChoices: const {'sd/%MODEL_CHECKPOINT%': 'pony.safetensors'},
        prompt: 'p',
        negative: 'n',
        seed: 1,
        steps: 20,
        cfg: 7,
        denoise: 1,
        shift: 3,
        width: 1024,
        height: 1024,
      );
      expect(viaSlot, isNotNull);
      expect(viaSlot!.useCheckpointBuilder, isTrue);
      expect(viaSlot.checkpoint, 'pony.safetensors');

      final viaFallback = resolveComfyCreateRequest(
        workflowId: 'sd',
        uploadedWorkflowJson: '',
        modelChoices: const {},
        prompt: 'p',
        negative: 'n',
        seed: 1,
        steps: 20,
        cfg: 7,
        denoise: 1,
        shift: 3,
        width: 512,
        height: 768,
        checkpointFallback: 'sdxl.safetensors',
      );
      expect(viaFallback!.checkpoint, 'sdxl.safetensors');
    });

    test('ZIT starter adapts UNET + lumina2 CLIP + VAE + EmptySD3', () {
      final r = resolveComfyCreateRequest(
        workflowId: 'z_image_turbo',
        uploadedWorkflowJson: '',
        modelChoices: const {
          'z_image_turbo/%MODEL_DIFFUSION%': 'z_image_turbo_bf16.safetensors',
          'z_image_turbo/%MODEL_CLIP%': 'qwen_3_4b.safetensors',
          'z_image_turbo/%MODEL_VAE%': 'ae.safetensors',
        },
        prompt: 'a porch',
        negative: '',
        seed: 9,
        steps: 8,
        cfg: 1,
        denoise: 1,
        shift: 3.1,
        width: 1104,
        height: 1472,
      );
      expect(r, isNotNull);
      expect(r!.useCheckpointBuilder, isFalse);
      final filled = substituteComfyWorkflow(r.template, r.values);
      expect(unresolvedComfyTokens(filled), isEmpty);
      final unet = filled.values.cast<Map>().firstWhere(
        (n) => n['class_type'] == 'UNETLoader',
      );
      expect(unet['inputs']['unet_name'], 'z_image_turbo_bf16.safetensors');
      final clip = filled.values.cast<Map>().firstWhere(
        (n) => n['class_type'] == 'CLIPLoader',
      );
      expect(clip['inputs']['type'], 'lumina2');
      expect(clip['inputs']['clip_name'], 'qwen_3_4b.safetensors');
      final latent = filled.values.cast<Map>().firstWhere(
        (n) => n['class_type'] == 'EmptySD3LatentImage',
      );
      expect(latent['inputs']['width'], 1104);
    });

    test('unpicked ZIT slot stays unresolved (pack cannot silently run)', () {
      final r = resolveComfyCreateRequest(
        workflowId: 'z_image_turbo',
        uploadedWorkflowJson: '',
        modelChoices: const {},
        prompt: 'x',
        negative: '',
        seed: 1,
        steps: 8,
        cfg: 1,
        denoise: 1,
        shift: 3,
        width: 64,
        height: 64,
      );
      final filled = substituteComfyWorkflow(r!.template, r.values);
      expect(unresolvedComfyTokens(filled), contains('%MODEL_DIFFUSION%'));
      expect(
        comfyCreateReady(
          workflowId: 'z_image_turbo',
          uploadedWorkflowJson: '',
          modelChoices: const {},
        ),
        isFalse,
      );
    });

    test('unknown id / empty upload → null', () {
      expect(
        resolveComfyCreateRequest(
          workflowId: 'nope',
          uploadedWorkflowJson: '',
          modelChoices: const {},
          prompt: 'x',
          negative: '',
          seed: 1,
          steps: 1,
          cfg: 1,
          denoise: 1,
          shift: 1,
          width: 8,
          height: 8,
        ),
        isNull,
      );
      expect(
        resolveComfyCreateRequest(
          workflowId: kComfyUploadedWorkflowId,
          uploadedWorkflowJson: '',
          modelChoices: const {},
          prompt: 'x',
          negative: '',
          seed: 1,
          steps: 1,
          cfg: 1,
          denoise: 1,
          shift: 1,
          width: 8,
          height: 8,
        ),
        isNull,
      );
    });

    test('live Comfy template JSON wins over the bundled starter', () {
      final live = {
        '1': {
          'class_type': 'UNETLoader',
          'inputs': {
            'unet_name': 'from-comfy.safetensors',
            'weight_dtype': 'default',
          },
        },
        '2': {
          'class_type': 'CLIPTextEncode',
          'inputs': {
            'text': 'stock prompt',
            'clip': ['1', 0],
          },
        },
        '3': {
          'class_type': 'KSampler',
          'inputs': {
            'seed': 0,
            'steps': 4,
            'cfg': 1,
            'sampler_name': 'euler',
            'scheduler': 'simple',
            'denoise': 1,
            'model': ['1', 0],
            'positive': ['2', 0],
            'negative': ['2', 0],
            'latent_image': ['1', 0],
          },
        },
      };
      final r = resolveComfyCreateRequest(
        workflowId: 'z_image_turbo',
        uploadedWorkflowJson: '',
        modelChoices: const {
          'z_image_turbo/%MODEL_DIFFUSION%': 'user-pick.safetensors',
        },
        prompt: 'p',
        negative: '',
        seed: 1,
        steps: 4,
        cfg: 1,
        denoise: 1,
        shift: 1,
        width: 8,
        height: 8,
        liveTemplate: live,
      );
      expect(r, isNotNull);
      expect(
        r!.template.values.whereType<Map>().any(
          (n) => n['class_type'] == 'CLIPLoader',
        ),
        isFalse,
        reason: 'live template must replace the ZIT starter, not merge',
      );
      final filled = substituteComfyWorkflow(r.template, r.values);
      final unet = filled.values.cast<Map>().firstWhere(
        (n) => n['class_type'] == 'UNETLoader',
      );
      expect(unet['inputs']['unet_name'], 'user-pick.safetensors');
    });
  });

  group('SD path still matches ComfyWorkflow builders', () {
    test('txt2img checkpoint graph is unchanged', () {
      final g = ComfyWorkflow.buildTxt2ImgWorkflow(
        model: 'sdxl.safetensors',
        prompt: 'porch',
        negativePrompt: 'blurry',
        width: 1024,
        height: 1024,
        steps: 20,
        cfgScale: 7,
        seed: 3,
        samplerName: 'euler',
        scheduler: 'normal',
      );
      expect(g['ckpt']['class_type'], 'CheckpointLoaderSimple');
      expect(g['ckpt']['inputs']['ckpt_name'], 'sdxl.safetensors');
      expect(g['latent']['class_type'], 'EmptyLatentImage');
      expect(g['sampler']['inputs']['denoise'], 1.0);
    });
  });

  group('img2img + LoRA knobs on adapted stock graphs', () {
    test('Flux img2img replaces EmptyLatent with VAEEncode', () {
      final adapted = adaptComfyApiWorkflow(kComfyStarterFlux);
      final img = applyCreateImg2Img(
        adapted.template,
        vaeNodeId: adapted.vaeNodeId,
      );
      expect(img['init_image']['class_type'], 'LoadImage');
      expect(
        img.values.whereType<Map>().any((n) => n['class_type'] == 'VAEEncode'),
        isTrue,
      );
    });

    test('ZIT LoRA splices between UNET/CLIP and consumers', () {
      final adapted = adaptComfyApiWorkflow(kComfyStarterZit);
      final g = spliceComfyLora(
        adapted.template,
        loraName: 'style.safetensors',
        loraWeight: 0.7,
        modelNodeId: adapted.modelNodeId,
        clipNodeId: adapted.clipNodeId,
      );
      expect(g['lora']['inputs']['lora_name'], 'style.safetensors');
      expect(g['lora']['inputs']['model'], [adapted.modelNodeId, 0]);
    });
  });

  group('edit presets did not regress', () {
    test('Qwen-Image-Edit and Flux Kontext still resolve', () {
      expect(kComfyEditPresets.map((p) => p.id), [
        'qwen_image_edit',
        'flux_kontext',
      ]);
      final r = resolveComfyEditRequest(
        workflowId: 'qwen_image_edit',
        uploadedWorkflowJson: '',
        modelChoices: const {
          'qwen_image_edit/%MODEL_DIFFUSION%': 'u.safetensors',
          'qwen_image_edit/%MODEL_CLIP%': 'c.safetensors',
          'qwen_image_edit/%MODEL_VAE%': 'v.safetensors',
        },
        prompt: 'coat',
        negative: '',
        seed: 1,
        steps: 20,
        cfg: 3.5,
        denoise: 1,
        shift: 3,
      );
      expect(r, isNotNull);
      final filled = substituteComfyWorkflow(r!.template, {
        ...r.values,
        ComfyEditTokens.image: 'ref.png',
      });
      expect(unresolvedComfyTokens(filled), isEmpty);
    });
  });
}
