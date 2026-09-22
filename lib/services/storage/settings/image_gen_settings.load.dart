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

part of 'image_gen_settings.dart';

/// Prefs load for [ImageGenSettings]. Call sites still use `load()`.
extension ImageGenSettingsLoad on ImageGenSettings {
  void load() {
    _imageGenEnabled = prefs?.getBool(k('image_gen_enabled')) ?? true;
    _imageGenBackend = prefs?.getString(k('image_gen_backend')) ?? 'remote';
    _localImageGenUrl =
        prefs?.getString(k('local_image_gen_url')) ?? 'http://127.0.0.1:7860';
    _comfyUiUrl =
        prefs?.getString(k('comfy_ui_url')) ?? 'http://127.0.0.1:8188';
    _imageGenModel = prefs?.getString(k('image_gen_model')) ?? '';
    _imageGenEditModel = prefs?.getString(k('image_gen_edit_model')) ?? '';
    // One-time migration seed: before the slot split the single model served
    // both tabs, so a user whose current model IS an edit model configured it
    // for the Edit tab — carry it into the edit slot so their setup survives.
    // (The create slot keeps the value too; the non-blocking warning nudges
    // them to pick a real create model.)
    if (_imageGenEditModel.isEmpty && looksLikeEditModel(_imageGenModel)) {
      _imageGenEditModel = _imageGenModel;
      prefs?.setString(k('image_gen_edit_model'), _imageGenEditModel);
    }
    _imageGenSize = prefs?.getString(k('image_gen_size')) ?? '1024x1024';
    _imageGenNegativePrompt =
        prefs?.getString(k('image_gen_negative_prompt')) ??
        'blurry, low quality, watermark, text';
    _imageGenStyle = prefs?.getString(k('image_gen_style')) ?? 'photorealistic';
    _imageGenPromptParadigm =
        prefs?.getString(k('image_gen_prompt_paradigm')) ?? 'natural';
    _imageGenLora = prefs?.getString(k('image_gen_lora')) ?? '';
    _imageGenLoraWeight = prefs?.getDouble(k('image_gen_lora_weight')) ?? 0.8;
    _imageGenDenoise = prefs?.getDouble(k('image_gen_denoise')) ?? 0.5;
    _imageGenSteps = prefs?.getInt(k('image_gen_steps')) ?? 4;
    _imageGenCfgScale = prefs?.getDouble(k('image_gen_cfg_scale')) ?? 1.0;
    _imageGenSampler = prefs?.getString(k('image_gen_sampler')) ?? 'Euler a';
    _imageGenScheduler =
        prefs?.getString(k('image_gen_scheduler')) ?? 'Automatic';
    _imageGenSeed = prefs?.getInt(k('image_gen_seed')) ?? -1;
    _imageGenPromptReview =
        prefs?.getBool(k('image_gen_prompt_review')) ?? true;

    _drawThingsGrpcHost =
        prefs?.getString(k('draw_things_grpc_host')) ?? '127.0.0.1';
    _drawThingsGrpcPort = prefs?.getInt(k('draw_things_grpc_port')) ?? 7859;
    _drawThingsSampler = prefs?.getInt(k('draw_things_sampler')) ?? 16;
    _drawThingsShift = prefs?.getDouble(k('draw_things_shift')) ?? 3.0;
    _drawThingsSeedMode = prefs?.getInt(k('draw_things_seed_mode')) ?? 2;
    _drawThingsTeaCache = prefs?.getBool(k('draw_things_tea_cache')) ?? false;
    _drawThingsCfgZeroStar =
        prefs?.getBool(k('draw_things_cfg_zero_star')) ?? false;

    _editSteps =
        prefs?.getInt(k('image_gen_edit_steps')) ?? kEditRecommendedSteps;
    _editCfgScale =
        prefs?.getDouble(k('image_gen_edit_cfg_scale')) ?? kEditRecommendedCfg;
    _editSampler =
        prefs?.getInt(k('draw_things_edit_sampler')) ??
        kEditRecommendedSamplerInt;
    _editShift =
        prefs?.getDouble(k('draw_things_edit_shift')) ?? kEditRecommendedShift;
    _editSeedMode =
        prefs?.getInt(k('draw_things_edit_seed_mode')) ??
        kEditRecommendedSeedMode;

    _comfyEditWorkflowId =
        prefs?.getString(k('comfy_edit_workflow_id')) ?? 'qwen_image_edit';
    _comfyEditModelChoices = _decodeStringMap(
      prefs?.getString(k('comfy_edit_model_choices')),
    );
    _comfyEditUploadedWorkflow =
        prefs?.getString(k('comfy_edit_uploaded_workflow')) ?? '';
    _comfyCreateWorkflowId =
        prefs?.getString(k('comfy_create_workflow_id')) ?? 'sd';
    _comfyCreateModelChoices = _decodeStringMap(
      prefs?.getString(k('comfy_create_model_choices')),
    );
    _comfyCreateUploadedWorkflow =
        prefs?.getString(k('comfy_create_uploaded_workflow')) ?? '';
    loadImageRemotePrefs();
  }

  Map<String, String> _decodeStringMap(String? s) {
    if (s == null || s.isEmpty) return {};
    try {
      final m = jsonDecode(s);
      if (m is Map) {
        return m.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }
}
