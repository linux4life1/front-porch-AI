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

// Create-family metadata + img2img / LoRA knobs on an adapted stock graph.
// Graphs themselves live in Comfy templates or replaceable starters — not here.

import 'comfy_edit_workflow.dart';

/// Thin pointer at a Comfy template (live `/templates/{name}` or a starter).
class ComfyCreatePreset {
  final String id;
  final String label;

  /// Official Comfy template file stem (`image_z_image_turbo`). Empty for SD.
  final String comfyTemplateName;

  /// SD pile: [ComfyWorkflow] builders, not a template.
  final bool usesCheckpointBuilder;

  final List<ComfyModelSlot> modelSlots;
  final List<String> requiredNodes;

  const ComfyCreatePreset({
    required this.id,
    required this.label,
    this.comfyTemplateName = '',
    this.usesCheckpointBuilder = false,
    this.modelSlots = const [],
    this.requiredNodes = const [],
  });
}

/// Resolved Create graph (or the SD-builder flag).
class ComfyCreateRequest {
  final Map<String, dynamic> template;
  final Map<String, Object?> values;
  final bool useCheckpointBuilder;
  final String checkpoint;
  final List<ComfyModelSlot> slots;
  final String vaeNodeId;
  final int vaeOutputIndex;
  final String modelNodeId;
  final String clipNodeId;

  const ComfyCreateRequest({
    required this.template,
    required this.values,
    this.useCheckpointBuilder = false,
    this.checkpoint = '',
    this.slots = const [],
    this.vaeNodeId = 'vae',
    this.vaeOutputIndex = 0,
    this.modelNodeId = 'unet',
    this.clipNodeId = 'clip',
  });
}

const String kComfyCheckpointToken = '%MODEL_CHECKPOINT%';

/// Swap Empty*Latent for LoadImage → VAEEncode. Deep-copies [template].
Map<String, dynamic> applyCreateImg2Img(
  Map<String, dynamic> template, {
  required String vaeNodeId,
  int vaeOutputIndex = 0,
}) {
  final out = substituteComfyWorkflow(template, const {});
  String? latentId;
  for (final e in out.entries) {
    if (e.value is! Map) continue;
    final ct = (e.value as Map)['class_type']?.toString() ?? '';
    if (ct == 'EmptyLatentImage' || ct == 'EmptySD3LatentImage') {
      latentId = e.key;
      break;
    }
  }
  latentId ??= 'latent';
  out['init_image'] = {
    'class_type': 'LoadImage',
    'inputs': {'image': ComfyEditTokens.image},
  };
  out[latentId] = {
    'class_type': 'VAEEncode',
    'inputs': {
      'pixels': ['init_image', 0],
      'vae': [vaeNodeId, vaeOutputIndex],
    },
  };
  return out;
}

/// Insert LoraLoader and rewire MODEL/CLIP consumers to it.
Map<String, dynamic> spliceComfyLora(
  Map<String, dynamic> graph, {
  required String loraName,
  required double loraWeight,
  required String modelNodeId,
  required String clipNodeId,
}) {
  if (loraName.isEmpty) return graph;
  final out = substituteComfyWorkflow(graph, const {});
  out['lora'] = {
    'class_type': 'LoraLoader',
    'inputs': {
      'lora_name': loraName,
      'strength_model': loraWeight,
      'strength_clip': loraWeight,
      'model': [modelNodeId, 0],
      'clip': [clipNodeId, 0],
    },
  };
  _rewire(out, from: [modelNodeId, 0], to: ['lora', 0], skip: 'lora');
  _rewire(out, from: [clipNodeId, 0], to: ['lora', 1], skip: 'lora');
  return out;
}

void _rewire(
  Map<String, dynamic> graph, {
  required List<Object> from,
  required List<Object> to,
  required String skip,
}) {
  for (final e in graph.entries) {
    if (e.key == skip || e.value is! Map) continue;
    final inputs = (e.value as Map)['inputs'];
    if (inputs is! Map) continue;
    for (final k in inputs.keys.toList()) {
      final v = inputs[k];
      if (v is List &&
          v.length == 2 &&
          '${v[0]}' == '${from[0]}' &&
          v[1] == from[1]) {
        inputs[k] = to;
      }
    }
  }
}
