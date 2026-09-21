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

// Create families are pointers at Comfy's own templates (or BYO), not
// Porch-authored node graphs. Live `/templates/{name}.json` wins; bundled
// starters are replaceable stock API JSON. SD keeps the existing builder.

import 'dart:convert';

import 'comfy_create_workflow.dart';
import 'comfy_edit_presets.dart';
import 'comfy_edit_workflow.dart';
import 'comfy_starters.dart';
import 'comfy_workflow_adapt.dart';
import 'comfy_workflow_convert.dart';

const ComfyModelSlot kComfyDiffusionSlot = ComfyModelSlot(
  token: '%MODEL_DIFFUSION%',
  loaderClass: 'UNETLoader',
  inputName: 'unet_name',
  label: 'Diffusion model',
  folderHint: 'diffusion_models',
);
const ComfyModelSlot kComfyClipSlot = ComfyModelSlot(
  token: '%MODEL_CLIP%',
  loaderClass: 'CLIPLoader',
  inputName: 'clip_name',
  label: 'Text encoder',
  folderHint: 'text_encoders',
);
const ComfyModelSlot kComfyVaeSlot = ComfyModelSlot(
  token: '%MODEL_VAE%',
  loaderClass: 'VAELoader',
  inputName: 'vae_name',
  label: 'VAE',
  folderHint: 'vae',
);

const ComfyCreatePreset kSdCreatePreset = ComfyCreatePreset(
  id: 'sd',
  label: 'SD / SDXL / Pony / Illustrious',
  usesCheckpointBuilder: true,
  requiredNodes: [
    'CheckpointLoaderSimple',
    'CLIPTextEncode',
    'EmptyLatentImage',
    'KSampler',
    'VAEDecode',
    'SaveImage',
    'LoadImage',
    'VAEEncode',
  ],
  modelSlots: [
    ComfyModelSlot(
      token: kComfyCheckpointToken,
      loaderClass: 'CheckpointLoaderSimple',
      inputName: 'ckpt_name',
      label: 'Checkpoint Model',
      folderHint: 'checkpoints',
    ),
  ],
);

const ComfyCreatePreset kFluxCreatePreset = ComfyCreatePreset(
  id: 'flux',
  label: 'Flux / Schnell / Krea',
  comfyTemplateName: 'flux_schnell',
  modelSlots: [
    kComfyDiffusionSlot,
    ComfyModelSlot(
      token: '%MODEL_CLIP1%',
      loaderClass: 'DualCLIPLoader',
      inputName: 'clip_name1',
      label: 'Text encoder 1 (CLIP-L)',
      folderHint: 'text_encoders',
    ),
    ComfyModelSlot(
      token: '%MODEL_CLIP2%',
      loaderClass: 'DualCLIPLoader',
      inputName: 'clip_name2',
      label: 'Text encoder 2 (T5-XXL)',
      folderHint: 'text_encoders',
    ),
    kComfyVaeSlot,
  ],
  requiredNodes: [
    'UNETLoader',
    'DualCLIPLoader',
    'VAELoader',
    'CLIPTextEncode',
    'FluxGuidance',
    'KSampler',
    'VAEDecode',
    'SaveImage',
  ],
);

const ComfyCreatePreset kQwenCreatePreset = ComfyCreatePreset(
  id: 'qwen_image',
  label: 'Qwen-Image',
  comfyTemplateName: 'image_qwen_image',
  modelSlots: [kComfyDiffusionSlot, kComfyClipSlot, kComfyVaeSlot],
  requiredNodes: [
    'UNETLoader',
    'CLIPLoader',
    'VAELoader',
    'CLIPTextEncode',
    'EmptySD3LatentImage',
    'KSampler',
    'VAEDecode',
    'SaveImage',
  ],
);

const ComfyCreatePreset kZitCreatePreset = ComfyCreatePreset(
  id: 'z_image_turbo',
  label: 'Z-Image Turbo',
  comfyTemplateName: 'image_z_image_turbo',
  modelSlots: [kComfyDiffusionSlot, kComfyClipSlot, kComfyVaeSlot],
  requiredNodes: [
    'UNETLoader',
    'CLIPLoader',
    'VAELoader',
    'CLIPTextEncode',
    'EmptySD3LatentImage',
    'KSampler',
    'VAEDecode',
    'SaveImage',
  ],
);

const List<ComfyCreatePreset> kComfyCreatePresets = [
  kSdCreatePreset,
  kFluxCreatePreset,
  kQwenCreatePreset,
  kZitCreatePreset,
];

ComfyCreatePreset? comfyCreatePresetById(String id) {
  for (final p in kComfyCreatePresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// Comfy template stem for a family id or a `comfy:{name}` live pick.
String? comfyTemplateNameFor(String workflowId) {
  final preset = comfyCreatePresetById(workflowId);
  if (preset != null) {
    return preset.comfyTemplateName.isEmpty ? null : preset.comfyTemplateName;
  }
  if (workflowId.startsWith('comfy:')) return workflowId.substring(6);
  return null;
}

/// Load the JSON we will adapt: BYO, a live Comfy template, or a starter.
Map<String, dynamic>? loadComfyCreateSource({
  required String workflowId,
  required String uploadedWorkflowJson,
  Map<String, dynamic>? liveTemplate,
}) {
  if (workflowId == kComfyUploadedWorkflowId) {
    if (uploadedWorkflowJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(uploadedWorkflowJson);
      if (decoded is! Map) return null;
      return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
  if (workflowId == 'sd') return null;
  if (liveTemplate != null && liveTemplate.isNotEmpty) return liveTemplate;
  return comfyStarterGraph(workflowId);
}

Map<String, Object?> comfyCreateTokenValues({
  required String prompt,
  required String negative,
  required int seed,
  required int steps,
  required double cfg,
  required double denoise,
  required double shift,
  required int width,
  required int height,
  String sampler = 'euler',
  String scheduler = 'simple',
}) => {
  ComfyEditTokens.prompt: prompt,
  ComfyEditTokens.negative: negative,
  ComfyEditTokens.seed: seed,
  ComfyEditTokens.steps: steps,
  ComfyEditTokens.cfg: cfg,
  ComfyEditTokens.denoise: denoise,
  ComfyEditTokens.shift: shift,
  ComfyEditTokens.width: width,
  ComfyEditTokens.height: height,
  ComfyEditTokens.sampler: sampler,
  ComfyEditTokens.scheduler: scheduler,
};

/// Knob + slot fill. [source] is BYO / live template / starter API-or-UI JSON.
ComfyCreateRequest? resolveComfyCreateRequest({
  required String workflowId,
  required String uploadedWorkflowJson,
  required Map<String, String> modelChoices,
  required String prompt,
  required String negative,
  required int seed,
  required int steps,
  required double cfg,
  required double denoise,
  required double shift,
  required int width,
  required int height,
  String sampler = 'euler',
  String scheduler = 'simple',
  String checkpointFallback = '',
  Map<String, dynamic>? liveTemplate,
  Map<String, dynamic>? objectInfo,
}) {
  final values = comfyCreateTokenValues(
    prompt: prompt,
    negative: negative,
    seed: seed,
    steps: steps,
    cfg: cfg,
    denoise: denoise,
    shift: shift,
    width: width,
    height: height,
    sampler: sampler,
    scheduler: scheduler,
  );

  if (workflowId == 'sd' ||
      (comfyCreatePresetById(workflowId)?.usesCheckpointBuilder ?? false)) {
    final file =
        modelChoices['$workflowId/$kComfyCheckpointToken'] ?? checkpointFallback;
    return ComfyCreateRequest(
      template: const {},
      values: values,
      useCheckpointBuilder: true,
      checkpoint: file,
      slots: kSdCreatePreset.modelSlots,
      vaeNodeId: 'ckpt',
      vaeOutputIndex: 2,
      modelNodeId: 'ckpt',
      clipNodeId: 'ckpt',
    );
  }

  final source = loadComfyCreateSource(
    workflowId: workflowId,
    uploadedWorkflowJson: uploadedWorkflowJson,
    liveTemplate: liveTemplate,
  );
  if (source == null) return null;
  final api = ensureComfyApiGraph(source, objectInfo: objectInfo);
  if (api == null) return null;
  final adapted = adaptComfyApiWorkflow(api);
  for (final slot in adapted.slots) {
    final file =
        modelChoices['$workflowId/${slot.token}'] ??
        modelChoices['${comfyTemplateNameFor(workflowId) ?? ''}/${slot.token}'] ??
        '';
    if (file.isNotEmpty) values[slot.token] = file;
  }
  return ComfyCreateRequest(
    template: adapted.template,
    values: values,
    slots: adapted.slots,
    vaeNodeId: adapted.vaeNodeId,
    vaeOutputIndex: adapted.vaeOutputIndex,
    modelNodeId: adapted.modelNodeId,
    clipNodeId: adapted.clipNodeId,
  );
}

/// True when Create / pack img2img would not hit an unfilled placeholder.
bool comfyCreateReady({
  required String workflowId,
  required String uploadedWorkflowJson,
  required Map<String, String> modelChoices,
  String checkpointFallback = '',
  Map<String, dynamic>? liveTemplate,
}) {
  final req = resolveComfyCreateRequest(
    workflowId: workflowId,
    uploadedWorkflowJson: uploadedWorkflowJson,
    modelChoices: modelChoices,
    prompt: 'x',
    negative: '',
    seed: 0,
    steps: 1,
    cfg: 1,
    denoise: 1,
    shift: 1,
    width: 64,
    height: 64,
    checkpointFallback: checkpointFallback,
    liveTemplate: liveTemplate,
  );
  if (req == null) return false;
  if (req.useCheckpointBuilder) return req.checkpoint.isNotEmpty;
  if (workflowId == kComfyUploadedWorkflowId) {
    final tokens = detectComfyTokens(req.template);
    if (!tokens.contains(ComfyEditTokens.prompt) &&
        !ComfyEditTokens.createRequired.every(tokens.contains)) {
      // Adapter always writes %PROMPT% when a text node exists.
      if (!req.template.toString().contains(ComfyEditTokens.prompt)) {
        return false;
      }
    }
  }
  final graph = substituteComfyWorkflow(req.template, {
    ...req.values,
    ComfyEditTokens.image: 'x',
  });
  return unresolvedComfyTokens(graph).isEmpty;
}
