// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/model_family.dart';

void main() {
  test('Draw Things version ids map onto the checkpoint family', () {
    expect(
      ImageModelFamily.familyFromDrawThingsVersion('flux2_9b'),
      ModelFamily.flux,
    );
    expect(
      ImageModelFamily.familyFromDrawThingsVersion('qwen_image'),
      ModelFamily.qwen,
    );
    expect(
      ImageModelFamily.familyFromDrawThingsVersion('z_image'),
      ModelFamily.zImage,
    );
    expect(
      ImageModelFamily.familyFromDrawThingsVersion('sdxl_base_v0.9'),
      ModelFamily.sdxl,
    );
    expect(
      ImageModelFamily.familyFromDrawThingsVersion('v1'),
      ModelFamily.sd15,
    );
    expect(
      ImageModelFamily.familyFromDrawThingsVersion('ltx2.3'),
      ModelFamily.unknown,
    );
  });

  test('a known checkpoint keeps its own base and tucks the rest away', () {
    final flux = ImageModelFamily.classifyLora(
      'style_lora_f16.ckpt',
      metadata: const {'dt_base_model': 'flux2_9b'},
    );
    final qwen = ImageModelFamily.classifyLora(
      'detail_slider.ckpt',
      metadata: const {'dt_base_model': 'qwen_image'},
    );
    final video = ImageModelFamily.classifyLora(
      'motion_lora_f16.ckpt',
      metadata: const {'dt_base_model': 'ltx2.3'},
    );
    expect(flux.family, ModelFamily.flux);
    expect(flux.familyFromMetadata, isTrue);

    bool main(LoraOption lora) => ImageModelFamily.shownInMainList(
      lora: lora.family,
      checkpoint: ModelFamily.flux,
      metadataBacked: lora.familyFromMetadata,
    );

    expect(main(flux), isTrue);
    expect(main(qwen), isFalse);
    expect(main(video), isFalse);

    final pony = ImageModelFamily.classifyLora('pony_style.safetensors');
    expect(
      ImageModelFamily.shownInMainList(
        lora: pony.family,
        checkpoint: ModelFamily.sdxl,
        metadataBacked: pony.familyFromMetadata,
      ),
      isTrue,
    );
  });
}
