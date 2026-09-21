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

part of 'image_gen_service.dart';

extension _ImageGenComfy on ImageGenService {
  /// Edit presets unchanged (pack stays Edit-first). Create / pack img2img
  /// ride Comfy's own template (or a replaceable starter) + the BYO token
  /// adapter. No pack-only graph. No ControlNet.
  Future<Uint8List> _generateViaComfy({
    required String prompt,
    required String negativePrompt,
    required String? size,
    required String refModelName,
    required Uint8List? referenceImage,
    required int? seed,
    required double? denoise,
    required double? editStrength,
    required ImageReferenceRole refRole,
  }) async {
    final comfy = _ensureComfyUi;
    final settings = _storage.imageGenSettings;
    final (width, height) = _parseSize(size ?? settings.imageGenSize);
    final available = await comfy.fetchSamplers();
    final storedSampler = settings.imageGenSampler;
    final storedScheduler = settings.imageGenScheduler;
    final scheduler =
        (storedScheduler.isNotEmpty && storedScheduler != 'Automatic')
        ? storedScheduler
        : ComfyUiService.schedulerFor(storedSampler);
    final sampler = ComfyUiService.normalizeSampler(storedSampler, available);
    final effectiveSeed = seed ?? settings.imageGenSeed;

    if (refRole == ImageReferenceRole.editConditioning &&
        referenceImage != null) {
      _statusMessage = 'Editing with ComfyUI...';
      _notify();
      final storedSeed = effectiveSeed == -1
          ? Random().nextInt(1 << 31)
          : effectiveSeed;
      final req = resolveComfyEditRequest(
        workflowId: settings.comfyEditWorkflowId,
        uploadedWorkflowJson: settings.comfyEditUploadedWorkflow,
        modelChoices: settings.comfyEditModelChoices,
        prompt: prompt,
        negative: negativePrompt,
        seed: storedSeed,
        steps: settings.editSteps,
        cfg: settings.editCfgScale,
        denoise: editStrength ?? kEditRecommendedStrength,
        shift: settings.editShift,
      );
      if (req == null) {
        throw Exception(
          'No ComfyUI edit workflow is set up. Pick a preset (and its '
          'models) or upload a workflow in the Edit tab.',
        );
      }
      return comfy.generateImageEdit(
        referenceImageBytes: referenceImage,
        workflowTemplate: req.template,
        tokenValues: req.values,
        onProgress: _updateGenProgress,
      );
    }

    final liveName = comfyTemplateNameFor(settings.comfyCreateWorkflowId);
    Map<String, dynamic>? liveTemplate;
    if (liveName != null) {
      liveTemplate = await comfy.fetchTemplateJson(liveName);
    }
    final req = resolveComfyCreateRequest(
      workflowId: settings.comfyCreateWorkflowId,
      uploadedWorkflowJson: settings.comfyCreateUploadedWorkflow,
      modelChoices: settings.comfyCreateModelChoices,
      prompt: prompt,
      negative: negativePrompt,
      seed: effectiveSeed == -1 ? Random().nextInt(1 << 31) : effectiveSeed,
      steps: settings.imageGenSteps,
      cfg: settings.imageGenCfgScale,
      denoise: denoise ?? settings.imageGenDenoise,
      shift: settings.editShift,
      width: width,
      height: height,
      sampler: sampler,
      scheduler: scheduler,
      checkpointFallback: refModelName,
      liveTemplate: liveTemplate,
    );
    if (req == null) {
      throw Exception(
        'No ComfyUI create workflow is set up. Pick SD or a Comfy '
        'template (and its model files) in Image Studio, or upload one.',
      );
    }
    if (req.useCheckpointBuilder) {
      if (req.checkpoint.isEmpty) {
        throw Exception('Select a checkpoint model for ComfyUI first.');
      }
      return comfy.generateImage(
        prompt: prompt,
        negativePrompt: negativePrompt,
        model: req.checkpoint,
        width: width,
        height: height,
        steps: settings.imageGenSteps,
        cfgScale: settings.imageGenCfgScale,
        seed: effectiveSeed,
        samplerName: sampler,
        scheduler: scheduler,
        loraName: settings.imageGenLora,
        loraWeight: settings.imageGenLoraWeight,
        referenceImageBytes: referenceImage,
        denoise: denoise ?? settings.imageGenDenoise,
        onProgress: _updateGenProgress,
      );
    }

    _statusMessage = 'Generating with ComfyUI...';
    _notify();
    var template = req.template;
    final values = Map<String, Object?>.from(req.values);
    if (referenceImage != null && referenceImage.isNotEmpty) {
      final uploaded = await comfy.uploadImage(referenceImage);
      values[ComfyEditTokens.image] = uploaded;
      template = applyCreateImg2Img(
        template,
        vaeNodeId: req.vaeNodeId,
        vaeOutputIndex: req.vaeOutputIndex,
      );
    } else {
      values[ComfyEditTokens.denoise] = 1.0;
    }
    if (settings.imageGenLora.isNotEmpty) {
      template = spliceComfyLora(
        template,
        loraName: settings.imageGenLora,
        loraWeight: settings.imageGenLoraWeight,
        modelNodeId: req.modelNodeId,
        clipNodeId: req.clipNodeId,
      );
    }
    final graph = substituteComfyWorkflow(template, values);
    final leftover = unresolvedComfyTokens(graph);
    if (leftover.isNotEmpty) {
      throw Exception(
        'This ComfyUI create workflow still has unfilled placeholders '
        '(${leftover.join(', ')}). Pick a model for each slot.',
      );
    }
    return comfy.runPromptGraph(graph, onProgress: _updateGenProgress);
  }
}
