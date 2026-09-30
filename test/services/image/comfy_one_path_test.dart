// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/image.dart';

void main() {
  Map<String, dynamic> filled(String workflowId, Map<String, String> choices) {
    final req = resolveComfyCreateRequest(
      workflowId: workflowId,
      uploadedWorkflowJson: '',
      modelChoices: choices,
      prompt: 'a porch at dusk',
      negative: 'blur',
      seed: 7,
      steps: 12,
      cfg: 5,
      denoise: 1,
      shift: 1,
      width: 768,
      height: 512,
      sampler: 'euler',
      scheduler: 'normal',
      checkpointFallback: 'fallback.safetensors',
    );
    expect(req, isNotNull, reason: workflowId);
    expect(req!.useCheckpointBuilder, isFalse, reason: workflowId);
    final graph = substituteComfyWorkflow(req.template, req.values);
    expect(unresolvedComfyTokens(graph), isEmpty, reason: workflowId);
    return graph;
  }

  test('SD and Z-Image fill through the same token entry', () {
    final sd = filled('sd', const {
      'sd/%MODEL_CHECKPOINT%': 'ponyDiffusion.safetensors',
    });
    final zit = filled('z_image_turbo', const {
      'z_image_turbo/%MODEL_DIFFUSION%': 'z_image_turbo_bf16.safetensors',
      'z_image_turbo/%MODEL_CLIP%': 'qwen_3_4b.safetensors',
      'z_image_turbo/%MODEL_VAE%': 'ae.safetensors',
    });

    final sdCkpt = sd.values.cast<Map>().firstWhere(
      (n) => n['class_type'] == 'CheckpointLoaderSimple',
    );
    expect(sdCkpt['inputs']['ckpt_name'], 'ponyDiffusion.safetensors');
    final sdPrompt = sd.values.cast<Map>().firstWhere(
      (n) =>
          n['class_type'] == 'CLIPTextEncode' && n['inputs']['text'] != 'blur',
    );
    expect(sdPrompt['inputs']['text'], 'a porch at dusk');
    final sdLatent = sd.values.cast<Map>().firstWhere(
      (n) => n['class_type'] == 'EmptyLatentImage',
    );
    expect(sdLatent['inputs']['width'], 768);
    expect(sdLatent['inputs']['height'], 512);
    final sdSampler = sd.values.cast<Map>().firstWhere(
      (n) => n['class_type'] == 'KSampler',
    );
    expect(sdSampler['inputs']['sampler_name'], 'euler');
    expect(sdSampler['inputs']['steps'], 12);

    final unet = zit.values.cast<Map>().firstWhere(
      (n) => n['class_type'] == 'UNETLoader',
    );
    expect(unet['inputs']['unet_name'], 'z_image_turbo_bf16.safetensors');
    expect(
      sd.values.cast<Map>().any(
        (n) => n['class_type'] == 'CheckpointLoaderSimple',
      ),
      isTrue,
    );
    expect(kSdCreatePreset.usesCheckpointBuilder, isFalse);
    expect(kSdCreatePreset.id, 'sd');
  });

  test('web Comfy family control still sends the sd id', () {
    final page = File(
      'web_ui/src/components/models/ImageGen.tsx',
    ).readAsStringSync();
    final fields = File(
      'web_ui/src/components/models/ComfyCreateFields.tsx',
    ).readAsStringSync();
    expect(page.contains("'sd'"), isTrue);
    expect(fields.contains('value={p.id}'), isTrue);
    expect(kComfyCreatePresets.map((p) => p.id), contains('sd'));
  });

  test('SD LoRA uses checkpoint CLIP output 1', () {
    final req = resolveComfyCreateRequest(
      workflowId: 'sd',
      uploadedWorkflowJson: '',
      modelChoices: const {'sd/%MODEL_CHECKPOINT%': 'pony.safetensors'},
      prompt: 'a porch',
      negative: 'blur',
      seed: 1,
      steps: 20,
      cfg: 7,
      denoise: 1,
      shift: 1,
      width: 512,
      height: 512,
    );
    expect(req, isNotNull);
    expect(req!.clipNodeId, 'ckpt');
    expect(req.clipOutputIndex, 1);
    final g = spliceComfyLora(
      req.template,
      loraName: 'detail.safetensors',
      loraWeight: 0.8,
      modelNodeId: req.modelNodeId,
      clipNodeId: req.clipNodeId,
      clipOutputIndex: req.clipOutputIndex,
    );
    expect(g['lora']['inputs']['model'], ['ckpt', 0]);
    expect(g['lora']['inputs']['clip'], ['ckpt', 1]);
    final encodes = g.values.cast<Map>().where(
      (n) => n['class_type'] == 'CLIPTextEncode',
    );
    expect(encodes, isNotEmpty);
    for (final node in encodes) {
      expect(node['inputs']['clip'], ['lora', 1]);
    }
    final sampler = g.values.cast<Map>().firstWhere(
      (n) => n['class_type'] == 'KSampler',
    );
    expect(sampler['inputs']['model'], ['lora', 0]);
    final decode = g.values.cast<Map>().firstWhere(
      (n) => n['class_type'] == 'VAEDecode',
    );
    expect(decode['inputs']['vae'], ['ckpt', 2]);

    final service = File(
      'lib/services/image_gen_service.comfy.dart',
    ).readAsStringSync();
    expect(service.contains('clipOutputIndex: req.clipOutputIndex'), isTrue);

    final zit = resolveComfyCreateRequest(
      workflowId: 'z_image_turbo',
      uploadedWorkflowJson: '',
      modelChoices: const {},
      prompt: 'x',
      negative: '',
      seed: 1,
      steps: 4,
      cfg: 1,
      denoise: 1,
      shift: 1,
      width: 64,
      height: 64,
    );
    expect(zit!.clipOutputIndex, 0);
  });
}
