// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for ComfyUiService's pure parts: the bundled txt2img workflow builder
// (node wiring, LoRA splicing), sampler-name normalization (A1111-style names
// shared across backends → ComfyUI-native), scheduler selection, and
// /object_info option extraction. HTTP paths are thin wrappers and are
// exercised against a live server manually.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/comfy_workflow.dart';

void main() {
  group('buildTxt2ImgWorkflow', () {
    Map<String, dynamic> build({String lora = ''}) =>
        ComfyWorkflow.buildTxt2ImgWorkflow(
          model: 'sdxl.safetensors',
          prompt: 'a porch at dusk',
          negativePrompt: 'blurry',
          width: 1024,
          height: 1216,
          steps: 25,
          cfgScale: 6.5,
          seed: 1234,
          samplerName: 'euler_ancestral',
          scheduler: 'karras',
          loraName: lora,
          loraWeight: 0.7,
        );

    test(
      'wires the plain graph: checkpoint → prompts/sampler → decode → save',
      () {
        final g = build();
        expect(g.containsKey('lora'), isFalse);
        expect(g['ckpt']['inputs']['ckpt_name'], 'sdxl.safetensors');
        expect(g['pos']['inputs']['text'], 'a porch at dusk');
        expect(g['pos']['inputs']['clip'], ['ckpt', 1]);
        expect(g['neg']['inputs']['text'], 'blurry');
        final s = g['sampler']['inputs'] as Map;
        expect(s['model'], ['ckpt', 0]);
        expect(s['seed'], 1234);
        expect(s['steps'], 25);
        expect(s['cfg'], 6.5);
        expect(s['sampler_name'], 'euler_ancestral');
        expect(s['scheduler'], 'karras');
        expect(g['latent']['inputs']['width'], 1024);
        expect(g['latent']['inputs']['height'], 1216);
        expect(g['decode']['inputs']['vae'], ['ckpt', 2]);
        expect(g['save']['inputs']['images'], ['decode', 0]);
      },
    );

    test(
      'a LoRA splices LoraLoader between checkpoint and sampler/prompts',
      () {
        final g = build(lora: 'style.safetensors');
        final lora = g['lora']['inputs'] as Map;
        expect(lora['lora_name'], 'style.safetensors');
        expect(lora['strength_model'], 0.7);
        expect(lora['strength_clip'], 0.7);
        expect(lora['model'], ['ckpt', 0]);
        // Downstream consumers now read from the LoRA node.
        expect(g['sampler']['inputs']['model'], ['lora', 0]);
        expect(g['pos']['inputs']['clip'], ['lora', 1]);
        expect(g['neg']['inputs']['clip'], ['lora', 1]);
      },
    );
  });

  group('buildImg2ImgWorkflow', () {
    Map<String, dynamic> build({String lora = '', double denoise = 0.55}) =>
        ComfyWorkflow.buildImg2ImgWorkflow(
          model: 'sdxl.safetensors',
          prompt: 'a porch at dusk',
          negativePrompt: 'blurry',
          steps: 25,
          cfgScale: 6.5,
          seed: 1234,
          samplerName: 'euler_ancestral',
          scheduler: 'karras',
          initImageName: 'fpai_ref_123.png',
          denoise: denoise,
          loraName: lora,
          loraWeight: 0.7,
        );

    test('replaces the empty latent with LoadImage → VAEEncode', () {
      final g = build();
      // No txt2img empty latent — the latent now comes from the encoded ref.
      expect(g.containsKey('init_image'), isTrue);
      expect(g['init_image']['class_type'], 'LoadImage');
      expect(g['init_image']['inputs']['image'], 'fpai_ref_123.png');
      expect(g['latent']['class_type'], 'VAEEncode');
      expect(g['latent']['inputs']['pixels'], ['init_image', 0]);
      expect(g['latent']['inputs']['vae'], ['ckpt', 2]);
      // The sampler consumes the encoded latent, not an EmptyLatentImage.
      expect(g['sampler']['inputs']['latent_image'], ['latent', 0]);
    });

    test('KSampler denoises from the reference at the requested strength', () {
      final s = build(denoise: 0.4)['sampler']['inputs'] as Map;
      expect(s['denoise'], 0.4);
      // Everything else matches the txt2img sampler wiring.
      expect(s['seed'], 1234);
      expect(s['steps'], 25);
      expect(s['sampler_name'], 'euler_ancestral');
      expect(s['scheduler'], 'karras');
    });

    test('a LoRA still splices in the same way as txt2img', () {
      final g = build(lora: 'style.safetensors');
      expect(g['lora']['inputs']['lora_name'], 'style.safetensors');
      expect(g['sampler']['inputs']['model'], ['lora', 0]);
      expect(g['pos']['inputs']['clip'], ['lora', 1]);
    });

    test('txt2img graph is unchanged (empty latent, denoise 1.0)', () {
      final g = ComfyWorkflow.buildTxt2ImgWorkflow(
        model: 'm.safetensors',
        prompt: 'p',
        negativePrompt: 'n',
        width: 768,
        height: 768,
        steps: 20,
        cfgScale: 7.0,
        seed: 7,
        samplerName: 'euler',
        scheduler: 'normal',
      );
      expect(g['latent']['class_type'], 'EmptyLatentImage');
      expect(g.containsKey('init_image'), isFalse);
      expect(g['sampler']['inputs']['denoise'], 1.0);
    });
  });

  group('normalizeSampler', () {
    const available = ['euler', 'euler_ancestral', 'dpmpp_2m', 'ddim'];

    test('native names pass through', () {
      expect(
        ComfyUiService.normalizeSampler('dpmpp_2m', available),
        'dpmpp_2m',
      );
    });

    test('A1111-style names map to ComfyUI names', () {
      expect(
        ComfyUiService.normalizeSampler('Euler a', available),
        'euler_ancestral',
      );
      expect(
        ComfyUiService.normalizeSampler('DPM++ 2M Karras', available),
        'dpmpp_2m',
      );
    });

    test('unknown names fall back to euler, then first available', () {
      expect(
        ComfyUiService.normalizeSampler('WeirdSampler', available),
        'euler',
      );
      expect(
        ComfyUiService.normalizeSampler('WeirdSampler', const ['uni_pc']),
        'uni_pc',
      );
    });
  });

  test('schedulerFor maps Karras-flavored names to the karras scheduler', () {
    expect(ComfyUiService.schedulerFor('DPM++ 2M Karras'), 'karras');
    expect(ComfyUiService.schedulerFor('Euler a'), 'normal');
  });

  test('ensureHttpScheme fixes scheme-less addresses and trailing slashes', () {
    expect(
      ComfyUiService.ensureHttpScheme('localhost:8188'),
      'http://localhost:8188',
    );
    expect(
      ComfyUiService.ensureHttpScheme('192.168.1.20:7860/'),
      'http://192.168.1.20:7860',
    );
    expect(
      ComfyUiService.ensureHttpScheme('https://my.server:8443//'),
      'https://my.server:8443',
    );
    expect(ComfyUiService.ensureHttpScheme('  '), '');
  });

  group('optionsFromObjectInfo', () {
    final info = {
      'CheckpointLoaderSimple': {
        'input': {
          'required': {
            'ckpt_name': [
              ['a.safetensors', 'b.ckpt'],
              {'tooltip': 'The name of the checkpoint'},
            ],
          },
        },
      },
      'LoraLoader': {
        'input': {
          'required': {
            'lora_name': [
              ['style.safetensors'],
            ],
          },
        },
      },
      // KSampler exposes both the sampler_name and scheduler enums — the
      // scheduler picker reads the latter (fetchSchedulers → this extraction).
      'KSampler': {
        'input': {
          'required': {
            'sampler_name': [
              ['euler', 'dpmpp_2m'],
            ],
            'scheduler': [
              ['normal', 'karras', 'exponential', 'sgm_uniform'],
            ],
          },
        },
      },
    };

    test('extracts enum options from required inputs', () {
      expect(
        ComfyUiService.optionsFromObjectInfo(
          info,
          'CheckpointLoaderSimple',
          'ckpt_name',
        ),
        ['a.safetensors', 'b.ckpt'],
      );
      expect(
        ComfyUiService.optionsFromObjectInfo(info, 'LoraLoader', 'lora_name'),
        ['style.safetensors'],
      );
      expect(
        ComfyUiService.optionsFromObjectInfo(info, 'KSampler', 'scheduler'),
        ['normal', 'karras', 'exponential', 'sgm_uniform'],
      );
    });

    test('missing node or input → empty (tolerant of server variations)', () {
      expect(
        ComfyUiService.optionsFromObjectInfo(info, 'NoSuchNode', 'x'),
        isEmpty,
      );
      expect(
        ComfyUiService.optionsFromObjectInfo(
          info,
          'CheckpointLoaderSimple',
          'nope',
        ),
        isEmpty,
      );
    });
  });
}
