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
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/grpc/draw_things_grpc_service.dart';

/// Available image generation modes.
enum ImageGenMode {
  customPrompt,
  visualizeScene,
  fromLastMessage,
  characterPortrait,
  chatBackground,
  userAvatar,
}

/// Local image-generation backend options.
enum ImageGenBackend {
  remote,
  a1111,
  drawThings;

  static ImageGenBackend fromKey(String key) {
    switch (key) {
      case 'a1111':      return ImageGenBackend.a1111;
      case 'drawthings': return ImageGenBackend.drawThings;
      default:           return ImageGenBackend.remote;
    }
  }

  String get key {
    switch (this) {
      case ImageGenBackend.a1111:      return 'a1111';
      case ImageGenBackend.drawThings: return 'drawthings';
      case ImageGenBackend.remote:     return 'remote';
    }
  }

  String get label {
    switch (this) {
      case ImageGenBackend.a1111:      return 'AUTOMATIC1111';
      case ImageGenBackend.drawThings: return 'Draw Things';
      case ImageGenBackend.remote:     return 'Remote API';
    }
  }
}

/// Metadata for an image model available via the remote API.
class ImageModelInfo {
  final String id;
  final String name;
  /// Whether this model costs extra per-prompt (true) or is included
  /// with a Nano-GPT Pro subscription (false).
  final bool isPaid;
  /// Pricing information from OpenRouter (if available).
  /// Format: "prompt_cost / completion_cost per token" or raw JSON string.
  final String? pricingInfo;

  const ImageModelInfo({
    required this.id,
    this.name = '',
    this.isPaid = true,
    this.pricingInfo,
  });

  String get displayName => name.isNotEmpty ? name : id;

  /// Human-readable description including pricing if available.
  String get description {
    if (pricingInfo != null && pricingInfo!.isNotEmpty) {
      return '$displayName — $pricingInfo';
    }
    return displayName;
  }
}

/// Service for generating images via the remote API.
///
/// Reuses the same API URL and key configured for text generation
/// (OpenRouter, Nano-GPT, or any OpenAI-compatible endpoint).
class ImageGenService extends ChangeNotifier {
  final StorageService _storage;

  bool _isGenerating = false;
  String _statusMessage = '';
  Uint8List? _lastGeneratedImage;
  String? _lastSavedPath;

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
    if (!_storage.imageGenEnabled) return false;
    final backend = ImageGenBackend.fromKey(_storage.imageGenBackend);
    switch (backend) {
      case ImageGenBackend.remote:
        return _storage.remoteApiKey.isNotEmpty && _storage.imageGenModel.isNotEmpty;
      case ImageGenBackend.a1111:
      case ImageGenBackend.drawThings:
        return _storage.localImageGenUrl.isNotEmpty;
    }
  }

  DrawThingsGrpcService? _drawThingsGrpc;

  DrawThingsGrpcService get _ensureDrawThingsGrpc {
    _drawThingsGrpc ??= DrawThingsGrpcService(host: '127.0.0.1', port: 7859);
    return _drawThingsGrpc!;
  }

  ImageGenService(this._storage);

  /// Build the images directory path.
  Directory get _imagesDir => Directory(
      path.join(_storage.rootPath ?? '', 'KoboldManager', 'images'));

  /// Generate an image from a prompt.
  ///
  /// Routes to the configured remote API (OpenRouter, Nano-GPT, etc.).
  ///
  /// Returns the image bytes on success, or null on failure.
  Future<Uint8List?> generateImage({
    required String prompt,
    String negativePrompt = '',
    String? size,
    String? model,
    bool isPortrait = false,
  }) async {
    _isGenerating = true;
    _statusMessage = 'Generating image...';
    _lastGeneratedImage = null;
    _lastSavedPath = null;
    notifyListeners();

    try {
      Uint8List imageBytes;

      final backend = ImageGenBackend.fromKey(_storage.imageGenBackend);

      if (backend == ImageGenBackend.a1111 || backend == ImageGenBackend.drawThings) {
        final isDrawThings = _storage.imageGenBackend == 'drawthings';
        
        if (isDrawThings) {
          // Use gRPC for Draw Things (Python client bridge)
          _statusMessage = 'Connecting to Draw Things...';
          notifyListeners();
          
          final modelCheckpoint = model ?? _storage.imageGenModel;
          if (modelCheckpoint.isNotEmpty && !modelCheckpoint.toLowerCase().endsWith('.ckpt')) {
            _statusMessage = 'Invalid model name for Draw Things: must end with .ckpt (got: $modelCheckpoint)';
            _isGenerating = false;
            notifyListeners();
            return null;
          }
          
          try {
            final grpcService = _ensureDrawThingsGrpc;
            final imageSize = size ?? _storage.imageGenSize;
            final (width, height) = _parseSize(imageSize);
            final steps = _storage.imageGenSteps;
            final cfgScale = _storage.imageGenCfgScale;
            final seed = _storage.imageGenSeed;
            
            imageBytes = await _generateViaDrawThingsGrpc(
              grpcService: grpcService,
              prompt: prompt,
              negativePrompt: negativePrompt,
              model: modelCheckpoint,
              width: width,
              height: height,
              steps: steps,
              cfgScale: cfgScale,
              seed: seed,
            );
          } catch (e) {
            _statusMessage = 'Draw Things connection failed: $e';
            _isGenerating = false;
            notifyListeners();
            return null;
          }
        } else {
          // Use HTTP for A1111
          final localUrl = _storage.localImageGenUrl;
          if (localUrl.isEmpty) {
            _statusMessage = 'No local server URL configured.';
            _isGenerating = false;
            notifyListeners();
            return null;
          }
          final imageSize = size ?? _storage.imageGenSize;
          final modelCheckpoint = model ?? _storage.imageGenModel;
          imageBytes = await _generateViaA1111(
            baseUrl: localUrl,
            prompt: prompt,
            negativePrompt: negativePrompt,
            size: imageSize,
            modelCheckpoint: modelCheckpoint,
            switchModelFirst: modelCheckpoint.isNotEmpty,
            loraName: _storage.imageGenLora,
            loraWeight: _storage.imageGenLoraWeight,
            steps: _storage.imageGenSteps,
            cfgScale: _storage.imageGenCfgScale,
            samplerName: _storage.imageGenSampler,
            seed: _storage.imageGenSeed,
          );
        }

      } else {
        // ── Remote API ─────────────────────────────────────────────────
        if (_storage.remoteApiKey.isEmpty) {
          _statusMessage = 'No API key configured.';
          _isGenerating = false;
          notifyListeners();
          return null;
        }

        final imageModel = model ?? _storage.imageGenModel;
        if (imageModel.isEmpty) {
          _statusMessage = 'No image model selected.';
          _isGenerating = false;
          notifyListeners();
          return null;
        }

        final imageSize = size ?? _storage.imageGenSize;
        final apiUrl = _storage.remoteApiUrl;
        final apiKey = _storage.remoteApiKey;

        if (_isOpenRouterStyle(apiUrl)) {
          imageBytes = await _generateViaOpenRouter(
            apiUrl: apiUrl,
            apiKey: apiKey,
            model: imageModel,
            prompt: prompt,
            size: imageSize,
          );
        } else {
          imageBytes = await _generateViaOpenAICompat(
            apiUrl: apiUrl,
            apiKey: apiKey,
            model: imageModel,
            prompt: prompt,
            negativePrompt: negativePrompt,
            size: imageSize,
          );
        }
      }

      _lastGeneratedImage = imageBytes;
      _statusMessage = 'Image generated successfully.';
      debugPrint('ImageGen: Returning ${imageBytes?.length ?? 0} bytes');
      notifyListeners();
      return imageBytes;
    } catch (e) {
      _statusMessage = 'Generation failed: $e';
      notifyListeners();
      return null;
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }


  /// Save the last generated image to disk.
  ///
  /// Returns the saved file path, or null on failure.
  Future<String?> saveImageToDisk([Uint8List? imageBytes]) async {
    final bytes = imageBytes ?? _lastGeneratedImage;
    if (bytes == null) return null;

    try {
      final dir = _imagesDir;
      await dir.create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'img_$timestamp.png';
      final file = File(path.join(dir.path, filename));
      await file.writeAsBytes(bytes);

      _lastSavedPath = file.path;
      notifyListeners();
      return file.path;
    } catch (e) {
      debugPrint('Failed to save image: $e');
      return null;
    }
  }

  /// Save a generated image as a character avatar to the characters directory.
  ///
  /// Unlike [saveImageToDisk], this saves to the characters directory
  /// (`KoboldManager/Characters/`) so cloud sync picks it up.
  /// Returns the saved file path, or null on failure.
  Future<String?> saveAvatarToDisk(Uint8List? imageBytes, {String? characterName}) async {
    final bytes = imageBytes ?? _lastGeneratedImage;
    if (bytes == null) return null;

    try {
      final dir = _storage.charactersDir;
      await dir.create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = (characterName ?? 'avatar')
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final filename = '${safeName}_$timestamp.png';
      final file = File(path.join(dir.path, filename));
      await file.writeAsBytes(bytes);

      _lastSavedPath = file.path;
      notifyListeners();
      return file.path;
    } catch (e) {
      debugPrint('Failed to save avatar: $e');
      return null;
    }
  }

  /// Common image generation models available on Nano-GPT and similar providers.
  /// These are always shown so the user can pick one even when the API's
  /// /models endpoint doesn't list image models separately (Nano-GPT's /models
  /// endpoint only returns text models; image models have no discovery endpoint).
  ///
  /// Model IDs sourced from https://nano-gpt.com/models/image (May 2026).
  static const _commonImageModels = <ImageModelInfo>[
    // ── Included with Nano-GPT Pro subscription ($8/mo) ──
    ImageModelInfo(id: 'hidream', name: 'HiDream', isPaid: false),
    ImageModelInfo(id: 'chroma', name: 'Chroma', isPaid: false),
    ImageModelInfo(id: 'z-image-turbo', name: 'Z Image Turbo', isPaid: false),
    ImageModelInfo(id: 'qwen-image', name: 'Qwen Image', isPaid: false),
    // ── Pay-per-prompt: OpenAI ──
    ImageModelInfo(id: 'gpt-image-2', name: 'GPT Image 2'),
    ImageModelInfo(id: 'dall-e-3', name: 'DALL-E 3'),
    // ── Pay-per-prompt: Black Forest Labs (FLUX) ──
    ImageModelInfo(id: 'flux-1-pro', name: 'FLUX.1 Pro'),
    ImageModelInfo(id: 'flux-1-dev', name: 'FLUX.1 Dev'),
    ImageModelInfo(id: 'flux-1-schnell', name: 'FLUX.1 Schnell'),
    ImageModelInfo(id: 'flux-2-klein-4b', name: 'FLUX.2 Klein 4B'),
    ImageModelInfo(id: 'flux-2-klein-9b', name: 'FLUX.2 Klein 9B'),
    // ── Pay-per-prompt: Ideogram ──
    ImageModelInfo(id: 'ideogram-v3-default', name: 'Ideogram V3'),
    ImageModelInfo(id: 'ideogram-v3-turbo', name: 'Ideogram V3 Turbo'),
    ImageModelInfo(id: 'ideogram-v3-generate-transparent', name: 'Ideogram V3 Transparent'),
    ImageModelInfo(id: 'ideogram-v3-remove-text', name: 'Ideogram V3 Remove Text'),
    // ── Pay-per-prompt: Alibaba (WAN / Qwen) ──
    ImageModelInfo(id: 'wan2.7-image', name: 'WAN 2.7 Image'),
    ImageModelInfo(id: 'wan2.7-image-pro', name: 'WAN 2.7 Image Pro'),
    ImageModelInfo(id: 'qwen-image-2.0', name: 'Qwen Image 2.0'),
    ImageModelInfo(id: 'qwen-image-2.0-pro', name: 'Qwen Image 2.0 Pro'),
    ImageModelInfo(id: 'qwen-image-max', name: 'Qwen Image Max'),
    ImageModelInfo(id: 'qwen-image-max-edit', name: 'Qwen Image Max Edit'),
    // ── Pay-per-prompt: Google (Nano Banana) ──
    ImageModelInfo(id: 'nano-banana-2', name: 'Nano Banana 2 (Gemini Image)'),
    ImageModelInfo(id: 'nano-banana-2-fast', name: 'Nano Banana 2 Fast'),
    // ── Pay-per-prompt: ByteDance (Seedream) ──
    ImageModelInfo(id: 'seedream-v5.0-lite', name: 'Seedream 5.0 Lite'),
    ImageModelInfo(id: 'seedream-v5.0-lite-sequential', name: 'Seedream 5.0 Lite Sequential'),
    // ── Pay-per-prompt: Z.AI (GLM / CogView) ──
    ImageModelInfo(id: 'cogview-4', name: 'Z.AI CogView-4'),
    ImageModelInfo(id: 'z-image-base', name: 'Z Image Base'),
    ImageModelInfo(id: 'glm-image', name: 'Z.AI GLM Image'),
    ImageModelInfo(id: 'glm-image-edit', name: 'GLM Image Edit'),
    // ── Pay-per-prompt: Tencent (Hunyuan) ──
    ImageModelInfo(id: 'hunyuan-image-3-instruct', name: 'Hunyuan Image 3 Instruct'),
    // ── Pay-per-prompt: Baidu (ERNIE) ──
    ImageModelInfo(id: 'ernie-image', name: 'ERNIE Image'),
    ImageModelInfo(id: 'ernie-image/turbo', name: 'ERNIE Image Turbo'),
    // ── Pay-per-prompt: xAI ──
    ImageModelInfo(id: 'grok-imagine-image', name: 'Grok Imagine Image'),
    // ── Pay-per-prompt: MiniMax ──
    ImageModelInfo(id: 'minimax-image-01', name: 'MiniMax Image-01'),
    // ── Pay-per-prompt: Bria ──
    ImageModelInfo(id: 'bria-fibo', name: 'Bria Fibo'),
    ImageModelInfo(id: 'bria-fibo-edit', name: 'Bria Fibo Edit'),
    // ── Pay-per-prompt: Sourceful (Riverflow) ──
    ImageModelInfo(id: 'riverflow-2.0-pro', name: 'Riverflow 2.0 Pro'),
    // ── Pay-per-prompt: Other / Utility ──
    ImageModelInfo(id: 'juggernaut-z', name: 'Juggernaut Z'),
    ImageModelInfo(id: 'mjv6', name: 'Flux Midjourney (MJV6)'),
    ImageModelInfo(id: 'dreamshaper-xl', name: 'Dreamshaper XL'),
    ImageModelInfo(id: 'nsfw-gen-illustrious', name: 'Animagine XL 4.0'),
    ImageModelInfo(id: 'atomix-xl', name: 'Atomix XL'),
    ImageModelInfo(id: 'background-remover', name: 'Background Remover'),
    ImageModelInfo(id: 'esrgan-4x', name: 'ESRGAN 4x Upscaler'),
    ImageModelInfo(id: 'custom-civitai', name: 'Custom CivitAI Model'),
  ];

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
    final apiUrl = _storage.remoteApiUrl;
    final apiKey = _storage.remoteApiKey;
    if (apiUrl.isEmpty || apiKey.isEmpty) return List.from(_commonImageModels);

    // Detect if this is OpenRouter
    final isOpenRouter = _isOpenRouterStyle(apiUrl);

    if (isOpenRouter) {
      return _fetchOpenRouterImageModels(apiUrl, apiKey);
    } else {
      // For Nano-GPT and other providers: return curated list
      return List.from(_commonImageModels);
    }
  }

  /// Fetch image models specifically from OpenRouter's API.
  ///
  /// OpenRouter supports querying for image-capable models via:
  /// GET /models?output_modalities=image
  ///
  /// Returns the models as provided by OpenRouter with their pricing,
  /// or an empty list if the API call fails.
  Future<List<ImageModelInfo>> _fetchOpenRouterImageModels(String apiUrl, String apiKey) async {
    final apiModels = <ImageModelInfo>[];
    final client = http.Client();

    try {
      // Query for models that can output images
      final uri = Uri.parse('$apiUrl/models?output_modalities=image');
      final response = await client.get(
        uri,
        headers: {'Authorization': 'Bearer $apiKey'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'] as List<dynamic>? ?? [];

        for (final m in data) {
          final id = m['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final name = m['name']?.toString() ?? id;

          // Extract pricing info if available (display as-is from OpenRouter)
          final pricing = m['pricing'] as Map<String, dynamic>?;
          String? pricingInfo;
          
          // NOTE: OpenRouter returns $0/$0 for free-tier-only models or unclear pricing
          // We do NOT mark these as "free" since they may have restrictions or credits only
          // Instead, we show the pricing as-is and let user check OpenRouter's site for details
          bool isPaid = true; // Conservative: assume paid unless clearly free ($0 everywhere)

          if (pricing != null) {
            final prompt = pricing['prompt'];
            final completion = pricing['completion'];

            // Format pricing for display (show as-is from API)
            if (prompt != null || completion != null) {
              pricingInfo = '\$$prompt / \$$completion';
            }
          }

          apiModels.add(ImageModelInfo(
            id: id,
            name: name,
            isPaid: isPaid,
            pricingInfo: pricingInfo,
          ));
        }

        debugPrint('ImageGen: Fetched ${apiModels.length} image models from OpenRouter');
      } else {
        debugPrint('ImageGen: OpenRouter /models?output_modalities=image returned ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('ImageGen: Failed to fetch OpenRouter image models: $e');
    } finally {
      client.close();
    }

    // Sort by name for consistent display
    apiModels.sort((a, b) => a.displayName.compareTo(b.displayName));
    return apiModels;
  }

  /// Max prompt length for image generation APIs.
  /// Most models cap at 1000-1200 chars; we target 1000 to be safe.
  static const _maxPromptLength = 1000;

  /// Truncate a string to a maximum length, breaking at a word boundary.
  static String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    final cut = text.substring(0, maxLen);
    final lastSpace = cut.lastIndexOf(' ');
    return '${lastSpace > maxLen ~/ 2 ? cut.substring(0, lastSpace) : cut}...';
  }

  /// Style suffixes appended to the final image prompt.
  /// Written as natural language so they work with FLUX, SD3, and SDXL
  /// as well as older SD 1.5-based models.
  static const Map<String, String> styleModifiers = {
    'photorealistic': 'Photorealistic with cinematic lighting, sharp focus, and highly detailed textures.',
    'anime':          'Anime-style illustration with clean linework, expressive eyes, vibrant colors, and cel shading.',
    'fantasy_art':    'Epic fantasy digital art with dramatic lighting, rich environmental detail, and a painterly quality.',
    'oil_painting':   'Classical oil painting with visible brushstrokes, rich color depth, and fine art composition.',
    'digital_art':    'Polished digital art with vibrant colors, clean lines, and professional illustration quality.',
    'watercolor':     'Soft watercolor illustration with flowing color washes, delicate edges, and gentle translucent tones.',
  };

  /// Legacy comma-separated tag modifiers for SD 1.5 / Illustrious models.
  static const Map<String, String> legacyStyleModifiers = {
    'photorealistic': 'photorealistic, cinematic lighting, sharp focus, highly detailed, 8k',
    'anime':          'anime style, masterpiece, best quality, highly detailed, cel shading',
    'fantasy_art':    'fantasy art, epic, dramatic lighting, highly detailed, painterly',
    'oil_painting':   'oil painting, traditional media, brushstrokes, fine art',
    'digital_art':    'digital art, polished, vibrant, illustration, high quality',
    'watercolor':     'watercolor, translucent, soft washes, pastel, traditional media',
  };

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
  /// Falls back to the static [buildPrompt] if [llmService] is null or unavailable.
  Future<String> generateSmartPrompt({
    required ImageGenMode mode,
    required String style,
    LLMService? llmService,
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
  }) async {
    final paradigm = _storage.imageGenPromptParadigm; // 'natural' or 'tags'
    final modifiers = paradigm == 'tags' ? legacyStyleModifiers : styleModifiers;

    // Custom prompt mode — no LLM needed, just append style
    if (mode == ImageGenMode.customPrompt) {
      final styleSuffix = modifiers[style] ?? '';
      final glue = paradigm == 'tags' ? ', ' : '. ';
      final raw = '${customPrompt ?? ''}$glue$styleSuffix';
      return _truncate(raw, _maxPromptLength);
    }

    // Replace {{user}}/{{char}} macros in raw context
    String resolve(String? text) {
      if (text == null || text.isEmpty) return '';
      return text
          .replaceAll('{{user}}', personaName ?? 'User')
          .replaceAll('{{char}}', characterName ?? 'Character');
    }

    // Build raw context block for the LLM
    final contextParts = <String>[];
    if (characterName != null && characterName.isNotEmpty) {
      contextParts.add('Character: $characterName');
    }
    if (characterDescription != null && characterDescription.isNotEmpty) {
      contextParts.add('Appearance: ${resolve(characterDescription)}');
    }
    if (scenario != null && scenario.isNotEmpty) {
      contextParts.add('Scenario: ${resolve(scenario)}');
    }
    if (worldInfo != null && worldInfo.isNotEmpty) {
      contextParts.add('Setting: ${resolve(worldInfo)}');
    }
    if (recentMessages != null && recentMessages.isNotEmpty) {
      final resolved = recentMessages.map((m) => resolve(m)).join('\n');
      contextParts.add('Recent events:\n$resolved');
    }
    if (lastMessage != null && lastMessage.isNotEmpty) {
      contextParts.add('Latest message: ${resolve(lastMessage)}');
    }
    if (personaName != null && personaName.isNotEmpty) {
      contextParts.add('User character: $personaName');
    }

    final rawContext = _truncate(contextParts.join('\n'), 2000);
    final styleSuffix = modifiers[style] ?? '';

    // If no LLM available, fall back to static prompt builder
    if (llmService == null || !llmService.isReady) {
      debugPrint('ImageGen: LLM unavailable, falling back to static prompt');
      final fallback = buildPrompt(
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
      );
      return _truncate('$fallback. $styleSuffix', _maxPromptLength);
    }

    // Mode-specific instruction
    String modeInstruction;
    switch (mode) {
      case ImageGenMode.visualizeScene:
        modeInstruction = 'Describe the current scene as a vivid image — environment, characters present, lighting, mood.';
      case ImageGenMode.fromLastMessage:
        modeInstruction = 'Describe the scene depicted in the latest message as a vivid image.';
      case ImageGenMode.characterPortrait:
        modeInstruction = 'Describe a portrait of the character — their appearance, expression, clothing, and pose.';
      case ImageGenMode.chatBackground:
        modeInstruction = 'Describe the environment/setting as a wide panoramic landscape. Do NOT include any characters or people.';
      case ImageGenMode.userAvatar:
        modeInstruction = 'Describe a portrait of the user character — their appearance, expression, and pose.';
      default:
        modeInstruction = 'Describe the scene as a vivid image.';
    }

    // Determine prompt instruction based on selected paradigm
    final isTags = paradigm == 'tags';
    final formatInstruction = isTags
        ? 'Write a flat, comma-separated list of visual danbooru tags describing the scene and characters — NO prose. NO sentences. ONLY tags.\nExample: masterpiece, best quality, 1girl, blonde hair, blue eyes, dynamic pose, outdoors'
        : 'Write a single paragraph in natural, descriptive English — NOT a comma-separated tag list.\nBe vivid and specific about visual details: physical appearance, clothing, lighting, mood, setting.';

    final llmPrompt =
        'You are writing an image generation prompt for an AI image model.\n'
        'Respond with ONLY a JSON object, no other text.\n'
        'Format: {"prompt": "your image prompt here"}\n\n'
        '$formatInstruction\n'
        '$modeInstruction\n'
        'Keep it under 100 words. Do not include any character names. '
        'End with the art style description.${styleSuffix.isNotEmpty ? " Art style: $styleSuffix" : ""}\n\n'
        'Context:\n$rawContext';

    try {
      debugPrint('ImageGen: Crafting smart prompt via LLM...');
      String accumulated = '';
      await for (final token in llmService.generateStream(GenerationParams(
        prompt: llmPrompt,
        maxLength: 2000,  // Generous budget: some models think extensively before generating the prompt
        temperature: 0.2,
        repeatPenalty: 1.0,
        reasoningEnabled: false,
        stopSequences: ['\n\n', '<END>', '</END>'],
      ))) {
        accumulated += token;
      }

      // ── Parse JSON response ──
      String smartPrompt = accumulated.trim();
      debugPrint('ImageGen: Raw output length: ${smartPrompt.length}');

      try {
        // Try to extract JSON from the response (may be wrapped in thinking or extra text)
        // Look for JSON object pattern: {...}
        final jsonMatch = RegExp(r'\{[^{}]*"prompt"[^{}]*\}', dotAll: true).firstMatch(smartPrompt);
        
        if (jsonMatch != null) {
          final jsonStr = jsonMatch.group(0)!;
          final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
          final prompt = parsed['prompt']?.toString() ?? '';
          
          if (prompt.isNotEmpty) {
            smartPrompt = prompt;
            debugPrint('ImageGen: Successfully parsed JSON prompt (${smartPrompt.length} chars)');
          } else {
            throw Exception('JSON prompt field was empty');
          }
        } else {
          // No JSON found - fall back to static generation
          throw Exception('No JSON object found in response');
        }
      } catch (e) {
        debugPrint('ImageGen: Failed to parse JSON ($e), falling back to static prompt');
        final fallback = buildPrompt(
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
        );
        return _truncate('$fallback. $styleSuffix', _maxPromptLength);
      }

      // Clean up the extracted prompt
      smartPrompt = smartPrompt
          .replaceAll(RegExp(r'\n+'), ' ')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();

      // Ensure style is present
      if (styleSuffix.isNotEmpty && !smartPrompt.toLowerCase().contains(styleSuffix.toLowerCase().substring(0, 5))) {
        final glue = isTags ? ', ' : '. ';
        smartPrompt = '${smartPrompt.trim()}$glue$styleSuffix';
      }
      
      if (isTags) {
        // Tag paradigm logic (e.g. remove trailing periods, ensure commas)
        smartPrompt = smartPrompt.replaceAll('.', ',');
      }

      debugPrint('ImageGen: Smart prompt crafted (${smartPrompt.length} chars)');
      return _truncate(smartPrompt, _maxPromptLength);
    } catch (e) {
      debugPrint('ImageGen: Smart prompt failed ($e), falling back to static');
      final fallback = buildPrompt(
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
      );
      return _truncate('$fallback. $styleSuffix', _maxPromptLength);
    }
  }

  /// Build a prompt for the given generation mode.
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
  }) {
    String raw;
    switch (mode) {
      case ImageGenMode.customPrompt:
        raw = customPrompt ?? '';

      case ImageGenMode.visualizeScene:
        final parts = <String>[];
        if (scenario != null && scenario.isNotEmpty) {
          parts.add('Scene: ${_truncate(scenario, 300)}');
        }
        if (worldInfo != null && worldInfo.isNotEmpty) {
          parts.add('Setting: ${_truncate(worldInfo, 200)}');
        }
        if (recentMessages != null && recentMessages.isNotEmpty) {
          parts.add('Recent events: ${_truncate(recentMessages.join(" "), 300)}');
        }
          parts.add('A wide establishing shot of the scene. Cinematic composition with atmospheric lighting.');
        raw = parts.join(' ');

      case ImageGenMode.fromLastMessage:
        if (lastMessage == null || lastMessage.isEmpty) return '';
        raw = 'Depict the following scene: ${_truncate(lastMessage, 500)}';

      case ImageGenMode.characterPortrait:
        final parts = <String>[];
        if (characterName != null && characterName.isNotEmpty) {
          parts.add('Character portrait of $characterName.');
        }
        if (characterDescription != null && characterDescription.isNotEmpty) {
          parts.add(_truncate(characterDescription, 400));
        }
        if (characterPersonality != null && characterPersonality.isNotEmpty) {
          parts.add('Personality: ${_truncate(characterPersonality, 200)}');
        }
        parts.add('A detailed close-up portrait, expressive face, high quality rendering.');
        raw = parts.join(' ');

      case ImageGenMode.chatBackground:
        final parts = <String>[];
        if (scenario != null && scenario.isNotEmpty) {
          parts.add('Environment: ${_truncate(scenario, 300)}');
        }
        if (worldInfo != null && worldInfo.isNotEmpty) {
          parts.add('Setting: ${_truncate(worldInfo, 300)}');
        }
        parts.add('Wide panoramic landscape, atmospheric lighting, no people or characters, suitable as a scene background.');
        raw = parts.join(' ');

      case ImageGenMode.userAvatar:
        final parts = <String>[];
        if (personaName != null && personaName.isNotEmpty) {
          parts.add('Portrait of $personaName.');
        }
if (personaText != null && personaText.isNotEmpty) {
      parts.add(_truncate(personaText, 400));
        }
        parts.add('A detailed close-up portrait, expressive face, high quality rendering.');
        raw = parts.join(' ');
    }

    // Final safety cap
    return _truncate(raw, _maxPromptLength);
  }

  // ── Private helpers ────────────────────────────────────────────────

  /// Parse a "WxH" size string into width and height integers.
  static (int width, int height) _parseSize(String size) {
    final parts = size.split('x');
    if (parts.length == 2) {
      final w = int.tryParse(parts[0]) ?? 1024;
      final h = int.tryParse(parts[1]) ?? 1024;
      return (w, h);
    }
    return (1024, 1024);
  }

  /// Test whether a local image-gen server is reachable.
  ///
  /// For Draw Things, uses gRPC. For A1111, uses HTTP.
  Future<bool> testLocalConnection(String baseUrl) async {
    final isDrawThings = _storage.imageGenBackend == 'drawthings';
    
    if (isDrawThings) {
      try {
        final grpcService = _ensureDrawThingsGrpc;
        return await grpcService.testConnection();
      } catch (e) {
        debugPrint('ImageGen: Draw Things connection test failed: $e');
        return false;
      }
    } else {
      final client = http.Client();
      try {
        final uri = Uri.parse('${baseUrl.trimRight()}/sdapi/v1/sd-models');
        final response = await client
            .get(uri)
            .timeout(const Duration(seconds: 5));
        return response.statusCode == 200;
      } catch (_) {
        return false;
      } finally {
        client.close();
      }
    }
  }

  /// Fetch available checkpoints from an A1111 / Draw Things server.
  ///
  /// For Draw Things, uses gRPC. For A1111, uses HTTP.
  Future<List<String>> fetchA1111Models(String baseUrl) async {
    final isDrawThings = _storage.imageGenBackend == 'drawthings';
    
    if (isDrawThings) {
      try {
        final grpcService = _ensureDrawThingsGrpc;
        return await grpcService.fetchModels();
      } catch (e) {
        debugPrint('ImageGen: fetchDrawThingsModels failed: $e');
        return [];
      }
    } else {
      final client = http.Client();
      try {
        final uri = Uri.parse('${baseUrl.trimRight()}/sdapi/v1/sd-models');
        final response = await client
            .get(uri)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) return [];
        final list = jsonDecode(response.body) as List<dynamic>;
        return list
            .map((m) => (m as Map<String, dynamic>)['title']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      } catch (_) {
        return [];
      } finally {
        client.close();
      }
    }
  }

  /// Fetch models from a Draw Things server.
  ///
  /// Uses gRPC to fetch models. Draw Things doesn't expose LoRAs via gRPC.
  Future<List<String>> fetchDrawThingsModels(String baseUrl) async {
    try {
      final grpcService = _ensureDrawThingsGrpc;
      return await grpcService.fetchModels();
    } catch (e) {
      debugPrint('ImageGen: fetchDrawThingsModels failed: $e');
      return [];
    }
  }

  /// Fetch LoRAs from an A1111 / Forge / SD.Next server.
  ///
  /// Endpoint: GET /sdapi/v1/loras
  /// Returns a list of LoRA names (the `name` field from each entry).
  /// Draw Things does not support this endpoint — returns empty list.
  Future<List<String>> fetchA1111Loras(String baseUrl) async {
    final client = http.Client();
    try {
      final uri = Uri.parse('${baseUrl.trimRight()}/sdapi/v1/loras');
      debugPrint('ImageGen: Fetching LoRAs from $uri');
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((e) {
            final m = e as Map<String, dynamic>;
            // Prefer alias if present and non-empty, else use name
            final alias = m['alias']?.toString() ?? '';
            final name  = m['name']?.toString() ?? '';
            return alias.isNotEmpty ? alias : name;
          })
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('ImageGen: fetchA1111Loras failed: $e');
      return [];
    } finally {
      client.close();
    }
  }

  /// Unload the currently active model from memory on a local server.
  ///
  /// Calls `POST /sdapi/v1/unload-checkpoint` (standard A1111 endpoint).
  /// Draw Things may support this via its A1111-compat layer.
  /// If the server doesn't support it the error is silently ignored —
  /// model switching via [switchLocalModel] will still proceed.
  ///
  /// Returns true if the server acknowledged the unload (HTTP 200).
  Future<bool> unloadLocalModel(String baseUrl) async {
    final client = http.Client();
    try {
      final uri = Uri.parse('${baseUrl.trimRight()}/sdapi/v1/unload-checkpoint');
      debugPrint('ImageGen: Requesting model unload at $uri');
      final response = await client
          .post(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 30));
      final ok = response.statusCode == 200;
      debugPrint('ImageGen: Unload ${ok ? "accepted" : "rejected (${response.statusCode}) — may not be supported"}');
      return ok;
    } catch (e) {
      debugPrint('ImageGen: unloadLocalModel failed (ignored): $e');
      return false;
    } finally {
      client.close();
    }
  }

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
  Future<bool> switchLocalModel(String baseUrl, String modelName) async {
    if (modelName.isEmpty) return false;
    // Step 1: unload current model (best-effort — Draw Things may ignore this)
    await unloadLocalModel(baseUrl);
    // Step 2: request the new checkpoint
    final client = http.Client();
    try {
      final uri = Uri.parse('${baseUrl.trimRight()}/sdapi/v1/options');
      debugPrint('ImageGen: Switching checkpoint → $modelName');
      final response = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'sd_model_checkpoint': modelName}),
          )
          .timeout(const Duration(seconds: 120)); // model loads can be slow
      final ok = response.statusCode == 200;
      debugPrint('ImageGen: Checkpoint switch ${ok ? "accepted" : "rejected (${response.statusCode})"}');
      if (!ok) return false;

      // Step 3: confirm the model is fully loaded before returning.
      // A1111's /sdapi/v1/options POST returns 200 when the load *starts*,
      // but on Windows/nVidia/CuBLAS the model may still be transferring
      // tensors to CUDA. We poll until the reported checkpoint matches or
      // we exhaust retries.
      final ready = await _waitForModelReady(baseUrl, modelName, client);
      if (ready) {
        _lastLoadedCheckpoint = modelName;
      } else {
        debugPrint('ImageGen: Model ready check timed out — proceeding anyway');
        _lastLoadedCheckpoint = modelName; // assume it loaded
      }
      return true;
    } catch (e) {
      debugPrint('ImageGen: switchLocalModel failed: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// Poll the A1111 server until the active checkpoint matches [expected].
  ///
  /// This prevents a race condition where `txt2img` fires while the model
  /// is still being moved to the CUDA device, causing the
  /// "Expected all tensors to be on the same device" RuntimeError.
  ///
  /// Polls up to 30 times with a 2-second interval (60 s total).
  Future<bool> _waitForModelReady(
    String baseUrl,
    String expected,
    http.Client client,
  ) async {
    final uri = Uri.parse('${baseUrl.trimRight()}/sdapi/v1/options');
    const maxAttempts = 30;
    const pollInterval = Duration(seconds: 2);

    for (var i = 0; i < maxAttempts; i++) {
      try {
        final resp = await client
            .get(uri)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final active = body['sd_model_checkpoint']?.toString() ?? '';
          if (active == expected) {
            debugPrint('ImageGen: Model ready confirmed on attempt ${i + 1}');
            return true;
          }
          debugPrint('ImageGen: Waiting for model load… '
              '(active="$active", expected="$expected", attempt ${i + 1}/$maxAttempts)');
        }
      } catch (e) {
        debugPrint('ImageGen: Model ready poll failed (attempt ${i + 1}): $e');
      }
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }

  /// Fetch available samplers from an A1111 / Draw Things server.
  ///
  /// Endpoint: GET /sdapi/v1/samplers
  /// Returns sampler names (the `name` field from each entry).
  Future<List<String>> fetchA1111Samplers(String baseUrl) async {
    final client = http.Client();
    try {
      final uri = Uri.parse('${baseUrl.trimRight()}/sdapi/v1/samplers');
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('ImageGen: fetchA1111Samplers failed: $e');
      return [];
    } finally {
      client.close();
    }
  }

  /// Generate via AUTOMATIC1111 / Draw Things local server.
  ///
  /// Endpoint: POST {baseUrl}/sdapi/v1/txt2img
  /// Response: { "images": ["<base64>", ...] }
  ///
  /// When [modelCheckpoint] is non-empty and the backend is Draw Things,
  /// the active model is switched via `POST /sdapi/v1/options` first,
  /// mimicking "create a new project" with the selected model.
  Future<Uint8List> _generateViaA1111({
    required String baseUrl,
    required String prompt,
    String negativePrompt = '',
    String size = '1024x1024',
    String modelCheckpoint = '',
    bool switchModelFirst = false,
    String loraName = '',
    double loraWeight = 0.8,
    int steps = 20,
    double cfgScale = 7.0,
    String samplerName = 'Euler a',
    int seed = -1,
  }) async {
    // Switch model only if a different checkpoint was requested.
    // Skipping redundant switches prevents the unload→reload cycle that
    // can leave tensors split across CPU & CUDA on Windows/nVidia setups.
    if (switchModelFirst && modelCheckpoint.isNotEmpty &&
        modelCheckpoint != _lastLoadedCheckpoint) {
      _statusMessage = 'Loading model: $modelCheckpoint…';
      notifyListeners();
      await switchLocalModel(baseUrl, modelCheckpoint);
    }

    final (width, height) = _parseSize(size);
    final uri = Uri.parse('${baseUrl.trimRight()}/sdapi/v1/txt2img');

    // Inject LoRA into the prompt: <lora:name:weight>
    final effectivePrompt = (loraName.isNotEmpty)
        ? '$prompt <lora:$loraName:${loraWeight.toStringAsFixed(2)}>'
        : prompt;

    debugPrint('ImageGen: POST $uri (model=${modelCheckpoint.isNotEmpty ? modelCheckpoint : "current"}, lora=${loraName.isNotEmpty ? loraName : "none"})');

    final payload = <String, dynamic>{
      'prompt': effectivePrompt,
      'negative_prompt': negativePrompt,
      'width': width,
      'height': height,
      'steps': steps,
      'cfg_scale': cfgScale,
      'sampler_name': samplerName,
      'seed': seed,
      'batch_size': 1,
      // NOTE: override_settings is intentionally omitted here.
      // Passing sd_model_checkpoint inside override_settings causes A1111 to
      // attempt a model reload mid-request, which splits tensors across
      // cpu and cuda and throws:
      //   "Expected all tensors to be on the same device"
      // The model switch is already handled by switchLocalModel() above.
    };


    final client = http.Client();
    try {
      final response = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 600)); // allow time for model load

      if (response.statusCode != 200) {
        String errorMsg = 'HTTP ${response.statusCode}';
        try {
          final errBody = jsonDecode(response.body);
          final detail = errBody['detail'];
          if (detail is String) errorMsg = detail;
        } catch (_) {}
        throw Exception(errorMsg);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final images = body['images'] as List<dynamic>?;
      if (images == null || images.isEmpty) {
        throw Exception('No images returned from local server');
      }

      final b64 = images[0] as String;
      return base64Decode(b64);
    } finally {
      client.close();
    }
  }

  /// Generate via Draw Things gRPC service (Python client bridge).
  Future<Uint8List> _generateViaDrawThingsGrpc({
    required DrawThingsGrpcService grpcService,
    required String prompt,
    String negativePrompt = '',
    String model = '',
    int width = 1024,
    int height = 1024,
    int steps = 20,
    double cfgScale = 7.0,
    int seed = -1,
  }) async {
    return await grpcService.generateImage(
      prompt: prompt,
      negativePrompt: negativePrompt,
      model: model,
      width: width,
      height: height,
      steps: steps,
      cfgScale: cfgScale,
      seed: seed,
    );
  }

  /// Detect if URL is an OpenRouter-style API (uses chat/completions for images).
  bool _isOpenRouterStyle(String url) {
    return url.contains('openrouter.ai');
  }

  /// Generate via OpenAI-compatible /images/generations endpoint.
  /// Works with Nano-GPT, direct OpenAI, and local A1111/SD servers.
  Future<Uint8List> _generateViaOpenAICompat({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String negativePrompt = '',
    String size = '1024x1024',
  }) async {
    final imageEndpoint = '$apiUrl/images/generations';
    debugPrint('ImageGen: POST $imageEndpoint (model=$model)');
    final uri = Uri.parse(imageEndpoint);
    final payload = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'n': 1,
      'size': size,
      'response_format': 'b64_json',
    };

    final client = http.Client();
    try {
      final response = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        debugPrint('ImageGen: HTTP ${response.statusCode} from $imageEndpoint');
        debugPrint('ImageGen: Response body: ${response.body}');
        String errorMsg = 'HTTP ${response.statusCode}';
        try {
          final errBody = jsonDecode(response.body);
          final error = errBody['error'];
          // Handle both OpenAI format {"error":{"message":"..."}} and
          // Nano-GPT format {"error":"...","code":"..."}
          if (error is Map<String, dynamic>) {
            errorMsg = error['message'] as String? ?? errorMsg;
          } else if (error is String) {
            errorMsg = error;
          }
        } catch (_) {}
        throw Exception(errorMsg);
      }

      final body = jsonDecode(response.body);
      final data = body['data'] as List<dynamic>;
      if (data.isEmpty) throw Exception('No image data returned');

      // Handle both b64_json and url response formats
      final first = data[0] as Map<String, dynamic>;
      if (first.containsKey('b64_json')) {
        return base64Decode(first['b64_json'] as String);
      } else if (first.containsKey('url')) {
        // Download the image from the URL
        final imgResponse =
            await client.get(Uri.parse(first['url'] as String))
                .timeout(const Duration(seconds: 30));
        if (imgResponse.statusCode != 200) {
          throw Exception('Failed to download image from URL');
        }
        return imgResponse.bodyBytes;
      } else {
        throw Exception('Unexpected response format');
      }
    } finally {
      client.close();
    }
  }

  /// Generate via OpenRouter's chat/completions endpoint with image modality.
  Future<Uint8List> _generateViaOpenRouter({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String prompt,
    String size = '1024x1024',
  }) async {
    final uri = Uri.parse('$apiUrl/chat/completions');
    final payload = <String, dynamic>{
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        }
      ],
      'modalities': ['image'],
      'max_tokens': 4096,
    };

    final client = http.Client();
    try {
      final response = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'HTTP-Referer': 'https://github.com/linux4life1/front-porch-AI',
          'X-Title': 'Front Porch AI',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        String errorMsg = 'HTTP ${response.statusCode}';
        try {
          final errBody = jsonDecode(response.body);
          final error = errBody['error'];
          if (error is Map<String, dynamic>) {
            errorMsg = error['message'] as String? ?? errorMsg;
          } else if (error is String) {
            errorMsg = error;
          }
        } catch (_) {}
        throw Exception(errorMsg);
      }

      final body = jsonDecode(response.body);
      final choices = body['choices'] as List<dynamic>? ?? [];
      if (choices.isEmpty) throw Exception('No response choices');

      final message = choices[0]['message'] as Map<String, dynamic>;
      final content = message['content'];

      // OpenRouter may return content as a list with image parts
      if (content is List) {
        for (final part in content) {
          if (part is Map<String, dynamic>) {
            if (part['type'] == 'image_url') {
              final imageUrl = part['image_url']?['url'] as String?;
              if (imageUrl != null) {
                if (imageUrl.startsWith('data:')) {
                  // Base64 data URI
                  final b64 = imageUrl.split(',').last;
                  return base64Decode(b64);
                } else {
                  // Regular URL — download it
                  final imgResp = await client.get(Uri.parse(imageUrl))
                      .timeout(const Duration(seconds: 30));
                  return imgResp.bodyBytes;
                }
              }
            }
          }
        }
      }

      // Fallback: try to extract base64 from string content
      if (content is String && content.isNotEmpty) {
        // Check if it's a base64 string
        try {
          return base64Decode(content);
        } catch (_) {
          throw Exception('Could not extract image from response');
        }
      }

      throw Exception('No image found in response');
    } finally {
      client.close();
    }
  }
}
