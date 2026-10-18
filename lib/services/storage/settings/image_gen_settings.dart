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

import '../../image/image_gen_lora_slots.dart';
import 'image_gen/image_gen.dart';
import 'image_gen_remote.dart';
import 'settings_base.dart';

export 'image_gen/comfy_ui_url_prefs.dart' show kDefaultComfyUiUrl;

/// Image generation (A1111/Draw Things/remote) + Draw Things gRPC settings.
///
/// Lifted Stage 7.
class ImageGenSettings
    with
        SettingsBase,
        ImageGenRemotePrefs,
        ComfyUiUrlPrefs,
        ComfyShiftPrefs,
        DrawThingsGrpcPrefs,
        ImageGenEditKnobPrefs {
  // Default ON since 2026-07: the feature is opt-out. Enabling only shows the
  // ✨ toolbar button and the /image command — nothing generates until a
  // backend is actually configured, so there is no overhead for users who
  // never touch it. Users who previously toggled it keep their saved choice.
  bool _imageGenEnabled = true;
  String _imageGenBackend =
      'remote'; // 'remote', 'a1111', 'drawthings', 'comfyui'
  String _localImageGenUrl = 'http://127.0.0.1:7860';
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
  List<ImageGenLoraSlot> _imageGenLoraSlots = ImageGenLoraSlot.blank();
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

  // Comfy edit: preset id or '__uploaded__', slot map, uploaded JSON.
  String _comfyEditWorkflowId = 'qwen_image_edit'; // == kQwenImageEditPreset.id
  Map<String, String> _comfyEditModelChoices = {};
  String _comfyEditUploadedWorkflow = '';
  String _comfyEditUploadedTitle = '';

  // Comfy Create: family id + slot map + BYO JSON (same shape as edit).
  String _comfyCreateWorkflowId = 'sd';
  Map<String, String> _comfyCreateModelChoices = {};
  String _comfyCreateUploadedWorkflow = '';
  String _comfyCreateUploadedTitle = '';

  bool get imageGenEnabled => _imageGenEnabled;
  String get imageGenBackend => _imageGenBackend;
  String get localImageGenUrl => _localImageGenUrl;
  String get imageGenModel => _imageGenModel;
  String get imageGenEditModel => _imageGenEditModel;
  String get imageGenSize => _imageGenSize;
  String get imageGenNegativePrompt => _imageGenNegativePrompt;
  String get imageGenStyle => _imageGenStyle;
  String get imageGenPromptParadigm => _imageGenPromptParadigm;
  List<ImageGenLoraSlot> get imageGenLoraSlots =>
      List.unmodifiable(_imageGenLoraSlots);

  /// Filled slots, in order. Empty pickers are skipped.
  List<ImageGenLoraSlot> get activeImageGenLoras => [
    for (final s in _imageGenLoraSlots)
      if (!s.isEmpty) s,
  ];

  /// Slot 0. Kept so older call sites and the web single-field still read.
  String get imageGenLora => _imageGenLoraSlots.first.file;
  double get imageGenLoraWeight => _imageGenLoraSlots.first.weight;
  double get imageGenDenoise => _imageGenDenoise;
  int get imageGenSteps => _imageGenSteps;
  double get imageGenCfgScale => _imageGenCfgScale;
  String get imageGenSampler => _imageGenSampler;
  String get imageGenScheduler => _imageGenScheduler;
  int get imageGenSeed => _imageGenSeed;

  /// Whether AI-crafted image prompts (the /image command) pause for user
  /// review/editing before being sent to the backend. Default ON.
  bool get imageGenPromptReview => _imageGenPromptReview;

  String get comfyEditWorkflowId => _comfyEditWorkflowId;
  Map<String, String> get comfyEditModelChoices =>
      Map.unmodifiable(_comfyEditModelChoices);
  String get comfyEditUploadedWorkflow => _comfyEditUploadedWorkflow;
  String get comfyEditUploadedTitle => _comfyEditUploadedTitle;

  String get comfyCreateWorkflowId => _comfyCreateWorkflowId;
  Map<String, String> get comfyCreateModelChoices =>
      Map.unmodifiable(_comfyCreateModelChoices);
  String get comfyCreateUploadedWorkflow => _comfyCreateUploadedWorkflow;
  String get comfyCreateUploadedTitle => _comfyCreateUploadedTitle;

  String? comfyCreateModelChoice(String presetId, String token) =>
      _comfyCreateModelChoices['$presetId/$token'];

  Future<void> setImageGenEnabled(bool value) async {
    _imageGenEnabled = value;
    await prefs?.setBool(k('image_gen_enabled'), value);
    notify();
  }

  /// Each backend keeps its own model and LoRA picks: a file one backend
  /// lists means nothing to another. Switching parks this backend's picks
  /// and brings back the new one's, blank the first time it is chosen.
  Future<void> setImageGenBackend(String value) async {
    final from = _imageGenBackend;
    _imageGenBackend = value;
    await prefs?.setString(k('image_gen_backend'), value);
    if (from != value) await _swapBackendPicks(from, value);
    notify();
  }

  Future<void> _swapBackendPicks(String from, String to) async {
    await prefs?.setString(
      k('image_gen_picks_$from'),
      jsonEncode({
        'model': _imageGenModel,
        'editModel': _imageGenEditModel,
        'loras': ImageGenLoraSlot.encode(_imageGenLoraSlots),
      }),
    );
    final parked = _decodeStringMap(prefs?.getString(k('image_gen_picks_$to')));
    _imageGenModel = parked['model'] ?? '';
    _imageGenEditModel = parked['editModel'] ?? '';
    _imageGenLoraSlots = ImageGenLoraSlot.decode(parked['loras']);
    await prefs?.setString(k('image_gen_model'), _imageGenModel);
    await prefs?.setString(k('image_gen_edit_model'), _imageGenEditModel);
    await _writeLoraSlots();
  }

  Future<void> setLocalImageGenUrl(String value) async {
    _localImageGenUrl = value;
    await prefs?.setString(k('local_image_gen_url'), value);
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

  Future<void> setImageGenLora(String value) =>
      setImageGenLoraSlot(0, file: value);

  Future<void> setImageGenLoraWeight(double value) =>
      setImageGenLoraSlot(0, weight: value);

  Future<void> setImageGenLoraSlot(
    int index, {
    String? file,
    double? weight,
  }) async {
    if (index < 0 || index >= kImageGenLoraSlotCount) return;
    final cur = _imageGenLoraSlots[index];
    _imageGenLoraSlots[index] = cur.copyWith(
      file: file,
      weight: weight?.clamp(0.0, 1.0),
    );
    await _persistLoraSlots();
  }

  Future<void> setImageGenLoraSlots(List<ImageGenLoraSlot> slots) async {
    _imageGenLoraSlots = ImageGenLoraSlot.fit(slots);
    await _persistLoraSlots();
  }

  Future<void> _persistLoraSlots() async {
    await _writeLoraSlots();
    notify();
  }

  Future<void> _writeLoraSlots() async {
    await prefs?.setString(
      k('image_gen_loras'),
      ImageGenLoraSlot.encode(_imageGenLoraSlots),
    );
    await prefs?.setString(k('image_gen_lora'), imageGenLora);
    await prefs?.setDouble(k('image_gen_lora_weight'), imageGenLoraWeight);
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

  Future<void> setComfyEditUploadedWorkflow(
    String json, {
    String title = '',
  }) async {
    _comfyEditUploadedWorkflow = json;
    await prefs?.setString(k('comfy_edit_uploaded_workflow'), json);
    if (title.isNotEmpty) {
      _comfyEditUploadedTitle = title;
      await prefs?.setString(k('comfy_edit_uploaded_title'), title);
    }
    notify();
  }

  Future<void> setComfyCreateWorkflowId(String value) async {
    _comfyCreateWorkflowId = value;
    await prefs?.setString(k('comfy_create_workflow_id'), value);
    notify();
  }

  Future<void> setComfyCreateModelChoice(
    String presetId,
    String token,
    String file,
  ) async {
    _comfyCreateModelChoices['$presetId/$token'] = file;
    await prefs?.setString(
      k('comfy_create_model_choices'),
      jsonEncode(_comfyCreateModelChoices),
    );
    if (presetId == 'sd' && token == '%MODEL_CHECKPOINT%') {
      _imageGenModel = file;
      await prefs?.setString(k('image_gen_model'), file);
    }
    notify();
  }

  Future<void> setComfyCreateUploadedWorkflow(
    String json, {
    String title = '',
  }) async {
    _comfyCreateUploadedWorkflow = json;
    await prefs?.setString(k('comfy_create_uploaded_workflow'), json);
    if (title.isNotEmpty) {
      _comfyCreateUploadedTitle = title;
      await prefs?.setString(k('comfy_create_uploaded_title'), title);
    }
    notify();
  }

  void load() {
    _imageGenEnabled = prefs?.getBool(k('image_gen_enabled')) ?? true;
    _imageGenBackend = prefs?.getString(k('image_gen_backend')) ?? 'remote';
    _localImageGenUrl =
        prefs?.getString(k('local_image_gen_url')) ?? 'http://127.0.0.1:7860';
    loadComfyUiUrlPrefs();
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
    _imageGenLoraSlots = ImageGenLoraSlot.decode(
      prefs?.getString(k('image_gen_loras')),
      legacyFile: prefs?.getString(k('image_gen_lora')) ?? '',
      legacyWeight: prefs?.getDouble(k('image_gen_lora_weight')) ?? 0.8,
    );
    _imageGenDenoise = prefs?.getDouble(k('image_gen_denoise')) ?? 0.5;
    _imageGenSteps = prefs?.getInt(k('image_gen_steps')) ?? 4;
    _imageGenCfgScale = prefs?.getDouble(k('image_gen_cfg_scale')) ?? 1.0;
    _imageGenSampler = prefs?.getString(k('image_gen_sampler')) ?? 'Euler a';
    _imageGenScheduler =
        prefs?.getString(k('image_gen_scheduler')) ?? 'Automatic';
    _imageGenSeed = prefs?.getInt(k('image_gen_seed')) ?? -1;
    _imageGenPromptReview =
        prefs?.getBool(k('image_gen_prompt_review')) ?? true;

    loadDrawThingsGrpcPrefs();
    loadEditKnobPrefs();

    _comfyEditWorkflowId =
        prefs?.getString(k('comfy_edit_workflow_id')) ?? 'qwen_image_edit';
    _comfyEditModelChoices = _decodeStringMap(
      prefs?.getString(k('comfy_edit_model_choices')),
    );
    _comfyEditUploadedWorkflow =
        prefs?.getString(k('comfy_edit_uploaded_workflow')) ?? '';
    _comfyEditUploadedTitle =
        prefs?.getString(k('comfy_edit_uploaded_title')) ?? '';
    _comfyCreateWorkflowId =
        prefs?.getString(k('comfy_create_workflow_id')) ?? 'sd';
    _comfyCreateModelChoices = _decodeStringMap(
      prefs?.getString(k('comfy_create_model_choices')),
    );
    _comfyCreateUploadedWorkflow =
        prefs?.getString(k('comfy_create_uploaded_workflow')) ?? '';
    _comfyCreateUploadedTitle =
        prefs?.getString(k('comfy_create_uploaded_title')) ?? '';
    loadComfyShiftPrefs();
    loadImageRemotePrefs();
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
}
