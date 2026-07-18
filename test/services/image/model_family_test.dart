// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/model_family.dart';

void main() {
  group('detectFromName', () {
    test('recognizes SDXL variants', () {
      expect(ImageModelFamily.detectFromName('dreamshaperXL_v21.safetensors'), ModelFamily.sdxl);
      expect(ImageModelFamily.detectFromName('some_sdxl_lora.safetensors'), ModelFamily.sdxl);
      expect(ImageModelFamily.detectFromName('illustrious_style.safetensors'), ModelFamily.sdxl);
      expect(ImageModelFamily.detectFromName('add_detail_sdxl_lora_f16.ckpt'), ModelFamily.sdxl);
    });

    test('recognizes SD1.5', () {
      expect(ImageModelFamily.detectFromName('epi_noiseoffset_sd15.safetensors'), ModelFamily.sd15);
      expect(ImageModelFamily.detectFromName('anime_lineart_sd_v1.5_lora_f16.ckpt'), ModelFamily.sd15);
      expect(ImageModelFamily.detectFromName('detailer_v1-5.safetensors'), ModelFamily.sd15);
    });

    test('recognizes Pony, Flux, SD3', () {
      expect(ImageModelFamily.detectFromName('pony_diffusion_v6.safetensors'), ModelFamily.pony);
      expect(ImageModelFamily.detectFromName('flux_watercolor_lora.safetensors'), ModelFamily.flux);
      expect(ImageModelFamily.detectFromName('sd3_medium_lora.safetensors'), ModelFamily.sd3);
    });

    test('Pony beats SDXL when both tokens present (Pony is more specific)', () {
      expect(ImageModelFamily.detectFromName('pony_realism_xl.safetensors'), ModelFamily.pony);
    });

    test('unrecognized names are unknown', () {
      expect(ImageModelFamily.detectFromName('grandmas_recipe_lora_f16.ckpt'), ModelFamily.unknown);
      expect(ImageModelFamily.detectFromName('my_custom_style_v3.safetensors'), ModelFamily.unknown);
    });
  });

  group('detectFromMetadata', () {
    test('reads ss_base_model_version', () {
      expect(ImageModelFamily.detectFromMetadata({'ss_base_model_version': 'sdxl_base_v1-0'}), ModelFamily.sdxl);
      expect(ImageModelFamily.detectFromMetadata({'ss_base_model_version': 'sd_v1'}), ModelFamily.sd15);
    });

    test('reads modelspec.architecture', () {
      expect(ImageModelFamily.detectFromMetadata({'modelspec.architecture': 'flux-1-dev/lora'}), ModelFamily.flux);
      expect(ImageModelFamily.detectFromMetadata({'modelspec.architecture': 'stable-diffusion-xl-v1-base/lora'}), ModelFamily.sdxl);
      expect(ImageModelFamily.detectFromMetadata({'modelspec.architecture': 'stable-diffusion-v1/lora'}), ModelFamily.sd15);
    });

    test('empty/unrecognized metadata is unknown (SD2 not force-classified)', () {
      expect(ImageModelFamily.detectFromMetadata(const {}), ModelFamily.unknown);
      expect(ImageModelFamily.detectFromMetadata({'ss_base_model_version': 'sd_v2'}), ModelFamily.unknown);
    });
  });

  group('classifyLora — metadata wins, name is the floor, Pony override', () {
    test('metadata authoritative and marked fromMetadata', () {
      final o = ImageModelFamily.classifyLora('mystery.safetensors', metadata: {'ss_base_model_version': 'sdxl_base_v1-0'});
      expect(o.family, ModelFamily.sdxl);
      expect(o.familyFromMetadata, isTrue);
    });

    test('falls back to name when no metadata, not fromMetadata', () {
      final o = ImageModelFamily.classifyLora('anime_sd15.safetensors');
      expect(o.family, ModelFamily.sd15);
      expect(o.familyFromMetadata, isFalse);
    });

    test('name "pony" overrides SDXL metadata and is treated as a guess', () {
      final o = ImageModelFamily.classifyLora('pony_style.safetensors', metadata: {'ss_base_model_version': 'sdxl_base_v1-0'});
      expect(o.family, ModelFamily.pony);
      expect(o.familyFromMetadata, isFalse);
    });
  });

  group('compatibility', () {
    test('same family matches', () {
      expect(ImageModelFamily.compatibility(ModelFamily.sdxl, ModelFamily.sdxl, metadataBacked: true), LoraCompat.match);
    });

    test('metadata-backed hard mismatch is certain', () {
      expect(ImageModelFamily.compatibility(ModelFamily.sd15, ModelFamily.sdxl, metadataBacked: true), LoraCompat.certain);
    });

    test('name-only hard mismatch is only likely (never hidden)', () {
      expect(ImageModelFamily.compatibility(ModelFamily.sd15, ModelFamily.sdxl, metadataBacked: false), LoraCompat.likely);
    });

    test('Pony <-> SDXL is always likely, even metadata-backed', () {
      expect(ImageModelFamily.compatibility(ModelFamily.pony, ModelFamily.sdxl, metadataBacked: true), LoraCompat.likely);
      expect(ImageModelFamily.compatibility(ModelFamily.sdxl, ModelFamily.pony, metadataBacked: true), LoraCompat.likely);
    });

    test('unknown on either side is unknown (never assumed bad)', () {
      expect(ImageModelFamily.compatibility(ModelFamily.unknown, ModelFamily.sdxl, metadataBacked: true), LoraCompat.unknown);
      expect(ImageModelFamily.compatibility(ModelFamily.flux, ModelFamily.unknown, metadataBacked: true), LoraCompat.unknown);
    });
  });
}
