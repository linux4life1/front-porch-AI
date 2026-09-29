// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/web/facade/image_facade.dart';

void main() {
  test('phone LoRA facts keep a metadata mismatch', () {
    final rows = phoneLoraFacts(
      options: const [
        LoraOption(
          'qwen_image_lora.safetensors',
          ModelFamily.qwen,
          familyFromMetadata: true,
        ),
      ],
      checks: const [
        DeskLoraCheck('z-image-turbo-realism.safetensors', ModelFamily.zImage),
      ],
    );
    expect(rows, [
      {'file': 'qwen_image_lora.safetensors', 'family': 'qwen', 'meta': true},
      {
        'file': 'z-image-turbo-realism.safetensors',
        'family': 'zImage',
        'meta': false,
      },
    ]);
  });
}
