// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/comfy_create_workflow.dart';
import 'package:front_porch_ai/services/image/comfy_starters.dart';
import 'package:front_porch_ai/services/image/image_gen_lora_slots.dart';

void main() {
  test('legacy single LoRA loads into slot 0', () {
    final slots = ImageGenLoraSlot.decode(
      null,
      legacyFile: 'warm_porch.safetensors',
      legacyWeight: 0.65,
    );
    expect(slots, hasLength(kImageGenLoraSlotCount));
    expect(slots.first.file, 'warm_porch.safetensors');
    expect(slots.first.weight, 0.65);
    expect(slots[1].isEmpty, isTrue);
  });

  test('Automatic1111 stacks every filled slot as a prompt tag', () {
    final prompt = promptWithLoras('a porch', const [
      ImageGenLoraSlot(file: 'style.safetensors', weight: 0.8),
      ImageGenLoraSlot(file: '', weight: 0.5),
      ImageGenLoraSlot(file: 'detail.ckpt', weight: 0.4),
    ]);
    expect(
      prompt,
      'a porch <lora:style.safetensors:0.80> <lora:detail.ckpt:0.40>',
    );
  });

  test('Comfy chains a second LoRA onto the first loader', () {
    final graph = spliceComfyLoraChain(
      Map<String, dynamic>.from(kComfyStarterSd),
      loras: const [
        (name: 'style.safetensors', weight: 0.8),
        (name: 'detail.safetensors', weight: 0.4),
      ],
      modelNodeId: 'ckpt',
      clipNodeId: 'ckpt',
      clipOutputIndex: 1,
    );
    expect(graph['lora']['inputs']['clip'], ['ckpt', 1]);
    expect(graph['lora_1']['inputs']['model'], ['lora', 0]);
    expect(graph['lora_1']['inputs']['clip'], ['lora', 1]);
    final encodes = graph.values.cast<Map>().where(
      (n) => n['class_type'] == 'CLIPTextEncode',
    );
    for (final node in encodes) {
      expect(node['inputs']['clip'], ['lora_1', 1]);
    }
    final sampler = graph.values.cast<Map>().firstWhere(
      (n) => n['class_type'] == 'KSampler',
    );
    expect(sampler['inputs']['model'], ['lora_1', 0]);
    final decode = graph.values.cast<Map>().firstWhere(
      (n) => n['class_type'] == 'VAEDecode',
    );
    expect(decode['inputs']['vae'], ['ckpt', 2]);
  });
}
