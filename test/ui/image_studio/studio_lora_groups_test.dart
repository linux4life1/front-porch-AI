// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image_gen_lora_slots.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/ui/image_studio/studio_lora_sheet.dart';

void main() {
  testWidgets('local LoRAs are listed by base model with no search', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: StudioLoraSheet(
          slots: ImageGenLoraSlot.blank(),
          files: const [
            'z-image-turbo-realism.safetensors',
            'qwen_image_lora.safetensors',
            'pretty.safetensors',
          ],
          primaryFile: 'qwen_image_bf16.safetensors',
          facts: const {
            'z-image-turbo-realism.safetensors': DeskLoraCheck(
              'z-image-turbo-realism.safetensors',
              ModelFamily.zImage,
              metadataBacked: true,
            ),
          },
          onPick: (_, file) => picked = file,
        ),
      ),
    );

    expect(find.text('Search LoRAs'), findsNothing);
    expect(find.text('Matches this model'), findsOneWidget);
    expect(find.text('Other bases'), findsOneWidget);
    expect(find.text('z-image-turbo-realism.safetensors'), findsOneWidget);
    expect(find.text('qwen_image_lora.safetensors'), findsOneWidget);

    await tester.tap(find.text('z-image-turbo-realism.safetensors'));
    await tester.pump();
    expect(picked, 'z-image-turbo-realism.safetensors');

    await tester.tap(find.text('qwen_image_lora.safetensors'));
    await tester.pump();
    expect(picked, 'qwen_image_lora.safetensors');
  });
}
