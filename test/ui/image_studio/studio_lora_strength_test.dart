// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image_gen_lora_slots.dart';
import 'package:front_porch_ai/ui/image_studio/studio_lora_sheet.dart';

void main() {
  testWidgets('a filled LoRA slot shows its strength on the slider', (
    tester,
  ) async {
    final slots = ImageGenLoraSlot.blank();
    slots[0] = const ImageGenLoraSlot(file: 'detail.safetensors', weight: 0.8);
    slots[1] = const ImageGenLoraSlot(file: 'style.safetensors', weight: 0.35);

    await tester.pumpWidget(
      MaterialApp(
        home: StudioLoraSheet(
          slots: slots,
          files: const ['detail.safetensors', 'style.safetensors'],
          primaryFile: 'z_image_turbo_bf16.safetensors',
          onPick: (_, _) {},
          onWeight: (_, _) {},
        ),
      ),
    );

    expect(find.text('0.80'), findsOneWidget);
    expect(find.text('0.35'), findsOneWidget);
  });
}
