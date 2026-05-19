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
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/app_version.dart';
import '../models/character_card.dart';

class StorageService extends ChangeNotifier {
  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get initialized => _initCompleter.future;

  SharedPreferences? _prefs;
  String? _rootPath;
  String? _customModelsPath;
  Directory? _binDir;

  String? get rootPath => _rootPath;
  String? get customModelsPath => _customModelsPath;
  Directory get binDir => _binDir ?? Directory(_rootPath ?? '');
  Directory get modelsDir =>
      _customModelsPath != null && _customModelsPath!.isNotEmpty
      ? Directory(_customModelsPath!)
      : Directory(path.join(_rootPath ?? '', 'models'));
  Directory get chatsDir => Directory(path.join(_rootPath ?? '', 'chats'));
  Directory get worldsDir => Directory(path.join(_rootPath ?? '', 'worlds'));

  Directory get charactersDir =>
      Directory(path.join(_rootPath ?? '', 'KoboldManager', 'Characters'));

  /// Resolve a character [imagePath] (stored in the DB) to a [File].
  ///
  /// The DB may contain either:
  ///   • A **basename** only — e.g. `"Maggie_1234567890.png"` (written by the
  ///     manual avatar picker and older AI-generated entries).
  ///   • A **full absolute path** — e.g. `/Users/.../Maggie_1234567890.png`
  ///     (written by newer AI-generated entries before this fix).
  ///   • A **relative path with subdirectory** — e.g. `"Aerin/avatars/avatar_1.png"`
  ///     (multi-avatar format with per-character subdirectories).
  ///
  /// In all cases this returns the correct [File].  Pass the result to
  /// [FileImage] or [Image.file] instead of [File(imagePath)] directly so
  /// that the code remains valid when the app data directory moves or the
  /// character card is used on a different machine.
  File resolveCharacterImage(String imagePath) {
    if (path.isAbsolute(imagePath)) return File(imagePath);
    final resolved = File(path.join(charactersDir.path, imagePath));
    return resolved;
  }

  /// Return the avatars subdirectory for a character by name.
  /// Creates the directory if it doesn't exist.
  Directory characterAvatarDir(String characterName) {
    final safeName = characterName
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');
    return Directory(path.join(charactersDir.path, safeName, 'avatars'));
  }

  // Settings
  static const String defaultSystemPrompt =
      "You are an immersive roleplay partner. Embody {{char}} completely — personality, appearance, thought processes, emotions, behaviors, and speech patterns. You may also roleplay as any side characters introduced.\n\nEngage with {{user}} by depicting {{char}}'s actions, emotions, and dialogue. Develop the plot slowly and organically while driving the scenario forward. Never write {{user}}'s speech, actions, or decisions — allow them full control of their character.\n\nWrite in a vivid, creative, varied, and descriptive style. Use rich sensory detail for the environment, people, and events. Make each reply unique and end with an action or dialogue to keep momentum.\n\nMaintain consistency with established details — clothing, time of day, location, and prior events. Stay in character at all times.";
  String _systemPrompt = defaultSystemPrompt;
  double _minP = 0.1;
  double _temperature = 0.7;
  double _bubbleOpacity = 1.0;

  // Global chat color defaults
  Color _globalUserBubbleColor = const Color(0xFF3B82F6);
  Color _globalUserTextColor = Colors.white;
  Color _globalAiBubbleColor = const Color(0xFF374151);
  Color _globalAiTextColor = Colors.white;
  Color _globalDialogueColor = Colors.amberAccent;
  Color _globalActionColor = const Color(0xFF90CAF9);

  // Global chat font family
  String _globalChatFontFamily = '';

  double _repeatPenalty = 1.1;
  int _repeatPenaltyTokens = 64;
  bool _dynamicTempEnabled = false;
  double _dynamicTempRange = 0.7;
  double _xtcThreshold = 0.1;
  double _xtcProbability = 0.5;
  bool? _useCublas;
  bool? _useVulkan;
  bool? _useMetal;
  bool? _useRocm;

  // ── Advanced KoboldCPP launch flags ──────────────────────────────────────
  // Defaults are chosen to match KoboldCPP's own Quick Launch GUI behaviour
  // and to give best out-of-box speed.
  bool _flashAttentionEnabled = true;  // ~30% speed boost on RTX/Metal; off for ROCm
  bool _mlockEnabled          = !Platform.isLinux; // prevent VRAM paging (needs root on Linux)
  int  _blasBatchSize         = 512;   // tokens processed in parallel during prefill
  int  _gpuId                 = 0;     // explicit GPU index — prevents iGPU routing on multi-GPU
  int _maxLength = 1024;
  int _minLength = 0;
  bool _autostartBackend = true;
  String? _lastUsedModelPath;
  String? _activeKcppsPath;
  /// True when the active .kcpps file contains a non-empty "model" key.
  /// KoboldCPP will load that model automatically, so the Flutter model picker
  /// should be disabled. False when no preset is active OR the preset has no
  /// model (user must select one via the Flutter picker).
  bool _kcppsHasModel = false;
  Map<String, String> _modelPresetMap = {};
  int _gpuLayers = 0;
  int _contextSize = 8192;
  List<String> _stopSequences = [
    "\nUser:",
    "\n###",
    "\nScenario:",
    "<END>",
    "</END>",
    "[END]",
    "<|end|>",
    "<START>",
    "\nSystem:",
    "\n(Note:",
    "\n[Note:",
    "\n{Note:",
  ];
  double _textScale = 1.0;
  String _chatBackground = 'none';
  List<Map<String, String>> _customBackgrounds = [];
  List<Map<String, String>> _savedPrompts = [];
  bool _displayBufferEnabled = true;
  double _targetDisplayTps = 6.0; // ~250 WPM average human reading speed
  double _bufferDurationSeconds =
      3.0; // How many seconds of tokens to buffer before draining

  // External API settings
  String _backendType = 'kobold'; // 'kobold' or 'openRouter'
  String _remoteApiKey = '';
  String _remoteApiUrl = 'https://openrouter.ai/api/v1';
  String _remoteModelName = '';

  // Reasoning settings (remote API)
  bool _reasoningEnabled = false;
  String _reasoningEffort = 'medium'; // 'low', 'medium', 'high'
  // Local KoboldCPP thinking model flag (separate from remote reasoning toggle)
  bool _koboldThinkingModel = false;

  // TTS settings
  bool _ttsEnabled = false;
  String _ttsEngine = 'kokoro'; // 'kokoro', 'openai', 'elevenlabs', 'piper'
  String _ttsVoiceModel =
      ''; // voice key, e.g. 'af_heart' or 'en_US-lessac-medium'
  double _ttsSpeechRate = 1.0;
  bool _ttsAutoPlay = false;
  String _openaiTtsApiKey = '';
  String _openaiTtsModel = 'tts-1'; // 'tts-1' or 'tts-1-hd'
  String _openaiTtsBaseUrl =
      'https://api.openai.com/v1'; // customizable endpoint for OpenAI-compatible TTS
  String _elevenlabsApiKey = '';
  String _elevenlabsModel = 'eleven_flash_v2_5';
  double _elevenlabsStability = 0.5;
  double _elevenlabsSimilarity = 0.75;
  double _elevenlabsStyle = 0.0;
  bool _ttsNarrateQuotedOnly = false;
  bool _ttsIgnoreAsterisks = false;
  int _ttsConcurrency = Platform.numberOfProcessors.clamp(1, 8);
  int _ttsAudioLookahead = 6; // How many future chunks the OrderedAudioCollector will buffer
  double _directorDelay =
      15.0; // seconds between auto-chat responses in Director Mode

  // STT (Speech-to-Text) settings
  bool _sttEnabled = false;
  String _whisperModel = 'base.en'; // 'tiny.en', 'base.en', 'small.en'
  bool _autoSendTranscription = false;
  String? _selectedMicId;
  String _callModelName = ''; // separate LLM model for voice call mode
  int _callBufferSentences = 3; // how many sentences to buffer before playback
  String _callSystemPrompt =
      'You are on a live voice call. Respond naturally as if speaking on the phone. '
      'ALWAYS write in first person — never narrate in third person. '
      'Keep responses concise: 1-3 sentences max. '
      'No actions, no narration, no stage directions — just speak directly.';

  // Sort preference
  String _sortMode = 'name'; // 'name', 'recent', 'importDate'

  // Grid scale preference
  double _gridScale = 300.0; // maxCrossAxisExtent in pixels (150-450)

  // Cloud sync settings
  bool _cloudSyncEnabled = false;
  String _cloudSyncProvider = 'none'; // 'none', 'webdav', 'gdrive'
  String _cloudSyncUrl = '';
  String _cloudSyncUsername = '';
  String _cloudSyncPassword = '';
  String _cloudSyncLastTime = '';

  // Image generation settings
  bool _imageGenEnabled = false;
  String _imageGenBackend = 'remote'; // 'remote', 'a1111', 'drawthings'
  String _localImageGenUrl = 'http://127.0.0.1:7860';
  String _imageGenModel = '';
  String _imageGenSize = '1024x1024';
  String _imageGenNegativePrompt = 'blurry, low quality, watermark, text';
  String _imageGenStyle = 'photorealistic';
  String _imageGenPromptParadigm = 'natural'; // 'natural', 'tags'
  String _imageGenLora = ''; // selected LoRA filename (A1111/Forge/SDNext only)
  double _imageGenLoraWeight = 0.8; // LoRA strength 0.0–1.0
  int    _imageGenSteps = 20; // sampling steps (5-50)
  double _imageGenCfgScale = 7.0; // CFG scale (1.0-20.0)
  String _imageGenSampler = 'Euler a'; // sampler name
  int    _imageGenSeed = -1; // -1 = random

  // Web server settings
  bool _webServerEnabled = false;
  int _webServerPort = 8085;
  String _webServerPin = '';

  // Summary settings
  bool _summaryEnabled = false;
  int _summaryInterval = 10; // generate/update summary every N user messages
  int _summaryMaxWords = 200; // target max words for the summary
  static const String defaultSummaryPrompt =
      'Provide a concise summary of the conversation so far in {{words}} words or fewer. '
      'Focus on: key plot points, character developments, important decisions, emotional shifts, '
      'and any established facts. Preserve character names, locations, and relationships. '
      'If a previous summary exists, update it with new events rather than starting fresh.';
  String _summaryPrompt = defaultSummaryPrompt;

  // Banned phrases (anti-slop)
  List<String> _bannedPhrases = [];

  // RAG memory settings
  bool _ragEnabled = false;
  int _ragRetrievalCount = 10;
  int _ragWindowSize = 5;
  String _ragEmbeddingSource = 'auto'; // 'auto', 'onnx', 'kobold', 'api'
  String _ragEmbeddingModel = 'text-embedding-3-small';

  // Auto-persona settings
  bool _autoPersonaEnabled = false;
  int _autoPersonaInterval = 10; // every N user messages

  // Character evolution settings
  bool _characterEvolutionEnabled = false;
  int _evolutionInterval =
      10; // unified with fact extraction (every N user messages)

  // Realism Engine global defaults (applied to new sessions / characters without extensions)
  bool _realismDefault = false; // Default to off for global realism control
  bool _nsfwCooldownDefault = false;
  bool _passageOfTimeDefault = true;

  // Realism Engine performance settings
  bool _realismOneShotEval =
      false; // fuse relationship + scene eval into one LLM call

  Directory get customBackgroundDir =>
      Directory(path.join(_rootPath ?? '', 'custom_backgrounds'));

  // Getters
  String get systemPrompt => _systemPrompt;
  double get minP => _minP;
  double get temperature => _temperature;
  double get bubbleOpacity => _bubbleOpacity;
  Color get globalUserBubbleColor => _globalUserBubbleColor;
  Color get globalUserTextColor => _globalUserTextColor;
  Color get globalAiBubbleColor => _globalAiBubbleColor;
  Color get globalAiTextColor => _globalAiTextColor;
  Color get globalDialogueColor => _globalDialogueColor;
  Color get globalActionColor => _globalActionColor;
  String get globalChatFontFamily => _globalChatFontFamily;
  double get repeatPenalty => _repeatPenalty;
  int get repeatPenaltyTokens => _repeatPenaltyTokens;
  bool get dynamicTempEnabled => _dynamicTempEnabled;
  double get dynamicTempRange => _dynamicTempRange;
  double get xtcThreshold => _xtcThreshold;
  double get xtcProbability => _xtcProbability;
  bool? get useCublas => _useCublas;
  bool? get useVulkan => _useVulkan;
  bool? get useMetal => _useMetal;
  bool? get useRocm => _useRocm;
  bool get flashAttentionEnabled => _flashAttentionEnabled;
  bool get mlockEnabled          => _mlockEnabled;
  int  get blasBatchSize         => _blasBatchSize;
  int  get gpuId                 => _gpuId;
  int get maxLength => _maxLength;
  int get minLength => _minLength;
  bool get autostartBackend => _autostartBackend;
  String? get lastUsedModelPath => _lastUsedModelPath;
  String? get activeKcppsPath => _activeKcppsPath;
  /// Whether the active .kcpps preset specifies its own model path.
  /// When true the Flutter model picker should be greyed out.
  bool get kcppsHasModel => _kcppsHasModel;
  Map<String, String> get modelPresetMap => Map.unmodifiable(_modelPresetMap);
  int get gpuLayers => _gpuLayers;
  int get contextSize => _contextSize;
  List<String> get stopSequences => List.unmodifiable(_stopSequences);
  double get textScale => _textScale;
  String get chatBackground => _chatBackground;
  List<Map<String, String>> get customBackgrounds =>
      List.unmodifiable(_customBackgrounds);
  List<Map<String, String>> get savedPrompts =>
      List.unmodifiable(_savedPrompts);
  bool get displayBufferEnabled => _displayBufferEnabled;
  double get targetDisplayTps => _targetDisplayTps;
  double get bufferDurationSeconds => _bufferDurationSeconds;
  String get backendType => _backendType;
  String get remoteApiKey => _remoteApiKey;
  String get remoteApiUrl => _remoteApiUrl;
  String get remoteModelName => _remoteModelName;
  bool get reasoningEnabled => _reasoningEnabled;
  String get reasoningEffort => _reasoningEffort;
  bool get koboldThinkingModel => _koboldThinkingModel;
  bool get ttsEnabled => _ttsEnabled;
  String get ttsEngine => _ttsEngine;
  String get ttsVoiceModel => _ttsVoiceModel;
  double get ttsSpeechRate => _ttsSpeechRate;
  bool get ttsAutoPlay => _ttsAutoPlay;
  String get openaiTtsApiKey => _openaiTtsApiKey;
  String get openaiTtsModel => _openaiTtsModel;
  String get openaiTtsBaseUrl => _openaiTtsBaseUrl;
  String get elevenlabsApiKey => _elevenlabsApiKey;
  String get elevenlabsModel => _elevenlabsModel;
  double get elevenlabsStability => _elevenlabsStability;
  double get elevenlabsSimilarity => _elevenlabsSimilarity;
  double get elevenlabsStyle => _elevenlabsStyle;
  bool get ttsNarrateQuotedOnly => _ttsNarrateQuotedOnly;
  bool get ttsIgnoreAsterisks => _ttsIgnoreAsterisks;
  int get ttsConcurrency => _ttsConcurrency.clamp(1, 8);
  int get ttsAudioLookahead => _ttsAudioLookahead;
  double get directorDelay => _directorDelay;
  bool get sttEnabled => _sttEnabled;
  String get whisperModel => _whisperModel;
  bool get autoSendTranscription => _autoSendTranscription;
  String? get selectedMicId => _selectedMicId;
  String get callModelName => _callModelName;
  int get callBufferSentences => _callBufferSentences;
  String get callSystemPrompt => _callSystemPrompt;
  String get sortMode => _sortMode;
  double get gridScale => _gridScale;
  bool get cloudSyncEnabled => _cloudSyncEnabled;
  String get cloudSyncProvider => _cloudSyncProvider;
  String get cloudSyncUrl => _cloudSyncUrl;
  String get cloudSyncUsername => _cloudSyncUsername;
  String get cloudSyncPassword => _cloudSyncPassword;
  String get cloudSyncLastTime => _cloudSyncLastTime;
  bool get imageGenEnabled => _imageGenEnabled;
  String get imageGenBackend => _imageGenBackend;
  String get localImageGenUrl => _localImageGenUrl;
  String get imageGenModel => _imageGenModel;
  String get imageGenSize => _imageGenSize;
  String get imageGenNegativePrompt => _imageGenNegativePrompt;
  String get imageGenStyle => _imageGenStyle;
  String get imageGenPromptParadigm => _imageGenPromptParadigm;
  String get imageGenLora => _imageGenLora;
  double get imageGenLoraWeight => _imageGenLoraWeight;
  int    get imageGenSteps => _imageGenSteps;
  double get imageGenCfgScale => _imageGenCfgScale;
  String get imageGenSampler => _imageGenSampler;
  int    get imageGenSeed => _imageGenSeed;

  bool get webServerEnabled => _webServerEnabled;
  int get webServerPort => _webServerPort;
  String get webServerPin => _webServerPin;
  bool get summaryEnabled => _summaryEnabled;
  int get summaryInterval => _summaryInterval;
  int get summaryMaxWords => _summaryMaxWords;
  String get summaryPrompt => _summaryPrompt;
  List<String> get bannedPhrases => List.unmodifiable(_bannedPhrases);

  int get kvQuantizationLevel => _kvQuantizationLevel;
  int _kvQuantizationLevel = 0;
  bool get ragEnabled => _ragEnabled;
  int get ragRetrievalCount => _ragRetrievalCount;
  int get ragWindowSize => _ragWindowSize;
  String get ragEmbeddingSource => _ragEmbeddingSource;
  String get ragEmbeddingModel => _ragEmbeddingModel;
  bool get autoPersonaEnabled => _autoPersonaEnabled;
  int get autoPersonaInterval => _autoPersonaInterval;
  bool get characterEvolutionEnabled => _characterEvolutionEnabled;
  int get evolutionInterval => _evolutionInterval;
  bool get realismDefault => _realismDefault;
  bool get nsfwCooldownDefault => _nsfwCooldownDefault;
  bool get passageOfTimeDefault => _passageOfTimeDefault;
  bool get realismOneShotEval => _realismOneShotEval;

  StorageService() {
    _init();
  }

  // ── Beta / stable isolation ────────────────────────────────────────────────
  //
  // ALL of the logic below is driven by [isPreRelease] from app_version.dart.
  // When a stable tag is built (e.g. v0.9.8 — no "-Beta" suffix),
  // isPreRelease returns false and every method here behaves exactly as before.
  // No code needs to be reverted when merging the beta branch into main.

  /// SharedPreferences key used to persist the root data directory.
  /// Beta builds use a separate key so a custom beta path never overwrites
  /// the user's stable path choice.
  static String get _rootPathKey =>
      isPreRelease ? 'root_path_beta' : 'root_path';

  /// Prefix all SharedPreferences keys for beta builds so settings (API keys,
  /// TTS config, etc.) are completely isolated from the stable installation.
  /// Returns [key] unchanged for stable builds — zero reversal needed on merge.
  static String _k(String key) => isPreRelease ? 'beta_$key' : key;

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    final docsDir = await getApplicationDocumentsDirectory();
    // Beta builds default to a completely separate data directory so they
    // never touch a stable user's characters, chats, or database.
    final defaultRootName = isPreRelease ? 'FrontPorchAI-Beta' : 'FrontPorchAI';
    final defaultRoot = path.join(docsDir.path, defaultRootName);
    _rootPath = _prefs?.getString(_rootPathKey) ?? defaultRoot;
    _binDir = Directory(path.join(_rootPath!, 'koboldcpp_bin'));

    // Ensure directories exist
    await chatsDir.create(recursive: true);
    await modelsDir.create(recursive: true);
    await worldsDir.create(recursive: true);
    await charactersDir.create(recursive: true);
    await customBackgroundDir.create(recursive: true);

    // Load settings
    _systemPrompt = _prefs?.getString(_k('system_prompt')) ?? _systemPrompt;
    _minP = _prefs?.getDouble(_k('min_p')) ?? _minP;
    _temperature = _prefs?.getDouble(_k('temperature')) ?? _temperature;
    _bubbleOpacity = _prefs?.getDouble(_k('bubble_opacity')) ?? _bubbleOpacity;
    _globalUserBubbleColor = Color(_prefs?.getInt(_k('global_user_bubble_color')) ?? _globalUserBubbleColor.value);
    _globalUserTextColor = Color(_prefs?.getInt(_k('global_user_text_color')) ?? _globalUserTextColor.value);
    _globalAiBubbleColor = Color(_prefs?.getInt(_k('global_ai_bubble_color')) ?? _globalAiBubbleColor.value);
    _globalAiTextColor = Color(_prefs?.getInt(_k('global_ai_text_color')) ?? _globalAiTextColor.value);
    _globalDialogueColor = Color(_prefs?.getInt(_k('global_dialogue_color')) ?? _globalDialogueColor.value);
    _globalActionColor = Color(_prefs?.getInt(_k('global_action_color')) ?? _globalActionColor.value);
    _globalChatFontFamily = _prefs?.getString(_k('global_chat_font_family')) ?? _globalChatFontFamily;
    _repeatPenalty = _prefs?.getDouble(_k('repeat_penalty')) ?? _repeatPenalty;
    _repeatPenaltyTokens =
        _prefs?.getInt(_k('repeat_penalty_tokens')) ?? _repeatPenaltyTokens;
    _dynamicTempEnabled =
        _prefs?.getBool(_k('dynamic_temp_enabled')) ?? _dynamicTempEnabled;
    _dynamicTempRange =
        _prefs?.getDouble(_k('dynamic_temp_range')) ?? _dynamicTempRange;
    _xtcThreshold = _prefs?.getDouble(_k('xtc_threshold')) ?? _xtcThreshold;
    _xtcProbability = _prefs?.getDouble(_k('xtc_probability')) ?? _xtcProbability;
    _useCublas = _prefs?.getBool(_k('use_cublas'));
    _useVulkan = _prefs?.getBool(_k('use_vulkan'));
    _useMetal = _prefs?.getBool(_k('use_metal'));
    _useRocm = _prefs?.getBool(_k('use_rocm'));
    _flashAttentionEnabled = _prefs?.getBool(_k('flash_attention_enabled')) ?? _flashAttentionEnabled;
    _mlockEnabled          = _prefs?.getBool(_k('mlock_enabled'))           ?? _mlockEnabled;
    // Cleanup orphaned prefs
    await _prefs?.remove(_k('context_shift_enabled'));
    _blasBatchSize         = _prefs?.getInt(_k('blas_batch_size'))          ?? _blasBatchSize;
    _gpuId                 = _prefs?.getInt(_k('gpu_id'))                   ?? _gpuId;
    _maxLength = _prefs?.getInt(_k('max_length')) ?? _maxLength;
    _minLength = _prefs?.getInt(_k('min_length')) ?? _minLength;
    _autostartBackend =
        _prefs?.getBool(_k('autostart_backend')) ?? _autostartBackend;
    _lastUsedModelPath = _prefs?.getString(_k('last_used_model_path'));
    _activeKcppsPath = _prefs?.getString(_k('active_kcpps_path'));
    // Restore the kcppsHasModel flag and context size from the persisted preset path so the UI
    // is correct immediately after a hot restart or app relaunch.
    final parsed = _parseKcppsFile(_activeKcppsPath);
    _kcppsHasModel = parsed != null && parsed['model'] is String && (parsed['model'] as String).trim().isNotEmpty;
    if (parsed != null && parsed['contextsize'] is int) {
      _contextSize = parsed['contextsize'] as int;
    }
    final presetMapJson = _prefs?.getString(_k('model_preset_map'));
    if (presetMapJson != null) {
      try {
        _modelPresetMap = Map<String, String>.from(jsonDecode(presetMapJson) as Map);
      } catch (_) {
        _modelPresetMap = {};
      }
    }
    _gpuLayers = _prefs?.getInt(_k('gpu_layers')) ?? _gpuLayers;
    _contextSize = _prefs?.getInt(_k('context_size')) ?? _contextSize;
    _stopSequences = _prefs?.getStringList(_k('stop_sequences')) ?? _stopSequences;
    // Ensure essential stop sequences are always present (migration for existing users)
    const essentialStops = ['</END>', '[END]', '<|end|>', '<START>'];
    bool added = false;
    for (final s in essentialStops) {
      if (!_stopSequences.contains(s)) {
        _stopSequences.add(s);
        added = true;
      }
    }
    if (added) {
      _prefs?.setStringList(_k('stop_sequences'), _stopSequences);
    }
    _textScale = _prefs?.getDouble(_k('text_scale')) ?? 1.0;
    _chatBackground = _prefs?.getString(_k('chat_background')) ?? 'none';
    final customBgJson = _prefs?.getString(_k('custom_backgrounds'));
    if (customBgJson != null) {
      try {
        _customBackgrounds = (jsonDecode(customBgJson) as List)
            .map((e) => Map<String, String>.from(e as Map))
            .toList();
      } catch (_) {
        _customBackgrounds = [];
      }
    }
    _displayBufferEnabled = _prefs?.getBool(_k('display_buffer_enabled')) ?? true;
    _targetDisplayTps = _prefs?.getDouble(_k('target_display_tps')) ?? 30.0;
    _bufferDurationSeconds =
        _prefs?.getDouble(_k('buffer_duration_seconds')) ?? 3.0;

    // External API settings
    _backendType = _prefs?.getString(_k('backend_type')) ?? 'kobold';
    _remoteApiKey = _prefs?.getString(_k('remote_api_key')) ?? '';
    _remoteApiUrl =
        _prefs?.getString(_k('remote_api_url')) ?? 'https://openrouter.ai/api/v1';
    _remoteModelName = _prefs?.getString(_k('remote_model_name')) ?? '';
    _reasoningEnabled = _prefs?.getBool(_k('reasoning_enabled')) ?? false;
    _reasoningEffort = _prefs?.getString(_k('reasoning_effort')) ?? 'medium';
    _koboldThinkingModel = _prefs?.getBool(_k('kobold_thinking_model')) ?? false;

    // TTS settings
    _ttsEnabled = _prefs?.getBool(_k('tts_enabled')) ?? false;
    _ttsEngine = _prefs?.getString(_k('tts_engine')) ?? 'kokoro';
    _ttsVoiceModel = _prefs?.getString(_k('tts_voice_model')) ?? '';
    _ttsSpeechRate = _prefs?.getDouble(_k('tts_speech_rate')) ?? 1.0;
    _ttsAutoPlay = _prefs?.getBool(_k('tts_auto_play')) ?? false;
    _openaiTtsApiKey = _prefs?.getString(_k('openai_tts_api_key')) ?? '';
    _ttsConcurrency = (_prefs?.getInt(_k('tts_concurrency')) ??
        Platform.numberOfProcessors).clamp(1, 8);
    _ttsAudioLookahead = _prefs?.getInt(_k('tts_audio_lookahead')) ?? 6;
    _kvQuantizationLevel = _prefs?.getInt(_k('kv_quantization_level')) ?? 0;
    _openaiTtsModel = _prefs?.getString(_k('openai_tts_model')) ?? 'tts-1';
    _openaiTtsBaseUrl =
        _prefs?.getString(_k('openai_tts_base_url')) ?? 'https://api.openai.com/v1';
    _elevenlabsApiKey = _prefs?.getString(_k('elevenlabs_api_key')) ?? '';
    _elevenlabsModel =
        _prefs?.getString(_k('elevenlabs_model')) ?? 'eleven_flash_v2_5';
    _elevenlabsStability = _prefs?.getDouble(_k('elevenlabs_stability')) ?? 0.5;
    _elevenlabsSimilarity = _prefs?.getDouble(_k('elevenlabs_similarity')) ?? 0.75;
    _elevenlabsStyle = _prefs?.getDouble(_k('elevenlabs_style')) ?? 0.0;
    _ttsNarrateQuotedOnly = _prefs?.getBool(_k('tts_narrate_quoted_only')) ?? false;
    _ttsIgnoreAsterisks = _prefs?.getBool(_k('tts_ignore_asterisks')) ?? false;
    _directorDelay = _prefs?.getDouble(_k('director_delay')) ?? 15.0;

    // STT settings
    _sttEnabled = _prefs?.getBool(_k('stt_enabled')) ?? false;
    _whisperModel = _prefs?.getString(_k('whisper_model')) ?? 'base.en';
    _autoSendTranscription =
        _prefs?.getBool(_k('auto_send_transcription')) ?? false;
    _selectedMicId = _prefs?.getString(_k('selected_mic_id'));
    _callModelName = _prefs?.getString(_k('call_model_name')) ?? '';
    _callBufferSentences = _prefs?.getInt(_k('call_buffer_sentences')) ?? 3;
    final savedCallPrompt = _prefs?.getString(_k('call_system_prompt'));
    if (savedCallPrompt != null) _callSystemPrompt = savedCallPrompt;

    _sortMode = _prefs?.getString(_k('sort_mode')) ?? 'name';
    _gridScale = _prefs?.getDouble(_k('grid_scale')) ?? 300.0;

    // Cloud sync settings
    _cloudSyncEnabled = _prefs?.getBool(_k('cloud_sync_enabled')) ?? false;
    _cloudSyncProvider = _prefs?.getString(_k('cloud_sync_provider')) ?? 'none';
    _cloudSyncUrl = _prefs?.getString(_k('cloud_sync_url')) ?? '';
    _cloudSyncUsername = _prefs?.getString(_k('cloud_sync_username')) ?? '';
    _cloudSyncPassword = _prefs?.getString(_k('cloud_sync_password')) ?? '';
    _cloudSyncLastTime = _prefs?.getString(_k('cloud_sync_last_time')) ?? '';

    // Image generation settings
    _imageGenEnabled = _prefs?.getBool(_k('image_gen_enabled')) ?? false;
    _imageGenBackend = _prefs?.getString(_k('image_gen_backend')) ?? 'remote';
    _localImageGenUrl =
        _prefs?.getString(_k('local_image_gen_url')) ?? 'http://127.0.0.1:7860';
    _imageGenModel = _prefs?.getString(_k('image_gen_model')) ?? '';
    _imageGenSize = _prefs?.getString(_k('image_gen_size')) ?? '1024x1024';
    _imageGenNegativePrompt =
        _prefs?.getString(_k('image_gen_negative_prompt')) ??
        'blurry, low quality, watermark, text';
    _imageGenStyle = _prefs?.getString(_k('image_gen_style')) ?? 'photorealistic';
    _imageGenPromptParadigm =
        _prefs?.getString(_k('image_gen_prompt_paradigm')) ?? 'natural';
    _imageGenLora = _prefs?.getString(_k('image_gen_lora')) ?? '';
    _imageGenLoraWeight = _prefs?.getDouble(_k('image_gen_lora_weight')) ?? 0.8;
    _imageGenSteps = _prefs?.getInt(_k('image_gen_steps')) ?? 20;
    _imageGenCfgScale = _prefs?.getDouble(_k('image_gen_cfg_scale')) ?? 7.0;
    _imageGenSampler = _prefs?.getString(_k('image_gen_sampler')) ?? 'Euler a';
    _imageGenSeed = _prefs?.getInt(_k('image_gen_seed')) ?? -1;

    // Web server settings
    _webServerEnabled = _prefs?.getBool(_k('web_server_enabled')) ?? false;
    _webServerPort = _prefs?.getInt(_k('web_server_port')) ?? 8085;
    _webServerPin = _prefs?.getString(_k('web_server_pin')) ?? '';

    // Custom models path
    _customModelsPath = _prefs?.getString(_k('custom_models_path'));

    // Summary settings
    _summaryEnabled = _prefs?.getBool(_k('summary_enabled')) ?? false;
    _summaryInterval = _prefs?.getInt(_k('summary_interval')) ?? 10;
    _summaryMaxWords = _prefs?.getInt(_k('summary_max_words')) ?? 200;
    _summaryPrompt =
        _prefs?.getString(_k('summary_prompt')) ?? defaultSummaryPrompt;

    // Banned phrases
    final bannedJson = _prefs?.getString(_k('banned_phrases'));
    if (bannedJson != null) {
      try {
        _bannedPhrases = List<String>.from(jsonDecode(bannedJson) as List);
      } catch (_) {
        _bannedPhrases = [];
      }
    }

    // RAG memory settings
    _ragEnabled = _prefs?.getBool(_k('rag_enabled')) ?? false;
    _ragRetrievalCount = _prefs?.getInt(_k('rag_retrieval_count')) ?? 5;
    _ragWindowSize = _prefs?.getInt(_k('rag_window_size')) ?? 5;
    _ragEmbeddingSource = _prefs?.getString(_k('rag_embedding_source')) ?? 'auto';
    _ragEmbeddingModel =
        _prefs?.getString(_k('rag_embedding_model')) ?? 'text-embedding-3-small';

    // Auto-persona settings
    _autoPersonaEnabled = _prefs?.getBool(_k('auto_persona_enabled')) ?? false;
    _autoPersonaInterval = _prefs?.getInt(_k('auto_persona_interval')) ?? 10;

    // Character evolution settings
    _characterEvolutionEnabled =
        _prefs?.getBool(_k('character_evolution_enabled')) ?? false;
    _evolutionInterval = _prefs?.getInt(_k('evolution_interval')) ?? 10;

    // Realism Engine global defaults
    _realismDefault = _prefs?.getBool(_k('realism_default')) ?? false;
    _nsfwCooldownDefault = _prefs?.getBool(_k('nsfw_cooldown_default')) ?? false;
    _passageOfTimeDefault = _prefs?.getBool(_k('passage_of_time_default')) ?? true;

    // Realism Engine performance settings
    _realismOneShotEval = _prefs?.getBool(_k('realism_one_shot_eval')) ?? false;

    // Expression Images settings
    _expressionEnabled = _prefs?.getBool(_k('expression_enabled')) ?? false;
    _expressionClassificationMode =
        _prefs?.getString(_k('expression_classification_mode')) ?? 'llm';
    _expressionDisplayMode =
        _prefs?.getString(_k('expression_display_mode')) ?? 'sidebar';
    _expressionRerollSame = _prefs?.getBool(_k('expression_reroll_same')) ?? false;
    _expressionFallback =
        _prefs?.getString(_k('expression_fallback')) ?? 'neutral';

    // Load saved prompts
    final promptsJson = _prefs?.getString(_k('saved_prompts'));
    if (promptsJson != null) {
      final decoded = jsonDecode(promptsJson) as List;
      _savedPrompts = decoded
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    }
    // Always ensure the built-in default preset exists
    if (!_savedPrompts.any((p) => p['name'] == 'Immersive Roleplay')) {
      _savedPrompts.insert(0, {
        'name': 'Immersive Roleplay',
        'content': defaultSystemPrompt,
      });
      await _persistPrompts();
    }

    if (!_initCompleter.isCompleted) _initCompleter.complete();
    notifyListeners();
  }

  /// Change the root installation directory and relocate all data files.
  /// Moves KoboldManager/ (DB + characters), chats/, worlds/, and models/
  /// from the old root to the new one. Closes and reopens the database.
  Future<void> setRootPath(String pathStr) async {
    final oldRoot = _rootPath;
    if (oldRoot == pathStr) return; // No-op if same path

    // Directories to move from old root to new root
    final dirsToMove = [
      'KoboldManager',
      'chats',
      'worlds',
      'models',
      'koboldcpp_bin',
    ];

    for (final dirName in dirsToMove) {
      final oldDir = Directory(path.join(oldRoot ?? '', dirName));
      final newDir = Directory(path.join(pathStr, dirName));
      if (await oldDir.exists() && !await newDir.exists()) {
        try {
          await newDir.create(recursive: true);
          await for (final entity in oldDir.list(recursive: false)) {
            final baseName = path.basename(entity.path);
            final newPath = path.join(newDir.path, baseName);
            if (entity is File) {
              await entity.copy(newPath);
            } else if (entity is Directory) {
              await _copyDirectory(entity, Directory(newPath));
            }
          }
          // Clean up old directory after successful copy
          await oldDir.delete(recursive: true);
          debugPrint('Relocated $dirName to $pathStr (old deleted)');
        } catch (e) {
          debugPrint('Error relocating $dirName: $e');
        }
      }
    }

    _rootPath = pathStr;
    _binDir = Directory(path.join(_rootPath!, 'koboldcpp_bin'));
    await _prefs?.setString(_rootPathKey, pathStr);

    // Ensure directories exist at the new location
    await chatsDir.create(recursive: true);
    await modelsDir.create(recursive: true);
    await worldsDir.create(recursive: true);
    await charactersDir.create(recursive: true);

    notifyListeners();
  }

  /// Recursively copy a directory and its contents.
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final baseName = path.basename(entity.path);
      final newPath = path.join(destination.path, baseName);
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }

  Future<void> setSystemPrompt(String value) async {
    _systemPrompt = value;
    await _prefs?.setString(_k('system_prompt'), value);
    notifyListeners();
  }

  Future<void> savePrompt(String name, String content) async {
    // Remove existing with same name to overwrite
    _savedPrompts.removeWhere((p) => p['name'] == name);
    _savedPrompts.add({'name': name, 'content': content});
    await _persistPrompts();
    notifyListeners();
  }

  Future<void> deleteSavedPrompt(String name) async {
    _savedPrompts.removeWhere((p) => p['name'] == name);
    await _persistPrompts();
    notifyListeners();
  }

  void loadSavedPrompt(String name) {
    final prompt = _savedPrompts.firstWhere(
      (p) => p['name'] == name,
      orElse: () => {},
    );
    if (prompt.containsKey('content')) {
      setSystemPrompt(prompt['content']!);
    }
  }

  Future<void> _persistPrompts() async {
    await _prefs?.setString(_k('saved_prompts'), jsonEncode(_savedPrompts));
  }

  Future<void> setMinP(double value) async {
    _minP = value;
    await _prefs?.setDouble(_k('min_p'), value);
    notifyListeners();
  }

  Future<void> setTemperature(double value) async {
    _temperature = value;
    await _prefs?.setDouble(_k('temperature'), value);
    notifyListeners();
  }

  Future<void> setBubbleOpacity(double value) async {
    _bubbleOpacity = value;
    await _prefs?.setDouble(_k('bubble_opacity'), value);
    notifyListeners();
  }

  Future<void> setRepeatPenalty(double value) async {
    _repeatPenalty = value;
    await _prefs?.setDouble(_k('repeat_penalty'), value);
    notifyListeners();
  }

  Future<void> setRepeatPenaltyTokens(int value) async {
    _repeatPenaltyTokens = value;
    await _prefs?.setInt(_k('repeat_penalty_tokens'), value);
    notifyListeners();
  }

  Future<void> setXtcThreshold(double value) async {
    _xtcThreshold = value;
    await _prefs?.setDouble(_k('xtc_threshold'), value);
    notifyListeners();
  }

  Future<void> setXtcProbability(double value) async {
    _xtcProbability = value;
    await _prefs?.setDouble(_k('xtc_probability'), value);
    notifyListeners();
  }

  Future<void> setDynamicTempEnabled(bool value) async {
    _dynamicTempEnabled = value;
    await _prefs?.setBool(_k('dynamic_temp_enabled'), value);
    notifyListeners();
  }

  Future<void> setDynamicTempRange(double value) async {
    _dynamicTempRange = value;
    await _prefs?.setDouble(_k('dynamic_temp_range'), value);
    notifyListeners();
  }

  Future<void> setUseCublas(bool value) async {
    _useCublas = value;
    await _prefs?.setBool(_k('use_cublas'), value);
    notifyListeners();
  }

  Future<void> setUseVulkan(bool value) async {
    _useVulkan = value;
    await _prefs?.setBool(_k('use_vulkan'), value);
    notifyListeners();
  }

  Future<void> setUseMetal(bool value) async {
    _useMetal = value;
    await _prefs?.setBool(_k('use_metal'), value);
    notifyListeners();
  }

  Future<void> setUseRocm(bool value) async {
    _useRocm = value;
    await _prefs?.setBool(_k('use_rocm'), value);
    notifyListeners();
  }

  Future<void> setFlashAttentionEnabled(bool value) async {
    _flashAttentionEnabled = value;
    await _prefs?.setBool(_k('flash_attention_enabled'), value);
    notifyListeners();
  }

  Future<void> setMlockEnabled(bool value) async {
    _mlockEnabled = value;
    await _prefs?.setBool(_k('mlock_enabled'), value);
    notifyListeners();
  }

  Future<void> setBlasBatchSize(int value) async {
    _blasBatchSize = value;
    await _prefs?.setInt(_k('blas_batch_size'), value);
    notifyListeners();
  }

  Future<void> setGpuId(int value) async {
    _gpuId = value;
    await _prefs?.setInt(_k('gpu_id'), value);
    notifyListeners();
  }

  Future<void> setMaxLength(int value) async {
    _maxLength = value;
    await _prefs?.setInt(_k('max_length'), value);
    notifyListeners();
  }

  Future<void> setMinLength(int value) async {
    _minLength = value;
    await _prefs?.setInt(_k('min_length'), value);
    notifyListeners();
  }

  Future<void> setAutostartBackend(bool value) async {
    _autostartBackend = value;
    await _prefs?.setBool(_k('autostart_backend'), value);
    notifyListeners();
  }

  Future<void> setLastUsedModelPath(String? value) async {
    _lastUsedModelPath = value;
    if (value != null) {
      await _prefs?.setString(_k('last_used_model_path'), value);
    } else {
      await _prefs?.remove(_k('last_used_model_path'));
    }
    notifyListeners();
  }

  Future<void> setActiveKcppsPath(String? value) async {
    _activeKcppsPath = value;
    // Parse synchronously so _kcppsHasModel and _contextSize are accurate in the same notifyListeners call.
    final parsed = _parseKcppsFile(value);
    _kcppsHasModel = parsed != null && parsed['model'] is String && (parsed['model'] as String).trim().isNotEmpty;
    // Update context size from preset if present
    if (parsed != null && parsed['contextsize'] is int) {
      _contextSize = parsed['contextsize'] as int;
      await _prefs?.setInt(_k('context_size'), _contextSize);
    }
    if (value != null) {
      await _prefs?.setString(_k('active_kcpps_path'), value);
    } else {
      await _prefs?.remove(_k('active_kcpps_path'));
    }
    notifyListeners();
  }

  /// Parse a .kcpps JSON file and return the parsed map.
  /// Returns null if the path is invalid or parsing fails.
  static Map<String, dynamic>? _parseKcppsFile(String? kcppsPath) {
    if (kcppsPath == null || kcppsPath.isEmpty) return null;
    try {
      final file = File(kcppsPath);
      if (!file.existsSync()) return null;
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> setModelPreset(String modelPath, String? kcppsPath) async {
    if (kcppsPath != null) {
      _modelPresetMap[modelPath] = kcppsPath;
    } else {
      _modelPresetMap.remove(modelPath);
    }
    await _prefs?.setString(_k('model_preset_map'), jsonEncode(_modelPresetMap));
    notifyListeners();
  }

  Future<void> setGpuLayers(int value) async {
    _gpuLayers = value;
    await _prefs?.setInt(_k('gpu_layers'), value);
    notifyListeners();
  }

  Future<void> setContextSize(int value) async {
    _contextSize = value;
    await _prefs?.setInt(_k('context_size'), value);
    notifyListeners();
  }

  Future<void> setStopSequences(List<String> value) async {
    _stopSequences = value;
    await _prefs?.setStringList(_k('stop_sequences'), value);
    notifyListeners();
  }

  Future<void> addStopSequence(String value) async {
    if (!_stopSequences.contains(value)) {
      _stopSequences.add(value);
      await _prefs?.setStringList(_k('stop_sequences'), _stopSequences);
      notifyListeners();
    }
  }

  Future<void> removeStopSequence(String value) async {
    if (_stopSequences.remove(value)) {
      await _prefs?.setStringList(_k('stop_sequences'), _stopSequences);
      notifyListeners();
    }
  }

  Future<void> setTextScale(double value) async {
    _textScale = value;
    await _prefs?.setDouble(_k('text_scale'), value);
    notifyListeners();
  }

  Future<void> setChatBackground(String value) async {
    _chatBackground = value;
    await _prefs?.setString(_k('chat_background'), value);
    notifyListeners();
  }

  Future<void> addCustomBackground(String id, String name, String filePath) async {
    _customBackgrounds.add({'id': id, 'name': name, 'filePath': filePath});
    await _persistCustomBackgrounds();
    notifyListeners();
  }

  Future<void> removeCustomBackground(String id) async {
    _customBackgrounds.removeWhere((bg) => bg['id'] == id);
    await _persistCustomBackgrounds();
    notifyListeners();
  }

  bool hasCustomBackgroundWithName(String name) {
    return _customBackgrounds.any((bg) => bg['name'] == name);
  }

  Future<void> _persistCustomBackgrounds() async {
    await _prefs?.setString(_k('custom_backgrounds'), jsonEncode(_customBackgrounds));
  }

  Future<void> setDisplayBufferEnabled(bool value) async {
    _displayBufferEnabled = value;
    await _prefs?.setBool(_k('display_buffer_enabled'), value);
    notifyListeners();
  }

  Future<void> setTargetDisplayTps(double value) async {
    _targetDisplayTps = value;
    await _prefs?.setDouble(_k('target_display_tps'), value);
    notifyListeners();
  }

  Future<void> setBufferDurationSeconds(double value) async {
    _bufferDurationSeconds = value;
    await _prefs?.setDouble(_k('buffer_duration_seconds'), value);
    notifyListeners();
  }

  // External API setters
  Future<void> setBackendType(String value) async {
    _backendType = value;
    await _prefs?.setString(_k('backend_type'), value);
    notifyListeners();
  }

  Future<void> setRemoteApiKey(String value) async {
    _remoteApiKey = value;
    await _prefs?.setString(_k('remote_api_key'), value);
    notifyListeners();
  }

  Future<void> setCallModelName(String value) async {
    _callModelName = value;
    await _prefs?.setString(_k('call_model_name'), value);
    notifyListeners();
  }

  Future<void> setCallBufferSentences(int value) async {
    _callBufferSentences = value.clamp(1, 10);
    await _prefs?.setInt(_k('call_buffer_sentences'), _callBufferSentences);
    notifyListeners();
  }

  Future<void> setCallSystemPrompt(String value) async {
    _callSystemPrompt = value;
    await _prefs?.setString(_k('call_system_prompt'), value);
    notifyListeners();
  }

  Future<void> setRemoteApiUrl(String value) async {
    _remoteApiUrl = value;
    await _prefs?.setString(_k('remote_api_url'), value);
    notifyListeners();
  }

  Future<void> setRemoteModelName(String value) async {
    _remoteModelName = value;
    await _prefs?.setString(_k('remote_model_name'), value);
    notifyListeners();
  }

  // Reasoning setters
  Future<void> setReasoningEnabled(bool value) async {
    _reasoningEnabled = value;
    await _prefs?.setBool(_k('reasoning_enabled'), value);
    notifyListeners();
  }

  Future<void> setReasoningEffort(String value) async {
    _reasoningEffort = value;
    await _prefs?.setString(_k('reasoning_effort'), value);
    notifyListeners();
  }

  Future<void> setKoboldThinkingModel(bool value) async {
    _koboldThinkingModel = value;
    await _prefs?.setBool(_k('kobold_thinking_model'), value);
    notifyListeners();
  }

  // TTS setters
  Future<void> setTtsEnabled(bool value) async {
    _ttsEnabled = value;
    await _prefs?.setBool(_k('tts_enabled'), value);
    notifyListeners();
  }

  Future<void> setTtsEngine(String value) async {
    _ttsEngine = value;
    await _prefs?.setString(_k('tts_engine'), value);
    notifyListeners();
  }

  Future<void> setTtsVoiceModel(String value) async {
    _ttsVoiceModel = value;
    await _prefs?.setString(_k('tts_voice_model'), value);
    notifyListeners();
  }

  Future<void> setTtsSpeechRate(double value) async {
    _ttsSpeechRate = value;
    await _prefs?.setDouble(_k('tts_speech_rate'), value);
    notifyListeners();
  }

  Future<void> setTtsAutoPlay(bool value) async {
    _ttsAutoPlay = value;
    await _prefs?.setBool(_k('tts_auto_play'), value);
    notifyListeners();
  }

  Future<void> setOpenaiTtsApiKey(String value) async {
    _openaiTtsApiKey = value;
    await _prefs?.setString(_k('openai_tts_api_key'), value);
    notifyListeners();
  }

  Future<void> setOpenaiTtsModel(String value) async {
    _openaiTtsModel = value;
    await _prefs?.setString(_k('openai_tts_model'), value);
    notifyListeners();
  }

  Future<void> setOpenaiTtsBaseUrl(String value) async {
    _openaiTtsBaseUrl = value;
    await _prefs?.setString(_k('openai_tts_base_url'), value);
    notifyListeners();
  }

  Future<void> setElevenlabsApiKey(String value) async {
    _elevenlabsApiKey = value;
    await _prefs?.setString(_k('elevenlabs_api_key'), value);
    notifyListeners();
  }

  Future<void> setElevenlabsModel(String value) async {
    _elevenlabsModel = value;
    await _prefs?.setString(_k('elevenlabs_model'), value);
    notifyListeners();
  }

  Future<void> setElevenlabsStability(double value) async {
    _elevenlabsStability = value.clamp(0.0, 1.0);
    await _prefs?.setDouble(_k('elevenlabs_stability'), _elevenlabsStability);
    notifyListeners();
  }

  Future<void> setElevenlabsSimilarity(double value) async {
    _elevenlabsSimilarity = value.clamp(0.0, 1.0);
    await _prefs?.setDouble(_k('elevenlabs_similarity'), _elevenlabsSimilarity);
    notifyListeners();
  }

  Future<void> setElevenlabsStyle(double value) async {
    _elevenlabsStyle = value.clamp(0.0, 1.0);
    await _prefs?.setDouble(_k('elevenlabs_style'), _elevenlabsStyle);
    notifyListeners();
  }

  Future<void> setTtsNarrateQuotedOnly(bool value) async {
    _ttsNarrateQuotedOnly = value;
    await _prefs?.setBool(_k('tts_narrate_quoted_only'), value);
    notifyListeners();
  }

  Future<void> setTtsIgnoreAsterisks(bool value) async {
    _ttsIgnoreAsterisks = value;
    await _prefs?.setBool(_k('tts_ignore_asterisks'), value);
    notifyListeners();
  }

  Future<void> setTtsConcurrency(int value) async {
    _ttsConcurrency = value.clamp(1, 8);
    await _prefs?.setInt(_k('tts_concurrency'), _ttsConcurrency);
    notifyListeners();
  }

  Future<void> setTtsAudioLookahead(int value) async {
    _ttsAudioLookahead = value.clamp(1, 32);
    await _prefs?.setInt(_k('tts_audio_lookahead'), _ttsAudioLookahead);
    notifyListeners();
  }

  Future<void> setKvQuantizationLevel(int value) async {
    _kvQuantizationLevel = value;
    await _prefs?.setInt(_k('kv_quantization_level'), value);
    notifyListeners();
  }

  // STT setters
  Future<void> setSttEnabled(bool value) async {
    _sttEnabled = value;
    await _prefs?.setBool(_k('stt_enabled'), value);
    notifyListeners();
  }

  Future<void> setWhisperModel(String value) async {
    _whisperModel = value;
    await _prefs?.setString(_k('whisper_model'), value);
    notifyListeners();
  }

  Future<void> setAutoSendTranscription(bool value) async {
    _autoSendTranscription = value;
    await _prefs?.setBool(_k('auto_send_transcription'), value);
    notifyListeners();
  }

  Future<void> setSelectedMicId(String? value) async {
    _selectedMicId = value;
    if (value != null) {
      await _prefs?.setString(_k('selected_mic_id'), value);
    } else {
      await _prefs?.remove(_k('selected_mic_id'));
    }
    notifyListeners();
  }

  Future<void> setDirectorDelay(double value) async {
    _directorDelay = value.clamp(0.5, 60.0);
    await _prefs?.setDouble(_k('director_delay'), _directorDelay);
    notifyListeners();
  }

  Future<void> setSortMode(String value) async {
    _sortMode = value;
    await _prefs?.setString(_k('sort_mode'), value);
    notifyListeners();
  }

  Future<void> setGridScale(double value) async {
    _gridScale = value.clamp(150.0, 450.0);
    await _prefs?.setDouble(_k('grid_scale'), _gridScale);
    notifyListeners();
  }

  Future<void> setCloudSyncEnabled(bool value) async {
    _cloudSyncEnabled = value;
    await _prefs?.setBool(_k('cloud_sync_enabled'), value);
    notifyListeners();
  }

  Future<void> setCloudSyncProvider(String value) async {
    _cloudSyncProvider = value;
    await _prefs?.setString(_k('cloud_sync_provider'), value);
    notifyListeners();
  }

  Future<void> setCloudSyncUrl(String value) async {
    _cloudSyncUrl = value;
    await _prefs?.setString(_k('cloud_sync_url'), value);
    notifyListeners();
  }

  Future<void> setCloudSyncUsername(String value) async {
    _cloudSyncUsername = value;
    await _prefs?.setString(_k('cloud_sync_username'), value);
    notifyListeners();
  }

  Future<void> setCloudSyncPassword(String value) async {
    _cloudSyncPassword = value;
    await _prefs?.setString(_k('cloud_sync_password'), value);
    notifyListeners();
  }

  Future<void> setCloudSyncLastTime(String value) async {
    _cloudSyncLastTime = value;
    await _prefs?.setString(_k('cloud_sync_last_time'), value);
    notifyListeners();
  }

  Future<void> setCustomModelsPath(String? value) async {
    _customModelsPath = value;
    if (value != null && value.isNotEmpty) {
      await _prefs?.setString(_k('custom_models_path'), value);
    } else {
      await _prefs?.remove(_k('custom_models_path'));
    }
    notifyListeners();
  }

  // Image generation setters
  Future<void> setImageGenEnabled(bool value) async {
    _imageGenEnabled = value;
    await _prefs?.setBool(_k('image_gen_enabled'), value);
    notifyListeners();
  }

  Future<void> setImageGenBackend(String value) async {
    _imageGenBackend = value;
    await _prefs?.setString(_k('image_gen_backend'), value);
    notifyListeners();
  }

  Future<void> setLocalImageGenUrl(String value) async {
    _localImageGenUrl = value;
    await _prefs?.setString(_k('local_image_gen_url'), value);
    notifyListeners();
  }

  Future<void> setImageGenModel(String value) async {
    _imageGenModel = value;
    await _prefs?.setString(_k('image_gen_model'), value);
    notifyListeners();
  }

  Future<void> setImageGenSize(String value) async {
    _imageGenSize = value;
    await _prefs?.setString(_k('image_gen_size'), value);
    notifyListeners();
  }

  Future<void> setImageGenNegativePrompt(String value) async {
    _imageGenNegativePrompt = value;
    await _prefs?.setString(_k('image_gen_negative_prompt'), value);
    notifyListeners();
  }

  Future<void> setImageGenStyle(String value) async {
    _imageGenStyle = value;
    await _prefs?.setString(_k('image_gen_style'), value);
    notifyListeners();
  }

  Future<void> setImageGenPromptParadigm(String value) async {
    _imageGenPromptParadigm = value;
    await _prefs?.setString(_k('image_gen_prompt_paradigm'), value);
    notifyListeners();
  }

  Future<void> setImageGenLora(String value) async {
    _imageGenLora = value;
    await _prefs?.setString(_k('image_gen_lora'), value);
    notifyListeners();
  }

  Future<void> setImageGenLoraWeight(double value) async {
    _imageGenLoraWeight = value.clamp(0.0, 1.0);
    await _prefs?.setDouble(_k('image_gen_lora_weight'), _imageGenLoraWeight);
    notifyListeners();
  }

  Future<void> setImageGenSteps(int value) async {
    _imageGenSteps = value.clamp(5, 50);
    await _prefs?.setInt(_k('image_gen_steps'), _imageGenSteps);
    notifyListeners();
  }

  Future<void> setImageGenCfgScale(double value) async {
    _imageGenCfgScale = value.clamp(1.0, 20.0);
    await _prefs?.setDouble(_k('image_gen_cfg_scale'), _imageGenCfgScale);
    notifyListeners();
  }

  Future<void> setImageGenSampler(String value) async {
    _imageGenSampler = value;
    await _prefs?.setString(_k('image_gen_sampler'), value);
    notifyListeners();
  }

  Future<void> setImageGenSeed(int value) async {
    _imageGenSeed = value;
    await _prefs?.setInt(_k('image_gen_seed'), value);
    notifyListeners();
  }

  // Web server setters
  Future<void> setWebServerEnabled(bool value) async {
    _webServerEnabled = value;
    await _prefs?.setBool(_k('web_server_enabled'), value);
    notifyListeners();
  }

  Future<void> setWebServerPort(int value) async {
    _webServerPort = value;
    await _prefs?.setInt(_k('web_server_port'), value);
    notifyListeners();
  }

  Future<void> setWebServerPin(String value) async {
    _webServerPin = value;
    await _prefs?.setString(_k('web_server_pin'), value);
    notifyListeners();
  }

  // Summary setters
  Future<void> setSummaryEnabled(bool value) async {
    _summaryEnabled = value;
    await _prefs?.setBool(_k('summary_enabled'), value);
    notifyListeners();
  }

  Future<void> setSummaryInterval(int value) async {
    _summaryInterval = value.clamp(3, 50);
    await _prefs?.setInt(_k('summary_interval'), _summaryInterval);
    notifyListeners();
  }

  Future<void> setSummaryMaxWords(int value) async {
    _summaryMaxWords = value.clamp(50, 1000);
    await _prefs?.setInt(_k('summary_max_words'), _summaryMaxWords);
    notifyListeners();
  }

  Future<void> setSummaryPrompt(String value) async {
    _summaryPrompt = value;
    await _prefs?.setString(_k('summary_prompt'), value);
    notifyListeners();
  }

  // Banned phrases setters
  Future<void> setBannedPhrases(List<String> value) async {
    _bannedPhrases = value.where((s) => s.isNotEmpty).toList();
    await _prefs?.setString(_k('banned_phrases'), jsonEncode(_bannedPhrases));
    notifyListeners();
  }

  // RAG memory setters
  Future<void> setRagEnabled(bool value) async {
    _ragEnabled = value;
    await _prefs?.setBool(_k('rag_enabled'), value);
    notifyListeners();
  }

  Future<void> setRagRetrievalCount(int value) async {
    _ragRetrievalCount = value.clamp(0, 50);
    await _prefs?.setInt(_k('rag_retrieval_count'), _ragRetrievalCount);
    notifyListeners();
  }

  Future<void> setRagWindowSize(int value) async {
    _ragWindowSize = value.clamp(2, 15);
    await _prefs?.setInt(_k('rag_window_size'), _ragWindowSize);
    notifyListeners();
  }

  Future<void> setRagEmbeddingSource(String value) async {
    _ragEmbeddingSource = value;
    await _prefs?.setString(_k('rag_embedding_source'), value);
    notifyListeners();
  }

  Future<void> setRagEmbeddingModel(String value) async {
    _ragEmbeddingModel = value;
    await _prefs?.setString(_k('rag_embedding_model'), value);
    notifyListeners();
  }

  // Auto-persona setters
  Future<void> setAutoPersonaEnabled(bool value) async {
    _autoPersonaEnabled = value;
    await _prefs?.setBool(_k('auto_persona_enabled'), value);
    notifyListeners();
  }

  Future<void> setAutoPersonaInterval(int value) async {
    _autoPersonaInterval = value.clamp(5, 50);
    await _prefs?.setInt(_k('auto_persona_interval'), _autoPersonaInterval);
    notifyListeners();
  }

  // Character evolution setters
  Future<void> setCharacterEvolutionEnabled(bool value) async {
    _characterEvolutionEnabled = value;
    await _prefs?.setBool(_k('character_evolution_enabled'), value);
    notifyListeners();
  }

  Future<void> setEvolutionInterval(int value) async {
    _evolutionInterval = value.clamp(10, 50);
    await _prefs?.setInt(_k('evolution_interval'), _evolutionInterval);
    notifyListeners();
  }

  Future<void> setRealismOneShotEval(bool value) async {
    _realismOneShotEval = value;
    await _prefs?.setBool(_k('realism_one_shot_eval'), value);
    notifyListeners();
  }

  Future<void> setRealismDefault(bool value) async {
    _realismDefault = value;
    await _prefs?.setBool(_k('realism_default'), value);
    notifyListeners();
  }

  Future<void> setNsfwCooldownDefault(bool value) async {
    _nsfwCooldownDefault = value;
    await _prefs?.setBool(_k('nsfw_cooldown_default'), value);
    notifyListeners();
  }

  Future<void> setPassageOfTimeDefault(bool value) async {
    _passageOfTimeDefault = value;
    await _prefs?.setBool(_k('passage_of_time_default'), value);
    notifyListeners();
  }

  // Global chat color and font setters
  Future<void> setGlobalUserBubbleColor(Color value) async {
    _globalUserBubbleColor = value;
    await _prefs?.setInt(_k('global_user_bubble_color'), value.value);
    notifyListeners();
  }

  Future<void> setGlobalUserTextColor(Color value) async {
    _globalUserTextColor = value;
    await _prefs?.setInt(_k('global_user_text_color'), value.value);
    notifyListeners();
  }

  Future<void> setGlobalAiBubbleColor(Color value) async {
    _globalAiBubbleColor = value;
    await _prefs?.setInt(_k('global_ai_bubble_color'), value.value);
    notifyListeners();
  }

  Future<void> setGlobalAiTextColor(Color value) async {
    _globalAiTextColor = value;
    await _prefs?.setInt(_k('global_ai_text_color'), value.value);
    notifyListeners();
  }

  Future<void> setGlobalDialogueColor(Color value) async {
    _globalDialogueColor = value;
    await _prefs?.setInt(_k('global_dialogue_color'), value.value);
    notifyListeners();
  }

  Future<void> setGlobalActionColor(Color value) async {
    _globalActionColor = value;
    await _prefs?.setInt(_k('global_action_color'), value.value);
    notifyListeners();
  }

  Future<void> setGlobalChatFontFamily(String value) async {
    _globalChatFontFamily = value;
    await _prefs?.setString(_k('global_chat_font_family'), value);
    notifyListeners();
  }

  /// Get effective user bubble color (per-character overrides global)
  Color getUserBubbleColor(CharacterCard? character) {
    return character?.frontPorchExtensions?.userBubbleColor ?? _globalUserBubbleColor;
  }

  /// Get effective user text color (per-character overrides global)
  Color getUserTextColor(CharacterCard? character) {
    return character?.frontPorchExtensions?.userTextColor ?? _globalUserTextColor;
  }

  /// Get effective AI bubble color (per-character overrides global)
  Color getAiBubbleColor(CharacterCard? character) {
    return character?.frontPorchExtensions?.aiBubbleColor ?? _globalAiBubbleColor;
  }

  /// Get effective AI text color (per-character overrides global)
  Color getAiTextColor(CharacterCard? character) {
    return character?.frontPorchExtensions?.aiTextColor ?? _globalAiTextColor;
  }

  /// Get effective dialogue color (per-character overrides global)
  Color getDialogueColor(CharacterCard? character) {
    return character?.frontPorchExtensions?.dialogueColor ?? _globalDialogueColor;
  }

  /// Get effective action color (per-character overrides global)
  Color getActionColor(CharacterCard? character) {
    return character?.frontPorchExtensions?.actionColor ?? _globalActionColor;
  }

  /// Get effective chat font family (per-character overrides global)
  String getChatFontFamily(CharacterCard? character) {
    return character?.frontPorchExtensions?.chatFontFamily ?? _globalChatFontFamily;
  }

  // Expression Images settings
  bool _expressionEnabled = false;
  String _expressionClassificationMode = 'llm'; // 'llm', 'onnx', 'manual'
  String _expressionDisplayMode = 'sidebar'; // 'sidebar', 'background', 'both'
  bool _expressionRerollSame = false;
  String _expressionFallback = 'neutral'; // 'neutral', 'prime', 'none', 'emoji'

  bool get expressionEnabled => _expressionEnabled;
  String get expressionClassificationMode => _expressionClassificationMode;
  String get expressionDisplayMode => _expressionDisplayMode;
  bool get expressionRerollSame => _expressionRerollSame;
  String get expressionFallback => _expressionFallback;

  Future<void> setExpressionEnabled(bool value) async {
    _expressionEnabled = value;
    await _prefs?.setBool(_k('expression_enabled'), value);
    notifyListeners();
  }

  Future<void> setExpressionClassificationMode(String value) async {
    _expressionClassificationMode = value;
    await _prefs?.setString(_k('expression_classification_mode'), value);
    notifyListeners();
  }

  Future<void> setExpressionDisplayMode(String value) async {
    _expressionDisplayMode = value;
    await _prefs?.setString(_k('expression_display_mode'), value);
    notifyListeners();
  }

  Future<void> setExpressionRerollSame(bool value) async {
    _expressionRerollSame = value;
    await _prefs?.setBool(_k('expression_reroll_same'), value);
    notifyListeners();
  }

  Future<void> setExpressionFallback(String value) async {
    _expressionFallback = value;
    await _prefs?.setString(_k('expression_fallback'), value);
    notifyListeners();
  }
}
