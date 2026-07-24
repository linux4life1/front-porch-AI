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

import 'dart:convert';

import 'package:front_porch_ai/services/capability/image_reference_role.dart';

import '../../image/edit_profile.dart';
import 'settings_base.dart';

/// Image generation (A1111/Draw Things/remote) + Draw Things gRPC settings.
///
/// Lifted Stage 7.
class ImageGenSettings with SettingsBase {
  // Default ON since 2026-07: the feature is opt-out. Enabling only shows the
  // ✨ toolbar button and the /image command — nothing generates until a
  // backend is actually configured, so there is no overhead for users who
  // never touch it. Users who previously toggled it keep their saved choice.
  bool _imageGenEnabled = true;
  String _imageGenBackend =
      'remote'; // 'remote', 'a1111', 'drawthings', 'comfyui'
  String _localImageGenUrl = 'http://127.0.0.1:7860';
  String _comfyUiUrl = 'http://127.0.0.1:8188';
  String _imageGenModel = '';

  // The EDIT-task model slot (phase #12 model-slot split). One shared
  // `imageGenModel` used to serve both Studio tabs, so an edit model left
  // selected after an Edit session silently poisoned base-image generation
  // (edit models can't txt2img — maintainer catch, 2026-07-16). The existing
  // key stays the CREATE slot for back-compat; edit paths (Edit tab, edit-
  // first expression packs on DT/remote) read this one. ComfyUI's edit setup
  // lives in its own comfyEdit* keys and is deliberately not duplicated here.
  String _imageGenEditModel = '';
  String _imageGenSize = '1024x1024';
  String _imageGenNegativePrompt = 'blurry, low quality, watermark, text';
  String _imageGenStyle = 'photorealistic';
  String _imageGenPromptParadigm = 'natural'; // 'natural', 'tags'
  String _imageGenLora = '';
  double _imageGenLoraWeight = 0.8;
  // img2img denoising strength — the single, backend-agnostic knob for how far
  // a generation moves away from the supplied reference image (0 = keep the
  // reference, 1 = ignore it). Only takes effect when a reference image is
  // provided; pure txt2img generations never read it. Replaced the old
  // Draw-Things-only `drawThingsStrength` (which was redundant once img2img
  // became a shared feature across A1111/ComfyUI/Draw Things).
  double _imageGenDenoise = 0.5;
  int _imageGenSteps = 4;
  double _imageGenCfgScale = 1.0;
  String _imageGenSampler = 'Euler a';
  // 'Automatic' means "let the backend decide": A1111 omits the scheduler field
  // (server default) and ComfyUI derives it from the sampler via
  // ComfyUiService.schedulerFor(). Any other value is passed through verbatim.
  String _imageGenScheduler = 'Automatic';
  int _imageGenSeed = -1;
  bool _imageGenPromptReview = true;

  // Draw Things gRPC-specific
  String _drawThingsGrpcHost = '127.0.0.1';
  int _drawThingsGrpcPort = 7859;
  int _drawThingsSampler = 16;
  double _drawThingsShift = 3.0;
  int _drawThingsSeedMode = 2;
  bool _drawThingsTeaCache = false;
  bool _drawThingsCfgZeroStar = false;

  // Edit-scoped generation knobs (Image Studio → Edit tab, instruction-edit
  // models like Qwen-Image-Edit). Kept SEPARATE from the txt2img knobs above so
  // tuning an edit never clobbers Create's sampler/CFG/steps — the two model
  // families want very different values. Seeded from the field-tested recipe
  // (edit_profile.dart) and then honored verbatim; nothing overrides them.
  int _editSteps = kEditRecommendedSteps;
  double _editCfgScale = kEditRecommendedCfg;
  int _editSampler = kEditRecommendedSamplerInt;
  double _editShift = kEditRecommendedShift;
  int _editSeedMode = kEditRecommendedSeedMode;

  // ComfyUI edit: which bundled preset drives an edit (matches a preset id, or
  // the '__uploaded__' sentinel for a user-supplied workflow), the per-preset
  // model-slot file choices ("presetId/%TOKEN%" -> filename), and any uploaded
  // workflow JSON. The DT-flavored edit knobs above still supply steps/CFG/
  // strength/shift; ComfyUI uses its own sampler/scheduler defaults.
  String _comfyEditWorkflowId = 'qwen_image_edit'; // == kQwenImageEditPreset.id
  Map<String, String> _comfyEditModelChoices = {};
  String _comfyEditUploadedWorkflow = '';

  bool get imageGenEnabled => _imageGenEnabled;
  String get imageGenBackend => _imageGenBackend;
  String get localImageGenUrl => _localImageGenUrl;
  String get comfyUiUrl => _comfyUiUrl;
  String get imageGenModel => _imageGenModel;
  String get imageGenEditModel => _imageGenEditModel;
  String get imageGenSize => _imageGenSize;
  String get imageGenNegativePrompt => _imageGenNegativePrompt;
  String get imageGenStyle => _imageGenStyle;
  String get imageGenPromptParadigm => _imageGenPromptParadigm;
  String get imageGenLora => _imageGenLora;
  double get imageGenLoraWeight => _imageGenLoraWeight;
  double get imageGenDenoise => _imageGenDenoise;
  int get imageGenSteps => _imageGenSteps;
  double get imageGenCfgScale => _imageGenCfgScale;
  String get imageGenSampler => _imageGenSampler;
  String get imageGenScheduler => _imageGenScheduler;
  int get imageGenSeed => _imageGenSeed;

  /// Whether AI-crafted image prompts (the /image command) pause for user
  /// review/editing before being sent to the backend. Default ON.
  bool get imageGenPromptReview => _imageGenPromptReview;

  String get drawThingsGrpcHost => _drawThingsGrpcHost;
  int get drawThingsGrpcPort => _drawThingsGrpcPort;
  int get drawThingsSampler => _drawThingsSampler;
  double get drawThingsShift => _drawThingsShift;
  int get drawThingsSeedMode => _drawThingsSeedMode;
  bool get drawThingsTeaCache => _drawThingsTeaCache;
  bool get drawThingsCfgZeroStar => _drawThingsCfgZeroStar;

  int get editSteps => _editSteps;
  double get editCfgScale => _editCfgScale;
  int get editSampler => _editSampler;
  double get editShift => _editShift;
  int get editSeedMode => _editSeedMode;

  String get comfyEditWorkflowId => _comfyEditWorkflowId;
  Map<String, String> get comfyEditModelChoices =>
      Map.unmodifiable(_comfyEditModelChoices);
  String get comfyEditUploadedWorkflow => _comfyEditUploadedWorkflow;

  /// The user's chosen file for a preset's model slot, or null if unpicked.
  String? comfyEditModelChoice(String presetId, String token) =>
      _comfyEditModelChoices['$presetId/$token'];

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

    _editSteps = prefs?.getInt(k('image_gen_edit_steps')) ?? kEditRecommendedSteps;
    _editCfgScale =
        prefs?.getDouble(k('image_gen_edit_cfg_scale')) ?? kEditRecommendedCfg;
    _editSampler =
        prefs?.getInt(k('draw_things_edit_sampler')) ?? kEditRecommendedSamplerInt;
    _editShift =
        prefs?.getDouble(k('draw_things_edit_shift')) ?? kEditRecommendedShift;
    _editSeedMode =
        prefs?.getInt(k('draw_things_edit_seed_mode')) ?? kEditRecommendedSeedMode;

    _comfyEditWorkflowId =
        prefs?.getString(k('comfy_edit_workflow_id')) ?? 'qwen_image_edit';
    _comfyEditModelChoices = _decodeStringMap(
      prefs?.getString(k('comfy_edit_model_choices')),
    );
    _comfyEditUploadedWorkflow =
        prefs?.getString(k('comfy_edit_uploaded_workflow')) ?? '';
  }

  static Map<String, String> _decodeStringMap(String? s) {
    if (s == null || s.isEmpty) return {};
    try {
      final m = jsonDecode(s);
      if (m is Map) {
        return m.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

  Future<void> setImageGenEnabled(bool value) async {
    _imageGenEnabled = value;
    await prefs?.setBool(k('image_gen_enabled'), value);
    notify();
  }

  Future<void> setImageGenBackend(String value) async {
    _imageGenBackend = value;
    await prefs?.setString(k('image_gen_backend'), value);
    notify();
  }

  Future<void> setLocalImageGenUrl(String value) async {
    _localImageGenUrl = value;
    await prefs?.setString(k('local_image_gen_url'), value);
    notify();
  }

  Future<void> setComfyUiUrl(String value) async {
    _comfyUiUrl = value;
    await prefs?.setString(k('comfy_ui_url'), value);
    notify();
  }

  Future<void> setImageGenPromptReview(bool value) async {
    _imageGenPromptReview = value;
    await prefs?.setBool(k('image_gen_prompt_review'), value);
    notify();
  }

  Future<void> setImageGenModel(String value) async {
    _imageGenModel = value;
    await prefs?.setString(k('image_gen_model'), value);
    notify();
  }

  Future<void> setImageGenEditModel(String value) async {
    _imageGenEditModel = value;
    await prefs?.setString(k('image_gen_edit_model'), value);
    notify();
  }

  Future<void> setImageGenSize(String value) async {
    _imageGenSize = value;
    await prefs?.setString(k('image_gen_size'), value);
    notify();
  }

  Future<void> setImageGenNegativePrompt(String value) async {
    _imageGenNegativePrompt = value;
    await prefs?.setString(k('image_gen_negative_prompt'), value);
    notify();
  }

  Future<void> setImageGenStyle(String value) async {
    _imageGenStyle = value;
    await prefs?.setString(k('image_gen_style'), value);
    notify();
  }

  Future<void> setImageGenPromptParadigm(String value) async {
    _imageGenPromptParadigm = value;
    await prefs?.setString(k('image_gen_prompt_paradigm'), value);
    notify();
  }

  Future<void> setImageGenLora(String value) async {
    _imageGenLora = value;
    await prefs?.setString(k('image_gen_lora'), value);
    notify();
  }

  Future<void> setImageGenLoraWeight(double value) async {
    _imageGenLoraWeight = value.clamp(0.0, 1.0);
    await prefs?.setDouble(k('image_gen_lora_weight'), _imageGenLoraWeight);
    notify();
  }

  /// img2img denoising strength. Clamped to the meaningful 0.0–1.0 fraction
  /// (the Studio slider narrows this further to 0.2–0.9 for usable results).
  Future<void> setImageGenDenoise(double value) async {
    _imageGenDenoise = value.clamp(0.0, 1.0);
    await prefs?.setDouble(k('image_gen_denoise'), _imageGenDenoise);
    notify();
  }

  Future<void> setImageGenSteps(int value) async {
    _imageGenSteps = value.clamp(1, 50);
    await prefs?.setInt(k('image_gen_steps'), _imageGenSteps);
    notify();
  }

  Future<void> setImageGenCfgScale(double value) async {
    _imageGenCfgScale = value.clamp(1.0, 20.0);
    await prefs?.setDouble(k('image_gen_cfg_scale'), _imageGenCfgScale);
    notify();
  }

  Future<void> setImageGenSampler(String value) async {
    _imageGenSampler = value;
    await prefs?.setString(k('image_gen_sampler'), value);
    notify();
  }

  Future<void> setImageGenScheduler(String value) async {
    _imageGenScheduler = value;
    await prefs?.setString(k('image_gen_scheduler'), value);
    notify();
  }

  Future<void> setImageGenSeed(int value) async {
    _imageGenSeed = value;
    await prefs?.setInt(k('image_gen_seed'), value);
    notify();
  }

  // Draw Things gRPC setters
  Future<void> setDrawThingsGrpcHost(String value) async {
    _drawThingsGrpcHost = value.trim();
    await prefs?.setString(k('draw_things_grpc_host'), _drawThingsGrpcHost);
    notify();
  }

  Future<void> setDrawThingsGrpcPort(int value) async {
    _drawThingsGrpcPort = value;
    await prefs?.setInt(k('draw_things_grpc_port'), value);
    notify();
  }

  Future<void> setDrawThingsSampler(int value) async {
    _drawThingsSampler = value;
    await prefs?.setInt(k('draw_things_sampler'), value);
    notify();
  }

  Future<void> setDrawThingsShift(double value) async {
    _drawThingsShift = value;
    await prefs?.setDouble(k('draw_things_shift'), value);
    notify();
  }

  Future<void> setDrawThingsSeedMode(int value) async {
    _drawThingsSeedMode = value;
    await prefs?.setInt(k('draw_things_seed_mode'), value);
    notify();
  }

  Future<void> setDrawThingsTeaCache(bool value) async {
    _drawThingsTeaCache = value;
    await prefs?.setBool(k('draw_things_tea_cache'), value);
    notify();
  }

  Future<void> setDrawThingsCfgZeroStar(bool value) async {
    _drawThingsCfgZeroStar = value;
    await prefs?.setBool(k('draw_things_cfg_zero_star'), value);
    notify();
  }

  // Edit-scoped setters (Image Studio → Edit tab). Same clamps as their txt2img
  // twins; they persist to their own keys so Create's knobs are never touched.
  Future<void> setEditSteps(int value) async {
    _editSteps = value.clamp(1, 50);
    await prefs?.setInt(k('image_gen_edit_steps'), _editSteps);
    notify();
  }

  Future<void> setEditCfgScale(double value) async {
    _editCfgScale = value.clamp(1.0, 20.0);
    await prefs?.setDouble(k('image_gen_edit_cfg_scale'), _editCfgScale);
    notify();
  }

  Future<void> setEditSampler(int value) async {
    _editSampler = value;
    await prefs?.setInt(k('draw_things_edit_sampler'), value);
    notify();
  }

  Future<void> setEditShift(double value) async {
    _editShift = value;
    await prefs?.setDouble(k('draw_things_edit_shift'), value);
    notify();
  }

  Future<void> setEditSeedMode(int value) async {
    _editSeedMode = value;
    await prefs?.setInt(k('draw_things_edit_seed_mode'), value);
    notify();
  }

  /// One-tap "Use recommended edit settings" — writes the field-tested edit
  /// recipe back into the edit-scoped knobs (never touches the Create knobs).
  Future<void> resetEditKnobsToRecommended() async {
    await setEditSteps(kEditRecommendedSteps);
    await setEditCfgScale(kEditRecommendedCfg);
    await setEditSampler(kEditRecommendedSamplerInt);
    await setEditShift(kEditRecommendedShift);
    await setEditSeedMode(kEditRecommendedSeedMode);
  }

  // ComfyUI edit setters.
  Future<void> setComfyEditWorkflowId(String value) async {
    _comfyEditWorkflowId = value;
    await prefs?.setString(k('comfy_edit_workflow_id'), value);
    notify();
  }

  Future<void> setComfyEditModelChoice(
    String presetId,
    String token,
    String file,
  ) async {
    _comfyEditModelChoices['$presetId/$token'] = file;
    await prefs?.setString(
      k('comfy_edit_model_choices'),
      jsonEncode(_comfyEditModelChoices),
    );
    notify();
  }

  Future<void> setComfyEditUploadedWorkflow(String json) async {
    _comfyEditUploadedWorkflow = json;
    await prefs?.setString(k('comfy_edit_uploaded_workflow'), json);
    notify();
  }
}
