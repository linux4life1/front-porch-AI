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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image_gen/image_gen.dart';

// ImageGenMode / ImageGenBackend / ImageModelInfo now live in the pure leaf
// image/image_gen_types.dart (imported above via the image/ barrel);
// re-exported so every existing importer of this file stays unaffected.
export 'image/image_gen_types.dart';
export 'image_gen/image_gen_local_admin.dart' show refreshA1111LorasAt;

/// Service for generating images via the remote API. Studio's host is
/// [ImageGenSettings.imageRemoteApiUrl] (Nano / OpenRouter chips); keys
/// still come from [RemoteApiKeyVault]. Chat's mouth URL is not rewritten.
///
/// Shell: every member a test double that `implements` or `extends` this
/// service overrides stays a literal instance member here, forwarding to the
/// collaborators in `image_gen/` (status, clients, admin, job, prompts, disk,
/// pack lock). Pack members that callers may invoke on a double also have
/// static `...On` twins, which run the double-safe path.
class ImageGenService extends ChangeNotifier {
  final StorageService _storage;

  late final ImageGenStatus _status = ImageGenStatus(notifyListeners);
  late final ImageGenClients _clients = ImageGenClients(_storage);
  late final ImageGenLocalAdmin _admin = ImageGenLocalAdmin(
    _storage,
    _clients,
    unloadViaService: unloadLocalModel,
  );
  late final ImageGenJob _job = ImageGenJob(
    _storage,
    _status,
    _clients,
    _admin,
    switchLocalModel: switchLocalModel,
  );
  late final ImageGenPrompts _prompts = ImageGenPrompts(_storage);
  late final ImageGenDisk _disk = ImageGenDisk(_storage, _clients, _status);
  late final ImageGenPackLock _pack = ImageGenPackLock(_status, _clients);

  /// Live generation progress (0..1) and the latest in-progress preview
  /// frame; see [ImageGenStatus]. Cleared at the start and end of every
  /// generation.
  double? get genProgress => _status.genProgress;
  Uint8List? get genPreview => _status.genPreview;

  bool get isGenerating => _status.isGenerating;
  String get statusMessage => _status.statusMessage;
  Uint8List? get lastGeneratedImage => _status.lastGeneratedImage;
  String? get lastSavedPath => _status.lastSavedPath;

  /// Whether image gen is configured and ready to use.
  bool get isConfigured => _clients.isConfigured;

  ImageGenService(this._storage);

  /// Best-effort ComfyUI VRAM nudge before a create→edit model swap (the
  /// creator pack's "Switching to edit model" stage). No-op on every other
  /// backend — DT/remote load-unload per request on their own.
  Future<void> nudgeComfyFree() => _clients.nudgeComfyFree();

  /// Generate an image from a prompt.
  ///
  /// Routes to the configured remote API (OpenRouter, Nano-GPT, etc.).
  ///
  /// Returns the image bytes on success, or null on failure.
  /// Per-parameter notes (img2img reference, seed/denoise overrides, intent,
  /// editStrength) live on [ImageGenJob.run].
  Future<Uint8List?> generateImage({
    required String prompt,
    String? negativePrompt,
    String? size,
    Uint8List? referenceImage,
    String? model,
    bool isPortrait = false,
    int? seed,
    double? denoise,
    StudioIntent intent = StudioIntent.create,
    double? editStrength,
  }) => _job.run(
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
  /// - GET `{apiUrl}/image-models`. A failed or empty response falls back
  ///   to the bundled snapshot in `_commonImageModels`.
  /// The list the last [fetchImageModels] read, without asking again.
  List<ImageModelInfo> get cachedImageModels => _clients.remoteModels;

  Future<List<ImageModelInfo>> fetchImageModels() async {
    final account = _clients.remoteAccount;
    final apiUrl = account.url;
    final apiKey = account.key;
    // No account = no models. This used to fall back to the curated catalog,
    // which is how the Remote API option showed a real-looking model menu to
    // a user with no key configured at all — who reasonably concluded the
    // whole thing was free and ready, then hit "No API key configured." on
    // Generate (maintainer report, 2026-08-13). The bundled list is the
    // offline fallback for a CONFIGURED provider whose listing fetch fails,
    // never a stand-in for having an account.
    if (apiUrl.isEmpty || apiKey.isEmpty) return const [];

    final models = remoteApiUrlIsXai(apiUrl)
        ? await fetchXaiImageModels(apiUrl, apiKey)
        : isOpenRouterStyle(apiUrl)
        ? await fetchOpenRouterImageModels(apiUrl, apiKey)
        : await fetchNanoImageModels(apiUrl, apiKey);
    _clients.remoteModels = models;
    return models;
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
  /// `_buildPromptContext` in [ImageGenPrompts] (data-bag assembly + the custom-vs-lastMessage rule only — zero
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
  }) => _prompts.generateSmartPrompt(
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
      _admin.testLocalConnection(baseUrl);

  /// Fetch available checkpoints from an A1111 / Draw Things server.
  ///
  /// For Draw Things, uses gRPC. For A1111, uses HTTP.
  Future<List<String>> fetchA1111Models(String baseUrl) =>
      _admin.fetchA1111Models(baseUrl);

  /// Fetch models from a Draw Things server.
  ///
  /// Uses the Draw Things gRPC CLI to fetch available .ckpt models (via the
  /// special Echo('models') response). LoRAs come from [fetchDrawThingsLoras].
  Future<List<String>> fetchDrawThingsModels(String baseUrl) =>
      _admin.fetchDrawThingsModels();

  /// `custom.json` version of each local checkpoint. The passed URL is
  /// ignored; the host comes from settings, same as [fetchDrawThingsLoras].
  Future<Map<String, String>> fetchDrawThingsModelVersions(String baseUrl) =>
      _admin.fetchDrawThingsModelVersions();

  /// See [ImageGenLocalAdmin.fetchDrawThingsLoras].
  Future<List<LoraOption>> fetchDrawThingsLoras(String baseUrl) =>
      _admin.fetchDrawThingsLoras();

  /// ComfyUI discovery — checkpoints / LoRAs / samplers all come from one
  /// GET /object_info payload (see [ComfyUiService]); URL from settings.
  Future<List<String>> fetchComfyModels(String baseUrl) =>
      _clients.comfyUi.fetchModels();

  /// Checkpoints + diffusion_models + encoders + VAE + LoRAs.
  Future<ComfyFileCatalog> fetchComfyCatalog(String baseUrl) =>
      _clients.comfyUi.fetchCatalog();

  /// See [ImageGenLocalAdmin.fetchComfyLoras].
  Future<List<LoraOption>> fetchComfyLoras(String baseUrl) =>
      _admin.fetchComfyLoras();

  Future<List<String>> fetchComfySamplers(String baseUrl) =>
      _clients.comfyUi.fetchSamplers();

  /// See [ImageGenLocalAdmin.fetchA1111Loras].
  Future<List<LoraOption>> fetchA1111Loras(String baseUrl) =>
      _admin.fetchA1111Loras(baseUrl);

  /// See [ImageGenLocalAdmin.unloadLocalModel].
  Future<bool> unloadLocalModel(String baseUrl) =>
      _admin.unloadLocalModel(baseUrl);

  /// See [ImageGenLocalAdmin.switchLocalModel].
  Future<bool> switchLocalModel(String baseUrl, String modelName) =>
      _admin.switchLocalModel(baseUrl, modelName);

  /// Fetch available samplers from an A1111 / Draw Things server.
  ///
  /// Endpoint: GET /sdapi/v1/samplers
  /// Returns sampler names (the `name` field from each entry).
  Future<List<String>> fetchA1111Samplers(String baseUrl) =>
      _admin.fetchA1111Samplers(baseUrl);

  /// See [ImageGenLocalAdmin.fetchA1111Schedulers].
  Future<List<String>> fetchA1111Schedulers(String baseUrl) =>
      _admin.fetchA1111Schedulers(baseUrl);

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
  }) => buildA1111PayloadMap(
    prompt: prompt,
    negativePrompt: negativePrompt,
    width: width,
    height: height,
    steps: steps,
    cfgScale: cfgScale,
    samplerName: samplerName,
    scheduler: scheduler,
    seed: seed,
    referenceImageB64: referenceImageB64,
    denoise: denoise,
  );

  /// Save the last generated image to disk.
  ///
  /// Returns the saved file path, or null on failure.
  ///
  /// [preferredFileName] — optional basename (e.g. package import). Sanitized
  /// and uniquified if a file already exists so back-to-back writes never
  /// collide on the same millisecond (review 03d46d9a finding 1).
  /// When omitted, uses `img_<ms>.png` with the same collision guard.
  Future<String?> saveImageToDisk([
    Uint8List? imageBytes,
    String? preferredFileName,
  ]) => _disk.saveImageToDisk(imageBytes, preferredFileName);

  /// Save a generated image as a character avatar to the characters directory.
  ///
  /// Unlike [saveImageToDisk], this saves to the characters directory
  /// (`KoboldManager/Characters/`) so cloud sync picks it up.
  /// Returns the saved file path, or null on failure.
  Future<String?> saveAvatarToDisk(
    Uint8List? imageBytes, {
    String? characterName,
  }) => _disk.saveAvatarToDisk(imageBytes, characterName: characterName);

  /// Build a prompt for the given generation mode (static quality path, no
  /// LLM). See [ImageGenPrompts.buildPrompt].
  String buildPrompt({
    required ImageGenMode mode,
    String? customPrompt,
    String? lastMessage,
    String? characterName,
    String? characterDescription,
    String? characterPersonality,
    String? scenario,
    String? worldInfo,
    String? personaName,
    String? personaText,
    List<String>? recentMessages,
    String? currentExpression,
    String? timeOfDay,
    String? lightingHint,
    bool isGroupNonObserver = false,
    String? currentSpeakerId,
    String? userInstruction,
  }) => _prompts.buildPrompt(
    mode: mode,
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

  /// `POST /sdapi/v1/refresh-loras` — see [refreshA1111LorasAt].
  Future<bool> refreshA1111Loras(String baseUrl) =>
      refreshA1111LorasAt(baseUrl);

  /// See [startExpressionPackOn].
  Future<List<String>?> startExpressionPack(
    List<String> emotions,
    Future<List<String>> Function(List<String> emotions) driver,
  ) => startExpressionPackOn(this, emotions, driver);

  /// See [expressionFrameOn].
  Future<Uint8List?> expressionFrame({
    required String prompt,
    String? negativePrompt,
    String? size,
    Uint8List? referenceImage,
    int? seed,
    double? denoise,
    StudioIntent intent = StudioIntent.create,
    double? editStrength,
  }) => expressionFrameOn(
    this,
    prompt: prompt,
    negativePrompt: negativePrompt,
    size: size,
    referenceImage: referenceImage,
    seed: seed,
    denoise: denoise,
    intent: intent,
    editStrength: editStrength,
  );

  /// Whether a cancel is still waiting for the next ComfyUI post; for tests.
  bool get comfyCancelIsPending => _pack.comfyCancelIsPending;

  /// See [cancelJobOn].
  Future<void> cancelJob() => cancelJobOn(this);

  // The pack members below are static so a caller holding a test double that
  // only `implements` this service still runs them: the double has none of
  // this library's private members, so [_packLockOf] finds no lock on it.

  /// The pack lock of a real service; null on a test double.
  static ImageGenPackLock? _packLockOf(ImageGenService gen) {
    try {
      return gen._pack;
    } on NoSuchMethodError {
      return null;
    }
  }

  /// Runs one pack inside a single hold of the generation lock, so nothing
  /// else can start between two of its frames. Null (and the status says
  /// "Already generating.") when a generation is already running, without
  /// calling [driver]. On a test double the pack simply runs.
  static Future<List<String>?> startExpressionPackOn(
    ImageGenService gen,
    List<String> emotions,
    Future<List<String>> Function(List<String> emotions) driver,
  ) async {
    final lock = _packLockOf(gen);
    if (lock == null) return driver(List<String>.from(emotions));
    return lock.start(emotions, driver);
  }

  /// One pack frame. Inside a pack flight it runs under the flight's lock;
  /// otherwise it is an ordinary single generation.
  static Future<Uint8List?> expressionFrameOn(
    ImageGenService gen, {
    required String prompt,
    String? negativePrompt,
    String? size,
    Uint8List? referenceImage,
    int? seed,
    double? denoise,
    StudioIntent intent = StudioIntent.create,
    double? editStrength,
  }) {
    final lock = _packLockOf(gen);
    if (lock != null && lock.inFlight) {
      return gen._job.run(
        prompt: prompt,
        negativePrompt: negativePrompt,
        size: size,
        referenceImage: referenceImage,
        seed: seed,
        denoise: denoise,
        intent: intent,
        editStrength: editStrength,
        fromPack: true,
      );
    }
    return gen.generateImage(
      prompt: prompt,
      negativePrompt: negativePrompt,
      size: size,
      referenceImage: referenceImage,
      seed: seed,
      denoise: denoise,
      intent: intent,
      editStrength: editStrength,
    );
  }

  /// Stops the job the server is running for this service: on ComfyUI the
  /// prompt is taken off the queue or interrupted. The other backends have no
  /// job to stop from here; they finish the picture they are on.
  static Future<void> cancelJobOn(ImageGenService gen) async {
    final lock = _packLockOf(gen);
    if (lock == null) return;
    await lock.cancel();
  }
}
