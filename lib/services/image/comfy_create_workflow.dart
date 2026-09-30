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

  /// Kept on the wire for older panels. Create no longer takes this branch.
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

  /// Output index on [clipNodeId] that is CLIP. 1 for a checkpoint, 0 for a
  /// CLIP loader.
  final int clipOutputIndex;

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
    this.clipOutputIndex = 0,
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

/// Insert one LoraLoader and rewire MODEL/CLIP consumers to it.
Map<String, dynamic> spliceComfyLora(
  Map<String, dynamic> graph, {
  required String loraName,
  required double loraWeight,
  required String modelNodeId,
  required String clipNodeId,
  int clipOutputIndex = 0,
}) {
  return spliceComfyLoraChain(
    graph,
    loras: [(name: loraName, weight: loraWeight)],
    modelNodeId: modelNodeId,
    clipNodeId: clipNodeId,
    clipOutputIndex: clipOutputIndex,
  );
}

/// Stack LoRAs. The first loader is node `lora` (same as [spliceComfyLora]).
/// Each later loader reads the previous loader's MODEL and CLIP outputs.
Map<String, dynamic> spliceComfyLoraChain(
  Map<String, dynamic> graph, {
  required List<({String name, double weight})> loras,
  required String modelNodeId,
  required String clipNodeId,
  int clipOutputIndex = 0,
}) {
  var out = graph;
  var fromModel = modelNodeId;
  var fromModelIndex = 0;
  var fromClip = clipNodeId;
  var fromClipIndex = clipOutputIndex;
  var n = 0;
  for (final lora in loras) {
    if (lora.name.trim().isEmpty) continue;
    final id = n == 0 ? 'lora' : 'lora_$n';
    out = substituteComfyWorkflow(out, const {});
    out[id] = {
      'class_type': 'LoraLoader',
      'inputs': {
        'lora_name': lora.name.trim(),
        'strength_model': lora.weight,
        'strength_clip': lora.weight,
        'model': [fromModel, fromModelIndex],
        'clip': [fromClip, fromClipIndex],
      },
    };
    _rewire(out, from: [fromModel, fromModelIndex], to: [id, 0], skip: id);
    _rewire(out, from: [fromClip, fromClipIndex], to: [id, 1], skip: id);
    fromModel = id;
    fromModelIndex = 0;
    fromClip = id;
    fromClipIndex = 1;
    n++;
  }
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
