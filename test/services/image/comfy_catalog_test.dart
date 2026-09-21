// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Catalog merge: Create / pack discovery must list diffusion_models
// (Z-Image Turbo, Flux, Qwen-Image) alongside checkpoints. Live Comfy
// paint cannot run in CI — Mac poke script is in the PR body.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';

void main() {
  group('mergeComfyCreateModels', () {
    test('unions checkpoints and diffusion_models without dupes', () {
      expect(
        mergeComfyCreateModels(
          ['sdxl.safetensors', 'pony.safetensors'],
          ['z_image_turbo_bf16.safetensors', 'sdxl.safetensors'],
        ),
        [
          'sdxl.safetensors',
          'pony.safetensors',
          'z_image_turbo_bf16.safetensors',
        ],
      );
    });

    test('empty diffusion_models still returns checkpoints', () {
      expect(mergeComfyCreateModels(['a.ckpt'], const []), ['a.ckpt']);
    });

    test('object_info checkpoints + UNETLoader is the Create catalog', () {
      final info = {
        'CheckpointLoaderSimple': {
          'input': {
            'required': {
              'ckpt_name': [
                ['sdxl.safetensors'],
                {},
              ],
            },
          },
        },
        'UNETLoader': {
          'input': {
            'required': {
              'unet_name': [
                ['z_image_turbo_bf16.safetensors', 'flux1-dev.safetensors'],
                {},
              ],
            },
          },
        },
      };
      final ckpts = ComfyUiService.optionsFromObjectInfo(
        info,
        'CheckpointLoaderSimple',
        'ckpt_name',
      );
      final unets = ComfyUiService.optionsFromObjectInfo(
        info,
        'UNETLoader',
        'unet_name',
      );
      expect(
        mergeComfyCreateModels(ckpts, unets),
        containsAll([
          'sdxl.safetensors',
          'z_image_turbo_bf16.safetensors',
          'flux1-dev.safetensors',
        ]),
      );
    });

    test('ZIT-only install is not an empty catalog', () {
      final cat = ComfyFileCatalog(
        diffusionModels: ['z_image_turbo_bf16.safetensors'],
      );
      expect(cat.checkpoints, isEmpty);
      expect(cat.createDiscovery, ['z_image_turbo_bf16.safetensors']);
    });
  });

  group('comfySlotEmptyMessage', () {
    test('names the drawer so wrong-family is distinct from empty', () {
      expect(
        comfySlotEmptyMessage(kComfyDiffusionSlot),
        contains('diffusion_models'),
      );
      expect(
        comfySlotEmptyMessage(kSdCreatePreset.modelSlots.first),
        contains('checkpoints'),
      );
    });
  });
}
