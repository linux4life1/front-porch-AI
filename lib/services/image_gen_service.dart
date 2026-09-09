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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/grpc/draw_things_grpc_service.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/capability/capability.dart';

// ImageGenMode / ImageGenBackend / ImageModelInfo now live in the pure leaf
// image/image_gen_types.dart (imported above via the image/ barrel);
// re-exported so every existing importer of this file stays unaffected.
export 'image/image_gen_types.dart';

part 'image_gen_service.generate.dart';
part 'image_gen_service.prompt.dart';
part 'image_gen_service.local_admin.dart';
part 'image_gen_service.backends.dart';
part 'image_gen_service.catalog.dart';

/// Parse a "WxH" size string into width and height integers.
(int width, int height) _parseSize(String size) {
  final parts = size.split('x');
  if (parts.length == 2) {
    final w = int.tryParse(parts[0]) ?? 1024;
    final h = int.tryParse(parts[1]) ?? 1024;
    return (w, h);
  }
  return (1024, 1024);
}

/// Service for generating images via the remote API. Reuses the same API
/// URL/key configured for text generation (OpenRouter, Nano-GPT, or any
/// OpenAI-compatible endpoint).
///
/// Split-god-file shell: the 19 members the 3 protected test fakes
/// `implements ImageGenService` override stay literal instance members here
/// (9 as one-line stubs into `_xImpl` parts); everything unfaked moved out.
class ImageGenService extends ChangeNotifier {
  final StorageService _storage;

  bool _isGenerating = false;
  String _statusMessage = '';
  Uint8List? _lastGeneratedImage;
  String? _lastSavedPath;

  /// Live generation progress (0..1) and the latest in-progress preview
  /// frame, so the UI can show the image "coming to life" instead of a
  /// spinner. Fed per backend: A1111 polls /sdapi/v1/progress (percent +
  /// preview), ComfyUI streams its WebSocket (percent + preview when the
  /// server has previews enabled), Draw Things reports sampling steps
  /// (percent only). Remote APIs return in one shot — both stay null there
  /// (indeterminate). Cleared at the start and end of every generation.
  double? _genProgress;
  Uint8List? _genPreview;
  double? get genProgress => _genProgress;
  Uint8List? get genPreview => _genPreview;

  void _updateGenProgress(double? progress, [Uint8List? preview]) {
    _genProgress = progress;
    if (preview != null) _genPreview = preview;
    notifyListeners();
  }

  // Extensions can't call @protected notifyListeners(); this is the forwarder.
  void _notify() => notifyListeners();

  /// The checkpoint name that is currently loaded on the local A1111 server.
  /// Used to skip redundant unload→reload cycles that can leave tensors
  /// split across CPU and CUDA on Windows/nVidia setups.
  String? _lastLoadedCheckpoint;

  bool get isGenerating => _isGenerating;
  String get statusMessage => _statusMessage;
  Uint8List? get lastGeneratedImage => _lastGeneratedImage;
  String? get lastSavedPath => _lastSavedPath;

  /// Whether image gen is configured and ready to use.
  bool get isConfigured {
    if (!_storage.imageGenSettings.imageGenEnabled) return false;
    final backend = ImageGenBackend.fromKey(
      _storage.imageGenSettings.imageGenBackend,
    );
    switch (backend) {
      case ImageGenBackend.remote:
        return _storage.backendSettings.remoteApiKey.isNotEmpty &&
            _storage.imageGenSettings.imageGenModel.isNotEmpty;
      case ImageGenBackend.a1111:
        return _storage.imageGenSettings.localImageGenUrl.isNotEmpty;
      case ImageGenBackend.drawThings:
        return _storage.imageGenSettings.drawThingsGrpcHost.isNotEmpty;
      case ImageGenBackend.comfyUi:
        return _storage.imageGenSettings.comfyUiUrl.isNotEmpty;
    }
  }

  DrawThingsGrpcService? _drawThingsGrpc;
  ComfyUiService? _comfyUi;

  ComfyUiService get _ensureComfyUi {
    final url = _storage.imageGenSettings.comfyUiUrl;
    if (_comfyUi == null || _comfyUi!.baseUrl != url) {
      _comfyUi = ComfyUiService(baseUrl: url);
    }
    return _comfyUi!;
  }

  // Thin delegation hook for prompt construction.
  // Full ownership of ImageGenContext mapping semantics, mode contracts
  // (no-personality portraits, and customPrompt's scene-distillation fallback
  // when the prompt is empty but recent chat narrative is present), style
  // enforcement, LLM smart path, and static fallbacks lives in ImagePromptBuilder.
  // Keep prompt blocks in sync: changes to ctx construction here must be mirrored in
  // any direct ImageGenContext sites and the builder's own
  // _buildStatic / buildPrompt / _generateSmartWith. The builder is stateless/prompt-only
  // (no reset calls needed). ImageGenService owns no prompt scalars that require zeroing
  // on chat startNew / setActive / load (per-call snapshot from _storage is authoritative).
  // See ImagePromptBuilder for the authoritative mode semantics and style rules.
  late final ImagePromptBuilder _promptBuilder = ImagePromptBuilder();

  DrawThingsGrpcService get _ensureDrawThingsGrpc {
    final h = _storage.imageGenSettings.drawThingsGrpcHost;
    final p = _storage.imageGenSettings.drawThingsGrpcPort;
    // Recreate if host/port changed since last use (cheap; keeps things in sync with settings)
    if (_drawThingsGrpc == null ||
        _drawThingsGrpc!.host != h ||
        _drawThingsGrpc!.port != p) {
      _drawThingsGrpc = DrawThingsGrpcService(host: h, port: p);
    }
    return _drawThingsGrpc!;
  }

  ImageGenService(this._storage);

  /// Best-effort ComfyUI VRAM nudge before a create→edit model swap (the
  /// creator pack's "Switching to edit model" stage). No-op on every other
  /// backend — DT/remote load-unload per request on their own.
  Future<void> nudgeComfyFree() async {
    final backend = ImageGenBackend.fromKey(
      _storage.imageGenSettings.imageGenBackend,
    );
    if (backend != ImageGenBackend.comfyUi) return;
    await _ensureComfyUi.freeMemory();
  }

  /// Build the images directory path.
  Directory get _imagesDir =>
      Directory(path.join(_storage.rootPath ?? '', 'KoboldManager', 'images'));

  /// Generate an image from a prompt.
  ///
  /// Routes to the configured remote API (OpenRouter, Nano-GPT, etc.).
  ///
  /// Returns the image bytes on success, or null on failure.
  Future<Uint8List?> generateImage({
    required String prompt,
    String? negativePrompt,
    String? size,
    Uint8List?
    referenceImage, // img2img reference: honored by all three local backends
    // (Draw Things, A1111, ComfyUI) at imageGenDenoise strength; remote APIs
    // have no img2img endpoint here, so they ignore it.
    String? model,
    bool isPortrait = false,
    // Per-call overrides for the stored seed/denoise settings; used by batch
    // flows (expression packs) that need a shared fixed seed and fixed denoise
    // across every image without touching the user's persisted settings.
    // Remote APIs ignore them (no seed/denoise support on those endpoints).
    int? seed,
    double? denoise,
    // Which surface asked. Create (default) keeps every existing path
    // byte-identical; Edit routes an edit-capable model to edit-conditioning
    // and resolves the EDIT model slot. Passed by the Studio's Edit tab and
    // by edit-first expression packs (Studio dialog + the creator panel).
    StudioIntent intent = StudioIntent.create,
    // Edit-only: how strongly the instruction changes the reference (higher =
    // more change). Overrides the edit profile's default strength when set, so
    // the Edit tab can offer a "how much should change" control. Ignored outside
    // the edit path.
    double? editStrength,
  }) => _generateImageImpl(
    prompt: prompt,
    negativePrompt: negativePrompt,
    size: size,
    referenceImage: referenceImage,
    model: model,
    isPortrait: isPortrait,
    seed: seed,
    denoise: denoise,
    intent: intent,
    editStrength: editStrength,
  );

  /// Fetch available image models.
  ///
  /// Behavior depends on which API backend is configured:
  ///
  /// **OpenRouter** (detected by URL containing "openrouter.ai"):
  /// - Calls `/models?output_modalities=image` to get real image-capable models
  /// - Returns what OpenRouter provides (includes pricing info from their API)
  /// - If API fails: returns empty list with error logged
  ///
  /// **Nano-GPT and others**:
  /// - Returns the curated list of known image models (Nano-GPT's /models
  ///   endpoint only returns text models; there is no image-specific listing API)
  Future<List<ImageModelInfo>> fetchImageModels() async {
    final apiUrl = _storage.backendSettings.remoteApiUrl;
    final apiKey = _storage.backendSettings.remoteApiKeyFor(apiUrl);
    // No account = no models. This used to fall back to the curated catalog,
    // which is how the Remote API option showed a real-looking model menu to
    // a user with no key configured at all — who reasonably concluded the
    // whole thing was free and ready, then hit "No API key configured." on
    // Generate (maintainer report, 2026-08-13). The catalog below is a
    // convenience for CONFIGURED providers without an image-listing endpoint
    // (Nano-GPT), never a stand-in for having an account.
    if (apiUrl.isEmpty || apiKey.isEmpty) return const [];

    // Detect if this is OpenRouter
    final isOpenRouter = _isOpenRouterStyle(apiUrl);

    if (isOpenRouter) {
      return _fetchOpenRouterImageModels(apiUrl, apiKey);
    } else {
      // For Nano-GPT and other providers: return curated list
      return List.from(_commonImageModels);
    }
  }

  /// Available style labels for UI display.
  static const Map<String, String> styleLabels = {
    'photorealistic': 'Photorealistic',
    'anime': 'Anime / Manga',
    'fantasy_art': 'Fantasy Art',
    'oil_painting': 'Oil Painting',
    'digital_art': 'Digital Art',
    'watercolor': 'Watercolor',
  };

  /// Use the active LLM to craft a concise, effective image prompt from raw context.
  ///
  /// Thin delegation to ImagePromptBuilder — see there for mode semantics and style rules
  /// (portrait = appearance + expression only; customPrompt = the user's text verbatim, or,
  /// when that text is empty, a distilled visualization of the current scene from the
  /// supplied recent chat narrative; style enforcement for both paradigms, etc.).
  /// Keep prompt blocks in sync with ImagePromptBuilder (and ctx construction in call sites
  /// like chat_page._showImageGenDialog and the /image slash command). Builder is stateless/prompt-only.
  ///
  /// The flat params are assembled into a typed [ImageGenContext] by the tiny pure helper
  /// [_buildPromptContext] (data-bag assembly + the custom-vs-lastMessage rule only — zero
  /// prompt/distillation/style/LLM logic, which all lives in ImagePromptBuilder).
  ///
  /// [userInstruction] is free text the user typed in the studio box before Craft; it is
  /// forwarded to the LLM as extra guidance so it "parses into the image prompt".
  Future<String> generateSmartPrompt({
    required ImageGenMode mode,
    required String style,
    LLMService? llmService,
    String? customPrompt,
    String? lastMessage,
    String? characterName,
    String? characterDescription,
    String?
    characterPersonality, // kept for signature compatibility during transition (ignored for visuals)
    String? scenario,
    String? worldInfo,
    String? personaName,
    String? personaText,
    List<String>? recentMessages,
    // Stage 4: richer optional fields for better prompts (expression/pose, time/lighting, group speaker targeting).
    // Forwarded to thin ctx builder. Keep in sync with buildPrompt sig, _buildPromptContext, studio craft/ctor/show, chat_page launch.
    String? currentExpression,
    String? timeOfDay,
    String? lightingHint,
    bool isGroupNonObserver = false,
    String? currentSpeakerId,
    // Text the user typed in the studio box pre-Craft (passed to the LLM as an
    // instruction to "parse into" the image prompt).
    String? userInstruction,
  }) => _generateSmartPromptImpl(
    mode: mode,
    style: style,
    llmService: llmService,
    customPrompt: customPrompt,
    lastMessage: lastMessage,
    characterName: characterName,
    characterDescription: characterDescription,
    characterPersonality: characterPersonality,
    scenario: scenario,
    worldInfo: worldInfo,
    personaName: personaName,
    personaText: personaText,
    recentMessages: recentMessages,
    currentExpression: currentExpression,
    timeOfDay: timeOfDay,
    lightingHint: lightingHint,
    isGroupNonObserver: isGroupNonObserver,
    currentSpeakerId: currentSpeakerId,
    userInstruction: userInstruction,
  );

  /// Test whether a local image-gen server is reachable.
  ///
  /// For Draw Things, uses gRPC. For ComfyUI, GET /system_stats. For A1111,
  /// GET /sdapi/v1/sd-models.
  Future<bool> testLocalConnection(String baseUrl) =>
      _testLocalConnectionImpl(baseUrl);

  /// Fetch available checkpoints from an A1111 / Draw Things server.
  ///
  /// For Draw Things, uses gRPC. For A1111, uses HTTP.
  Future<List<String>> fetchA1111Models(String baseUrl) =>
      _fetchA1111ModelsImpl(baseUrl);

  /// Fetch models from a Draw Things server.
  ///
  /// Uses the Draw Things gRPC CLI to fetch available .ckpt models (via the
  /// special Echo('models') response). LoRAs come from [fetchDrawThingsLoras].
  Future<List<String>> fetchDrawThingsModels(String baseUrl) async {
    try {
      final grpcService = _ensureDrawThingsGrpc;
      return await grpcService.fetchModels();
    } catch (e) {
      debugPrint('ImageGen: fetchDrawThingsModels failed: $e');
      return [];
    }
  }

  /// Fetch LoRA files from a Draw Things server (gRPC CLI op 'loras' — the
  /// same Echo('models') listing as [fetchDrawThingsModels], filtered to
  /// LoRAs). The selected name is applied natively via the generation config.
  ///
  /// Draw Things does not expose per-model compatibility over its gRPC surface,
  /// so family is detected from the (canonical) file name only —
  /// [LoraOption.familyFromMetadata] is false, which makes the UI warn on a
  /// mismatch rather than hide it.
  Future<List<LoraOption>> fetchDrawThingsLoras(String baseUrl) async {
    try {
      final grpcService = _ensureDrawThingsGrpc;
      final names = await grpcService.fetchLoras();
      return names.map((n) => ImageModelFamily.classifyLora(n)).toList();
    } catch (e) {
      debugPrint('ImageGen: fetchDrawThingsLoras failed: $e');
      return [];
    }
  }

  /// ComfyUI discovery — checkpoints / LoRAs / samplers all come from one
  /// GET /object_info payload (see [ComfyUiService]); URL from settings.
  Future<List<String>> fetchComfyModels(String baseUrl) =>
      _ensureComfyUi.fetchModels();

  /// ComfyUI LoRAs, enriched with base-model family. Names come from
  /// /object_info; the family is read per-LoRA from the embedded safetensors
  /// metadata via /view_metadata (authoritative), falling back to the file name
  /// when a model exposes none. Metadata reads run in small concurrent batches
  /// so a large library doesn't stall the picker, and any failure degrades
  /// silently to name detection.
  Future<List<LoraOption>> fetchComfyLoras(String baseUrl) async {
    final comfy = _ensureComfyUi;
    final names = await comfy.fetchLoras();
    final out = <LoraOption>[];
    const batch = 8;
    for (var i = 0; i < names.length; i += batch) {
      final slice = names.skip(i).take(batch);
      final metas = await Future.wait(slice.map(comfy.fetchLoraMetadata));
      var j = 0;
      for (final n in slice) {
        final meta = metas[j++];
        out.add(
          ImageModelFamily.classifyLora(n, metadata: meta.isEmpty ? null : meta),
        );
      }
    }
    return out;
  }

  Future<List<String>> fetchComfySamplers(String baseUrl) =>
      _ensureComfyUi.fetchSamplers();

  Future<List<String>> fetchComfySchedulers(String baseUrl) =>
      _ensureComfyUi.fetchSchedulers();

  /// Fetch LoRAs from an A1111 / Forge / SD.Next server, enriched with
  /// base-model family.
  ///
  /// Endpoint: GET /sdapi/v1/loras — each entry carries a `metadata` block that
  /// usually includes `ss_base_model_version` / `modelspec.architecture`, which
  /// gives an authoritative family (this is the same field A1111's own UI uses).
  /// When a LoRA exposes no metadata we fall back to file-name detection.
  /// Draw Things uses [fetchDrawThingsLoras] instead (no HTTP endpoint).
  Future<List<LoraOption>> fetchA1111Loras(String baseUrl) =>
      _fetchA1111LorasImpl(baseUrl);

  /// Unload the currently active model from memory on a local server.
  ///
  /// Calls `POST /sdapi/v1/unload-checkpoint` (standard A1111 endpoint).
  /// Draw Things may support this via its A1111-compat layer.
  /// If the server doesn't support it the error is silently ignored —
  /// model switching via [switchLocalModel] will still proceed.
  ///
  /// Returns true if the server acknowledged the unload (HTTP 200).
  Future<bool> unloadLocalModel(String baseUrl) =>
      _unloadLocalModelImpl(baseUrl);

  /// Switch the active checkpoint on a local A1111 / Draw Things server.
  ///
  /// Sequence:
  ///   1. `POST /sdapi/v1/unload-checkpoint` — free current model from memory
  ///      (silently ignored if not supported by the server)
  ///   2. `POST /sdapi/v1/options` with the new model name — trigger model load
  ///   3. Poll `GET /sdapi/v1/options` to confirm the model is fully loaded
  ///      on the GPU before returning, preventing tensor device mismatches.
  ///
  /// Returns true if the model was successfully switched and confirmed ready.
  Future<bool> switchLocalModel(String baseUrl, String modelName) =>
      _switchLocalModelImpl(baseUrl, modelName);

  /// Fetch available samplers from an A1111 / Draw Things server.
  ///
  /// Endpoint: GET /sdapi/v1/samplers
  /// Returns sampler names (the `name` field from each entry).
  Future<List<String>> fetchA1111Samplers(String baseUrl) =>
      _fetchA1111SamplersImpl(baseUrl);

  /// Fetch available schedulers from an A1111 / Forge / SD.Next server.
  ///
  /// Endpoint: GET /sdapi/v1/schedulers
  /// Returns scheduler names (the `name` field from each entry). Older forks
  /// (and Draw Things' A1111 shim) predate this endpoint and answer 404 — that
  /// degrades silently to an empty list, so the UI simply offers only
  /// 'Automatic' there.
  Future<List<String>> fetchA1111Schedulers(String baseUrl) =>
      _fetchA1111SchedulersImpl(baseUrl);

  /// Build the AUTOMATIC1111 generation payload shared by the txt2img and
  /// img2img endpoints. Pure — unit-tested. When [referenceImageB64] is
  /// non-null/non-empty the caller must POST to `/sdapi/v1/img2img`, and this
  /// adds `init_images` + `denoising_strength` ([denoise]); otherwise it is a
  /// plain txt2img payload for `/sdapi/v1/txt2img`.
  static Map<String, dynamic> buildA1111Payload({
    required String prompt,
    required String negativePrompt,
    required int width,
    required int height,
    required int steps,
    required double cfgScale,
    required String samplerName,
    required String scheduler,
    required int seed,
    String? referenceImageB64,
    double denoise = 0.5,
  }) {
    final isImg2Img =
        referenceImageB64 != null && referenceImageB64.isNotEmpty;
    return <String, dynamic>{
      'prompt': prompt,
      'negative_prompt': negativePrompt,
      'width': width,
      'height': height,
      'steps': steps,
      'cfg_scale': cfgScale,
      'sampler_name': samplerName,
      // Only pin the scheduler when the user picked an explicit one. 'Automatic'
      // omits the field so A1111 uses its own default (and older forks that
      // don't know the field never see it). Newer A1111/Forge builds accept
      // `scheduler` alongside `sampler_name`.
      if (scheduler.isNotEmpty && scheduler != 'Automatic')
        'scheduler': scheduler,
      'seed': seed,
      'batch_size': 1,
      if (isImg2Img) 'init_images': [referenceImageB64],
      if (isImg2Img) 'denoising_strength': denoise,
      // NOTE: override_settings is intentionally omitted here.
      // Passing sd_model_checkpoint inside override_settings causes A1111 to
      // attempt a model reload mid-request, which splits tensors across
      // cpu and cuda and throws:
      //   "Expected all tensors to be on the same device"
      // The model switch is already handled by switchLocalModel() above.
    };
  }
}
