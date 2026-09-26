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

// Map Studio knobs onto a stock Comfy API graph — same fill as Edit BYO.
// Literals become %TOKEN%; already-tokened graphs are left alone.

import 'comfy_edit_workflow.dart';
import 'comfy_workflow_convert.dart';

class AdaptedComfyGraph {
  final Map<String, dynamic> template;
  final List<ComfyModelSlot> slots;
  final List<String> requiredNodes;
  final String vaeNodeId;
  final int vaeOutputIndex;
  final String modelNodeId;
  final String clipNodeId;

  /// CheckpointLoaderSimple CLIP is output 1. A CLIP loader's CLIP is output 0.
  final int clipOutputIndex;

  const AdaptedComfyGraph({
    required this.template,
    required this.slots,
    required this.requiredNodes,
    this.vaeNodeId = 'vae',
    this.vaeOutputIndex = 0,
    this.modelNodeId = 'unet',
    this.clipNodeId = 'clip',
    this.clipOutputIndex = 0,
  });
}

const _kPromptTextNodes = {
  'CLIPTextEncode',
  'CLIPTextEncodeFlux',
  'TextEncodeQwenImageEditPlus',
  'TextEncodeQwenImage21',
  'TextGenerate',
};

const _kPromptKeys = {'text', 'prompt'};

/// Tokenize model files + sampler/size/prompt widgets on an API-format graph.
AdaptedComfyGraph adaptComfyApiWorkflow(Map<String, dynamic> api) {
  final graph = ensureComfyApiGraph(api) ?? Map<String, dynamic>.from(api);
  final slots = <ComfyModelSlot>[];
  final classes = <String>{};
  var promptCount = 0;
  var diffusionN = 0;
  var clipN = 0;
  var vaeN = 0;
  var ckptN = 0;
  var vaeNodeId = '';
  var modelNodeId = '';
  var clipNodeId = '';
  var clipFromCheckpoint = false;
  var hasFluxGuidance = false;
  final promptSwitchIds = <String>{};
  for (final node in graph.values.whereType<Map>()) {
    if (!_kPromptTextNodes.contains(node['class_type'])) continue;
    final inputs = node['inputs'];
    if (inputs is! Map) continue;
    for (final key in _kPromptKeys) {
      final value = inputs[key];
      if (value is List && value.isNotEmpty) {
        promptSwitchIds.add(value.first.toString());
      }
    }
  }
  for (final v in graph.values) {
    if (v is Map && v['class_type'] == 'FluxGuidance') hasFluxGuidance = true;
  }

  for (final e in graph.entries) {
    if (e.value is! Map) continue;
    final node = Map<String, dynamic>.from(e.value as Map);
    final classType = node['class_type']?.toString() ?? '';
    if (classType.isEmpty) continue;
    classes.add(classType);
    final inputs = node['inputs'];
    if (inputs is! Map) {
      graph[e.key] = node;
      continue;
    }
    final ins = Map<String, dynamic>.from(inputs);

    void slot(
      String token,
      String loader,
      String input,
      String label,
      String folder,
    ) {
      _tokenIfLiteral(ins, input, token);
      if (!slots.any((s) => s.token == token)) {
        slots.add(
          ComfyModelSlot(
            token: token,
            loaderClass: loader,
            inputName: input,
            label: label,
            folderHint: folder,
          ),
        );
      }
    }

    switch (classType) {
      case 'UNETLoader':
      case 'UnetLoaderGGUF':
      case 'UnetLoaderGGUFAdvanced':
        diffusionN++;
        modelNodeId = modelNodeId.isEmpty ? e.key : modelNodeId;
        slot(
          diffusionN == 1
              ? '%MODEL_DIFFUSION%'
              : '%MODEL_DIFFUSION_$diffusionN%',
          classType,
          'unet_name',
          diffusionN == 1 ? 'Diffusion model' : 'Diffusion model $diffusionN',
          'diffusion_models',
        );
      case 'CLIPLoader':
      case 'CLIPLoaderGGUF':
        clipN++;
        if (clipNodeId.isEmpty) {
          clipNodeId = e.key;
          clipFromCheckpoint = false;
        }
        slot(
          clipN == 1 ? '%MODEL_CLIP%' : '%MODEL_CLIP_$clipN%',
          classType,
          'clip_name',
          clipN == 1 ? 'Text encoder' : 'Text encoder $clipN',
          'text_encoders',
        );
      case 'DualCLIPLoader':
      case 'DualCLIPLoaderGGUF':
      case 'TripleCLIPLoaderGGUF':
      case 'QuadrupleCLIPLoaderGGUF':
        if (clipNodeId.isEmpty) {
          clipNodeId = e.key;
          clipFromCheckpoint = false;
        }
        final count = classType.startsWith('Quadruple')
            ? 4
            : classType.startsWith('Triple')
            ? 3
            : 2;
        for (var i = 1; i <= count; i++) {
          slot(
            '%MODEL_CLIP$i%',
            classType,
            'clip_name$i',
            classType == 'DualCLIPLoader'
                ? (i == 1
                      ? 'Text encoder 1 (CLIP-L)'
                      : 'Text encoder 2 (T5-XXL)')
                : 'Text encoder $i',
            'text_encoders',
          );
        }
      case 'VAELoader':
        vaeN++;
        vaeNodeId = vaeNodeId.isEmpty ? e.key : vaeNodeId;
        slot(
          vaeN == 1 ? '%MODEL_VAE%' : '%MODEL_VAE_$vaeN%',
          'VAELoader',
          'vae_name',
          vaeN == 1 ? 'VAE' : 'VAE $vaeN',
          'vae',
        );
      case 'CheckpointLoaderSimple':
        ckptN++;
        modelNodeId = modelNodeId.isEmpty ? e.key : modelNodeId;
        if (clipNodeId.isEmpty) {
          clipNodeId = e.key;
          clipFromCheckpoint = true;
        }
        vaeNodeId = vaeNodeId.isEmpty ? e.key : vaeNodeId;
        slot(
          ckptN == 1 ? '%MODEL_CHECKPOINT%' : '%MODEL_CHECKPOINT_$ckptN%',
          'CheckpointLoaderSimple',
          'ckpt_name',
          ckptN == 1 ? 'Checkpoint Model' : 'Checkpoint Model $ckptN',
          'checkpoints',
        );
      case 'KSampler':
        _tokenIfLiteral(ins, 'seed', ComfyEditTokens.seed);
        _tokenIfLiteral(ins, 'steps', ComfyEditTokens.steps);
        if (!hasFluxGuidance) {
          _tokenIfLiteral(ins, 'cfg', ComfyEditTokens.cfg);
        }
        _tokenIfLiteral(ins, 'sampler_name', ComfyEditTokens.sampler);
        _tokenIfLiteral(ins, 'scheduler', ComfyEditTokens.scheduler);
        _tokenIfLiteral(ins, 'denoise', ComfyEditTokens.denoise);
      case 'FluxGuidance':
        _tokenIfLiteral(ins, 'guidance', ComfyEditTokens.cfg);
      case 'ModelSamplingAuraFlow':
        _tokenIfLiteral(ins, 'shift', ComfyEditTokens.shift);
      case 'EmptyLatentImage':
      case 'EmptySD3LatentImage':
        _tokenIfLiteral(ins, 'width', ComfyEditTokens.width);
        _tokenIfLiteral(ins, 'height', ComfyEditTokens.height);
      case 'LoadImage':
        _tokenIfLiteral(ins, 'image', ComfyEditTokens.image);
      case 'ComfySwitchNode':
        if (promptSwitchIds.contains(e.key) && ins['on_false'] is String) {
          _tokenIfLiteral(ins, 'on_false', ComfyEditTokens.prompt);
        }
      default:
        if (classType == 'TextEncodeQwenImage21') {
          _tokenIfLiteral(ins, 'negative_prompt', ComfyEditTokens.negative);
        }
        if (_kPromptTextNodes.contains(classType)) {
          for (final key in _kPromptKeys) {
            if (!ins.containsKey(key)) continue;
            promptCount++;
            if (ins[key] is List) break;
            _tokenIfLiteral(
              ins,
              key,
              promptCount == 1
                  ? ComfyEditTokens.prompt
                  : ComfyEditTokens.negative,
            );
            break;
          }
        }
    }

    node['inputs'] = ins;
    graph[e.key] = node;
  }

  if (vaeNodeId.isEmpty) {
    for (final e in graph.entries) {
      if (e.value is Map &&
          (e.value as Map)['class_type'] == 'CheckpointLoaderSimple') {
        vaeNodeId = e.key;
        break;
      }
    }
  }

  return AdaptedComfyGraph(
    template: graph,
    slots: slots,
    requiredNodes: classes.toList(),
    vaeNodeId: vaeNodeId.isEmpty ? 'vae' : vaeNodeId,
    vaeOutputIndex: ckptN > 0 && vaeN == 0 ? 2 : 0,
    modelNodeId: modelNodeId.isEmpty ? 'unet' : modelNodeId,
    clipNodeId: clipNodeId.isEmpty ? 'clip' : clipNodeId,
    clipOutputIndex: clipFromCheckpoint ? 1 : 0,
  );
}

void _tokenIfLiteral(Map<String, dynamic> inputs, String key, String token) {
  if (!inputs.containsKey(key)) return;
  final v = inputs[key];
  if (v is String && v.startsWith('%') && v.endsWith('%')) return;
  if (v is List) return; // linked socket — not a widget we own
  inputs[key] = token;
}
