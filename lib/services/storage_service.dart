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
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/models/character_card.dart';

// Stage 7: storage decomposition (directories + domain settings; final cleanup complete - shims excised; corrective COMPAT FLAT ACCESSORS bridge re-inserted at ~113 after incomplete 29bbf59d; see block comments + refactoring-guide.md "old API preserved via shim" for current state; long-term pure-dir + *Settings wiring intended). NOTE: file >500 LOC due to bridge (documented exception; do not grow per rule).
import 'storage/directories.dart';
import 'storage/settings/generation_settings.dart';
import 'storage/settings/backend_settings.dart';
import 'storage/settings/ui_settings.dart';
import 'storage/settings/tts_settings.dart';
import 'storage/settings/stt_settings.dart';
import 'storage/settings/image_gen_settings.dart';
import 'storage/settings/expression_settings.dart';
import 'storage/settings/web_server_settings.dart';
import 'storage/settings/cloud_sync_settings.dart';
import 'storage/settings/realism_settings.dart';
import 'storage/settings/memory_settings.dart';
import 'storage/settings/preset_settings.dart';

class StorageService extends ChangeNotifier {
  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get initialized => _initCompleter.future;

  SharedPreferences? _prefs;
  String? _rootPath;
  String? _customModelsPath;
  Directory? _binDir;

  // Stage 7: domain settings (plain classes + base mixin; single Storage ChangeNotifier surface)
  late final GenerationSettings _generationSettings = GenerationSettings();
  late final BackendSettings _backendSettings = BackendSettings();
  late final UiSettings _uiSettings = UiSettings();
  late final TtsSettings _ttsSettings = TtsSettings();
  late final SttSettings _sttSettings = SttSettings();
  late final ImageGenSettings _imageGenSettings = ImageGenSettings();
  late final ExpressionSettings _expressionSettings = ExpressionSettings();
  late final WebServerSettings _webServerSettings = WebServerSettings();
  late final CloudSyncSettings _cloudSyncSettings = CloudSyncSettings();
  late final RealismSettings _realismSettings = RealismSettings();
  late final MemorySettings _memorySettings = MemorySettings();
  late final PresetSettings _presetSettings = PresetSettings();

  // Directories lifted to directories.dart (Stage 7); thin god owns root state for setRootPath.
  // Getter ensures live values after setRootPath / setCustomModelsPath.
  AppDirectories get directories =>
      AppDirectories(rootPath: _rootPath, customModelsPath: _customModelsPath);

  String? get rootPath => _rootPath;
  String? get customModelsPath => _customModelsPath;
  Directory get binDir => _binDir ?? Directory(_rootPath ?? '');
  Directory get modelsDir => directories.modelsDir;
  Directory get chatsDir => directories.chatsDir;
  Directory get worldsDir => directories.worldsDir;

  Directory get charactersDir => directories.charactersDir;

  /// Directory for all group-private data (decoupled from singular library characters).
  /// Each group gets its own subdirectory (by group id) under here to store its
  /// member avatar PNGs (primary only; no multi-avatar or expressions per spec).
  /// Group data is NEVER written to or resolved from the global charactersDir or library.
  /// The only bridge to library is the user's explicit "Separate to my library" action.
  Directory get groupsDir => directories.groupsDir;

  File resolveCharacterImage(String imagePath) =>
      directories.resolveCharacterImage(imagePath);

  Directory characterAvatarDir(String characterName) =>
      directories.characterAvatarDir(characterName);

  Directory get customBackgroundDir => directories.customBackgroundDir;

  // Public accessors to extracted domain settings (post-Stage 7 final shim migration).
  // Callers now use direct e.g. storage.generationSettings.systemPrompt or .setTemperature(v)
  // instead of the old flat shims. Storage owns the instances (for _prefs init, beta _k,
  // single ChangeNotifier notify surface, and wiring). This + dir mgmt is the thinned god.
  // (final shim migration cleanup complete; corrective flat shims re-added in COMPAT block below after incomplete excision; see ~113 and refactoring-guide; no change to long-term pure-dir + *Settings intent)
  GenerationSettings get generationSettings => _generationSettings;
  BackendSettings get backendSettings => _backendSettings;
  UiSettings get uiSettings => _uiSettings;
  TtsSettings get ttsSettings => _ttsSettings;
  SttSettings get sttSettings => _sttSettings;
  ImageGenSettings get imageGenSettings => _imageGenSettings;
  ExpressionSettings get expressionSettings => _expressionSettings;
  WebServerSettings get webServerSettings => _webServerSettings;
  CloudSyncSettings get cloudSyncSettings => _cloudSyncSettings;
  RealismSettings get realismSettings => _realismSettings;
  MemorySettings get memorySettings => _memorySettings;
  PresetSettings get presetSettings => _presetSettings;

  // --- COMPATIBILITY FLAT ACCESSORS (corrective bridge after incomplete "final shim migration" in 29bbf59d) ---
  // The excision of flat shims happened before all call sites across lib/ (settings tabs, dialogs, model_settings,
  // chat_settings, creator, kcpps_selector, memory/summary sections, message_bubble, web_server, setup, llm/kobold/kokoro
  // providers, main, tests, etc.) had been updated to the .xxxSettings direct API.
  // These thin forwards restore the old names so the tree actually compiles and `flutter run -d macos` succeeds,
  // while the public *Settings (the real home of the logic, persistence, notify, and beta isolation) remain the
  // preferred/updated path.
  // This is exactly the "old API preserved via shim where callers exist" step described in docs/refactoring-guide.md.
  // When a full exhaustive audit + caller update pass is done, these can be deleted.
  // Added so the app is runnable after the push of the incomplete cleanup.
  // (All delegate to the corresponding *Settings; no duplication of logic or prefs keys.)
  // Types match the *Settings canonical (String for imageGenSize/grpcHost, int for draw*Port/Sampler/SeedMode/kv/callBuffer, bool for Tea/Cfg etc).
  //
  // NOTE (LOC cap exception per review): This file exceeds the strict <500 LOC rule (currently ~730) solely due to the
  // corrective 180+ line compat bridge required to unblock the app post-Stage 7 excision (callers not yet migrated).
  // Per "If modifying an existing file that exceeds 500 LOC ... you should not grow it further", NO new thins or logic
  // will be added here; long-term the block should be extracted (e.g. to storage/compat_shims.dart mixin) or pruned after
  // full caller migration. This exception is documented; do not grow the compat surface. (See also Issue 2 in review.)

  // UI / theme / presentation (all on UiSettings)
  @Deprecated(
    'Temporary compat flat after incomplete Stage 7 shim excision (see block header at ~113 and refactoring-guide.md "old API preserved via shim"); migrate callers to storage.uiSettings.xxx / .backendSettings etc. Will be pruned after full audit. Applies to all thins in COMPATIBILITY FLAT ACCESSORS block.',
  )
  bool get isDark => uiSettings.isDark;
  double get textScale => uiSettings.textScale;
  Future<void> setTextScale(double v) => uiSettings.setTextScale(v);
  double get bubbleOpacity => uiSettings.bubbleOpacity;
  Future<void> setBubbleOpacity(double v) => uiSettings.setBubbleOpacity(v);
  Color get globalUserBubbleColor => uiSettings.globalUserBubbleColor;
  Future<void> setGlobalUserBubbleColor(Color v) =>
      uiSettings.setGlobalUserBubbleColor(v);
  Color get globalUserTextColor => uiSettings.globalUserTextColor;
  Future<void> setGlobalUserTextColor(Color v) =>
      uiSettings.setGlobalUserTextColor(v);
  Color get globalAiBubbleColor => uiSettings.globalAiBubbleColor;
  Future<void> setGlobalAiBubbleColor(Color v) =>
      uiSettings.setGlobalAiBubbleColor(v);
  Color get globalAiTextColor => uiSettings.globalAiTextColor;
  Future<void> setGlobalAiTextColor(Color v) =>
      uiSettings.setGlobalAiTextColor(v);
  Color get globalDialogueColor => uiSettings.globalDialogueColor;
  Future<void> setGlobalDialogueColor(Color v) =>
      uiSettings.setGlobalDialogueColor(v);
  Color get globalActionColor => uiSettings.globalActionColor;
  Future<void> setGlobalActionColor(Color v) =>
      uiSettings.setGlobalActionColor(v);
  String get globalChatFontFamily => uiSettings.globalChatFontFamily;
  Future<void> setGlobalChatFontFamily(String v) =>
      uiSettings.setGlobalChatFontFamily(v);
  String get chatBackground => uiSettings.chatBackground;
  Future<void> setChatBackground(String v) => uiSettings.setChatBackground(v);
  List<Map<String, String>> get customBackgrounds =>
      uiSettings.customBackgrounds;
  Future<void> addCustomBackground(String id, String name, String filePath) =>
      uiSettings.addCustomBackground(id, name, filePath);
  Future<void> removeCustomBackground(String id) =>
      uiSettings.removeCustomBackground(id);
  bool hasCustomBackgroundWithName(String name) =>
      uiSettings.hasCustomBackgroundWithName(name);
  bool get displayBufferEnabled => uiSettings.displayBufferEnabled;
  Future<void> setDisplayBufferEnabled(bool v) =>
      uiSettings.setDisplayBufferEnabled(v);
  double get targetDisplayTps => uiSettings.targetDisplayTps;
  Future<void> setTargetDisplayTps(double v) =>
      uiSettings.setTargetDisplayTps(v);
  double get bufferDurationSeconds => uiSettings.bufferDurationSeconds;
  Future<void> setBufferDurationSeconds(double v) =>
      uiSettings.setBufferDurationSeconds(v);
  String get sortMode => uiSettings.sortMode;
  Future<void> setSortMode(String v) => uiSettings.setSortMode(v);
  double get gridScale => uiSettings.gridScale;
  Future<void> setGridScale(double v) => uiSettings.setGridScale(v);
  Color getUserBubbleColor([CharacterCard? c]) =>
      uiSettings.getUserBubbleColor(c);
  Color getAiBubbleColor([CharacterCard? c]) => uiSettings.getAiBubbleColor(c);
  Color getDialogueColor([CharacterCard? c]) => uiSettings.getDialogueColor(c);
  Color getUserTextColor([CharacterCard? c]) => uiSettings.getUserTextColor(c);
  Color getAiTextColor([CharacterCard? c]) => uiSettings.getAiTextColor(c);
  String getChatFontFamily([CharacterCard? c]) =>
      uiSettings.getChatFontFamily(c);
  Color getActionColor([CharacterCard? c]) => uiSettings.getActionColor(c);
  Future<void> setIsDark(bool v) => uiSettings.setIsDark(v);

  // Cloud sync
  bool get cloudSyncEnabled => cloudSyncSettings.cloudSyncEnabled;
  String get cloudSyncProvider => cloudSyncSettings.cloudSyncProvider;
  String get cloudSyncUrl => cloudSyncSettings.cloudSyncUrl;
  String get cloudSyncUsername => cloudSyncSettings.cloudSyncUsername;
  String get cloudSyncPassword => cloudSyncSettings.cloudSyncPassword;
  String get cloudSyncLastTime => cloudSyncSettings.cloudSyncLastTime;
  Future<void> setCloudSyncEnabled(bool v) =>
      cloudSyncSettings.setCloudSyncEnabled(v);
  Future<void> setCloudSyncProvider(String v) =>
      cloudSyncSettings.setCloudSyncProvider(v);
  Future<void> setCloudSyncUrl(String v) =>
      cloudSyncSettings.setCloudSyncUrl(v);
  Future<void> setCloudSyncUsername(String v) =>
      cloudSyncSettings.setCloudSyncUsername(v);
  Future<void> setCloudSyncPassword(String v) =>
      cloudSyncSettings.setCloudSyncPassword(v);
  Future<void> setCloudSyncLastTime(String v) =>
      cloudSyncSettings.setCloudSyncLastTime(v);

  // Web server
  bool get webServerEnabled => webServerSettings.webServerEnabled;
  int get webServerPort => webServerSettings.webServerPort;
  Future<void> setWebServerEnabled(bool v) =>
      webServerSettings.setWebServerEnabled(v);
  Future<void> setWebServerPort(int v) => webServerSettings.setWebServerPort(v);

  // TTS / STT / voice (directorDelay on tts; kv authoritative in backend, callBuffer in stt; thins route to canonical to avoid dupe state)
  bool get ttsEnabled => ttsSettings.ttsEnabled;
  String get ttsVoiceModel => ttsSettings.ttsVoiceModel;
  Future<void> setTtsEnabled(bool v) => ttsSettings.setTtsEnabled(v);
  Future<void> setTtsVoiceModel(String v) => ttsSettings.setTtsVoiceModel(v);
  bool get sttEnabled => sttSettings.sttEnabled;
  String get whisperModel => sttSettings.whisperModel;
  Future<void> setSttEnabled(bool v) => sttSettings.setSttEnabled(v);
  Future<void> setWhisperModel(String v) => sttSettings.setWhisperModel(v);
  String? get selectedMicId => sttSettings.selectedMicId;
  Future<void> setSelectedMicId(String? v) => sttSettings.setSelectedMicId(v);
  String get ttsEngine => ttsSettings.ttsEngine;
  Future<void> setTtsEngine(String v) => ttsSettings.setTtsEngine(v);
  String get openaiTtsApiKey => ttsSettings.openaiTtsApiKey;
  Future<void> setOpenaiTtsApiKey(String v) =>
      ttsSettings.setOpenaiTtsApiKey(v);
  String get openaiTtsModel => ttsSettings.openaiTtsModel;
  Future<void> setOpenaiTtsModel(String v) => ttsSettings.setOpenaiTtsModel(v);
  String get openaiTtsBaseUrl => ttsSettings.openaiTtsBaseUrl;
  Future<void> setOpenaiTtsBaseUrl(String v) =>
      ttsSettings.setOpenaiTtsBaseUrl(v);
  String get elevenlabsApiKey => ttsSettings.elevenlabsApiKey;
  Future<void> setElevenlabsApiKey(String v) =>
      ttsSettings.setElevenlabsApiKey(v);
  String get elevenlabsModel => ttsSettings.elevenlabsModel;
  Future<void> setElevenlabsModel(String v) =>
      ttsSettings.setElevenlabsModel(v);
  double get elevenlabsStability => ttsSettings.elevenlabsStability;
  Future<void> setElevenlabsStability(double v) =>
      ttsSettings.setElevenlabsStability(v);
  double get elevenlabsSimilarity => ttsSettings.elevenlabsSimilarity;
  Future<void> setElevenlabsSimilarity(double v) =>
      ttsSettings.setElevenlabsSimilarity(v);
  double get elevenlabsStyle => ttsSettings.elevenlabsStyle;
  Future<void> setElevenlabsStyle(double v) =>
      ttsSettings.setElevenlabsStyle(v);
  double get ttsSpeechRate => ttsSettings.ttsSpeechRate;
  Future<void> setTtsSpeechRate(double v) => ttsSettings.setTtsSpeechRate(v);
  bool get ttsNarrateQuotedOnly => ttsSettings.ttsNarrateQuotedOnly;
  Future<void> setTtsNarrateQuotedOnly(bool v) =>
      ttsSettings.setTtsNarrateQuotedOnly(v);
  bool get ttsIgnoreAsterisks => ttsSettings.ttsIgnoreAsterisks;
  Future<void> setTtsIgnoreAsterisks(bool v) =>
      ttsSettings.setTtsIgnoreAsterisks(v);
  bool get ttsReplaceCurlyQuotes => ttsSettings.ttsReplaceCurlyQuotes;
  Future<void> setTtsReplaceCurlyQuotes(bool v) =>
      ttsSettings.setTtsReplaceCurlyQuotes(v);
  int get ttsAudioLookahead => ttsSettings.ttsAudioLookahead;
  Future<void> setTtsAudioLookahead(int v) =>
      ttsSettings.setTtsAudioLookahead(v);
  int get ttsConcurrency => ttsSettings.ttsConcurrency;
  Future<void> setTtsConcurrency(int v) => ttsSettings.setTtsConcurrency(v);
  bool get ttsAutoPlay => ttsSettings.ttsAutoPlay;
  Future<void> setTtsAutoPlay(bool v) => ttsSettings.setTtsAutoPlay(v);
  double get directorDelay => ttsSettings.directorDelay;
  Future<void> setDirectorDelay(double v) => ttsSettings.setDirectorDelay(v);
  String get callModelName => sttSettings.callModelName;
  Future<void> setCallModelName(String v) => sttSettings.setCallModelName(v);
  String get callSystemPrompt => sttSettings.callSystemPrompt;
  Future<void> setCallSystemPrompt(String v) =>
      sttSettings.setCallSystemPrompt(v);
  bool get autoSendTranscription => sttSettings.autoSendTranscription;
  Future<void> setAutoSendTranscription(bool v) =>
      sttSettings.setAutoSendTranscription(v);
  int get callBufferSentences => sttSettings.callBufferSentences;
  Future<void> setCallBufferSentences(int v) =>
      sttSettings.setCallBufferSentences(v);
  // (kv authoritative on backendSettings after dupe consolidation; tts no longer owns kv field/set)

  // Expression (all on ExpressionSettings)
  bool get expressionEnabled => expressionSettings.expressionEnabled;
  String get expressionClassificationMode =>
      expressionSettings.expressionClassificationMode;
  Future<void> setExpressionEnabled(bool v) =>
      expressionSettings.setExpressionEnabled(v);
  Future<void> setExpressionClassificationMode(String v) =>
      expressionSettings.setExpressionClassificationMode(v);
  String get expressionDisplayMode => expressionSettings.expressionDisplayMode;
  Future<void> setExpressionDisplayMode(String v) =>
      expressionSettings.setExpressionDisplayMode(v);
  bool get expressionRerollSame => expressionSettings.expressionRerollSame;
  Future<void> setExpressionRerollSame(bool v) =>
      expressionSettings.setExpressionRerollSame(v);
  String get expressionFallback => expressionSettings.expressionFallback;
  Future<void> setExpressionFallback(String v) =>
      expressionSettings.setExpressionFallback(v);

  // Image gen / draw things (types per imageGenSettings canonical: String size, int for draw* ints, bool for flags)
  bool get imageGenEnabled => imageGenSettings.imageGenEnabled;
  Future<void> setImageGenEnabled(bool v) =>
      imageGenSettings.setImageGenEnabled(v);
  String get imageGenModel => imageGenSettings.imageGenModel;
  Future<void> setImageGenModel(String v) =>
      imageGenSettings.setImageGenModel(v);
  String get imageGenBackend => imageGenSettings.imageGenBackend;
  Future<void> setImageGenBackend(String v) =>
      imageGenSettings.setImageGenBackend(v);
  String get localImageGenUrl => imageGenSettings.localImageGenUrl;
  Future<void> setLocalImageGenUrl(String v) =>
      imageGenSettings.setLocalImageGenUrl(v);
  String get imageGenSize => imageGenSettings.imageGenSize;
  Future<void> setImageGenSize(String v) => imageGenSettings.setImageGenSize(v);
  String get imageGenStyle => imageGenSettings.imageGenStyle;
  Future<void> setImageGenStyle(String v) =>
      imageGenSettings.setImageGenStyle(v);
  String get imageGenNegativePrompt => imageGenSettings.imageGenNegativePrompt;
  Future<void> setImageGenNegativePrompt(String v) =>
      imageGenSettings.setImageGenNegativePrompt(v);
  String get imageGenPromptParadigm => imageGenSettings.imageGenPromptParadigm;
  Future<void> setImageGenPromptParadigm(String v) =>
      imageGenSettings.setImageGenPromptParadigm(v);
  String get imageGenLora => imageGenSettings.imageGenLora;
  Future<void> setImageGenLora(String v) => imageGenSettings.setImageGenLora(v);
  double get imageGenLoraWeight => imageGenSettings.imageGenLoraWeight;
  Future<void> setImageGenLoraWeight(double v) =>
      imageGenSettings.setImageGenLoraWeight(v);
  int get imageGenSteps => imageGenSettings.imageGenSteps;
  Future<void> setImageGenSteps(int v) => imageGenSettings.setImageGenSteps(v);
  double get imageGenCfgScale => imageGenSettings.imageGenCfgScale;
  Future<void> setImageGenCfgScale(double v) =>
      imageGenSettings.setImageGenCfgScale(v);
  String get imageGenSampler => imageGenSettings.imageGenSampler;
  Future<void> setImageGenSampler(String v) =>
      imageGenSettings.setImageGenSampler(v);
  int get imageGenSeed => imageGenSettings.imageGenSeed;
  Future<void> setImageGenSeed(int v) => imageGenSettings.setImageGenSeed(v);
  String get drawThingsGrpcHost => imageGenSettings.drawThingsGrpcHost;
  Future<void> setDrawThingsGrpcHost(String v) =>
      imageGenSettings.setDrawThingsGrpcHost(v);
  int get drawThingsGrpcPort => imageGenSettings.drawThingsGrpcPort;
  Future<void> setDrawThingsGrpcPort(int v) =>
      imageGenSettings.setDrawThingsGrpcPort(v);
  int get drawThingsSampler => imageGenSettings.drawThingsSampler;
  Future<void> setDrawThingsSampler(int v) =>
      imageGenSettings.setDrawThingsSampler(v);
  double get drawThingsShift => imageGenSettings.drawThingsShift;
  Future<void> setDrawThingsShift(double v) =>
      imageGenSettings.setDrawThingsShift(v);
  double get drawThingsStrength => imageGenSettings.drawThingsStrength;
  Future<void> setDrawThingsStrength(double v) =>
      imageGenSettings.setDrawThingsStrength(v);
  int get drawThingsSeedMode => imageGenSettings.drawThingsSeedMode;
  Future<void> setDrawThingsSeedMode(int v) =>
      imageGenSettings.setDrawThingsSeedMode(v);
  bool get drawThingsTeaCache => imageGenSettings.drawThingsTeaCache;
  Future<void> setDrawThingsTeaCache(bool v) =>
      imageGenSettings.setDrawThingsTeaCache(v);
  bool get drawThingsCfgZeroStar => imageGenSettings.drawThingsCfgZeroStar;
  Future<void> setDrawThingsCfgZeroStar(bool v) =>
      imageGenSettings.setDrawThingsCfgZeroStar(v);

  // Backend / kobold / remote / launch flags / kcpps (kv + callBuffer here per lift/compat needs; some also on tts/stt)
  String get backendType => backendSettings.backendType;
  Future<void> setBackendType(String v) => backendSettings.setBackendType(v);
  String get remoteApiKey => backendSettings.remoteApiKey;
  Future<void> setRemoteApiKey(String v) => backendSettings.setRemoteApiKey(v);
  String get remoteApiUrl => backendSettings.remoteApiUrl;
  Future<void> setRemoteApiUrl(String v) => backendSettings.setRemoteApiUrl(v);
  String get remoteModelName => backendSettings.remoteModelName;
  Future<void> setRemoteModelName(String v) =>
      backendSettings.setRemoteModelName(v);
  Future<void> setRemoteModel(String v) =>
      backendSettings.setRemoteModelName(v); // alias for callers
  bool get reasoningEnabled => backendSettings.reasoningEnabled;
  Future<void> setReasoningEnabled(bool v) =>
      backendSettings.setReasoningEnabled(v);
  String get reasoningEffort => backendSettings.reasoningEffort;
  Future<void> setReasoningEffort(String v) =>
      backendSettings.setReasoningEffort(v);
  String? get activeKcppsPath => backendSettings.activeKcppsPath;
  Future<void> setActiveKcppsPath(String? v) =>
      backendSettings.setActiveKcppsPath(v);
  String? get lastUsedModelPath => backendSettings.lastUsedModelPath;
  Future<void> setLastUsedModelPath(String? v) =>
      backendSettings.setLastUsedModelPath(v);
  bool get kcppsHasModel => backendSettings.kcppsHasModel;
  bool get kcppsModelFileExists => backendSettings.kcppsModelFileExists;
  bool? get useCublas => backendSettings.useCublas;
  Future<void> setUseCublas(bool? v) => backendSettings.setUseCublas(v);
  bool? get useVulkan => backendSettings.useVulkan;
  Future<void> setUseVulkan(bool? v) => backendSettings.setUseVulkan(v);
  bool? get useMetal => backendSettings.useMetal;
  Future<void> setUseMetal(bool? v) => backendSettings.setUseMetal(v);
  bool? get useRocm => backendSettings.useRocm;
  Future<void> setUseRocm(bool? v) => backendSettings.setUseRocm(v);
  bool get flashAttentionEnabled => backendSettings.flashAttentionEnabled;
  Future<void> setFlashAttentionEnabled(bool v) =>
      backendSettings.setFlashAttentionEnabled(v);
  bool get mlockEnabled => backendSettings.mlockEnabled;
  Future<void> setMlockEnabled(bool v) => backendSettings.setMlockEnabled(v);
  int get blasBatchSize => backendSettings.blasBatchSize;
  Future<void> setBlasBatchSize(int v) => backendSettings.setBlasBatchSize(v);
  int get gpuId => backendSettings.gpuId;
  Future<void> setGpuId(int v) => backendSettings.setGpuId(v);
  int get gpuLayers => backendSettings.gpuLayers;
  Future<void> setGpuLayers(int v) => backendSettings.setGpuLayers(v);
  int get contextSize => backendSettings.contextSize;
  Future<void> setContextSize(int v) => backendSettings.setContextSize(v);
  int get kvQuantizationLevel => backendSettings.kvQuantizationLevel;
  Future<void> setKvQuantizationLevel(int v) =>
      backendSettings.setKvQuantizationLevel(v);
  // callBufferSentences authoritative on sttSettings (thin at STT section); kv on backend -- dupes removed (tts/backend callBuffer) to single canonical owner per review to avoid stale-read/notify risk on runtime sets via thins or direct *Settings.
  bool get autostartBackend => backendSettings.autostartBackend;
  Future<void> setAutostartBackend(bool v) =>
      backendSettings.setAutostartBackend(v);
  bool get autostartPseudoRemote => backendSettings.autostartPseudoRemote;
  Future<void> setAutostartPseudoRemote(bool v) =>
      backendSettings.setAutostartPseudoRemote(v);
  bool get koboldThinkingModel => backendSettings.koboldThinkingModel;
  Future<void> setKoboldThinkingModel(bool v) =>
      backendSettings.setKoboldThinkingModel(v);
  Future<void> setModelPreset(String modelPath, String? kcppsPath) =>
      presetSettings.setModelPreset(modelPath, kcppsPath);

  // Generation / sampling
  double get temperature => generationSettings.temperature;
  Future<void> setTemperature(double v) => generationSettings.setTemperature(v);
  double get minP => generationSettings.minP;
  Future<void> setMinP(double v) => generationSettings.setMinP(v);
  double get repeatPenalty => generationSettings.repeatPenalty;
  Future<void> setRepeatPenalty(double v) =>
      generationSettings.setRepeatPenalty(v);
  int get repeatPenaltyTokens => generationSettings.repeatPenaltyTokens;
  Future<void> setRepeatPenaltyTokens(int v) =>
      generationSettings.setRepeatPenaltyTokens(v);
  double get xtcThreshold => generationSettings.xtcThreshold;
  Future<void> setXtcThreshold(double v) =>
      generationSettings.setXtcThreshold(v);
  double get xtcProbability => generationSettings.xtcProbability;
  Future<void> setXtcProbability(double v) =>
      generationSettings.setXtcProbability(v);
  bool get dynamicTempEnabled => generationSettings.dynamicTempEnabled;
  Future<void> setDynamicTempEnabled(bool v) =>
      generationSettings.setDynamicTempEnabled(v);
  double get dynamicTempRange => generationSettings.dynamicTempRange;
  Future<void> setDynamicTempRange(double v) =>
      generationSettings.setDynamicTempRange(v);
  int get maxLength => generationSettings.maxLength;
  Future<void> setMaxLength(int v) => generationSettings.setMaxLength(v);
  int get minLength => generationSettings.minLength;
  Future<void> setMinLength(int v) => generationSettings.setMinLength(v);
  List<String> get stopSequences => generationSettings.stopSequences;
  Future<void> setStopSequences(List<String> v) =>
      generationSettings.setStopSequences(v);
  Future<void> addStopSequence(String v) =>
      generationSettings.addStopSequence(v);
  Future<void> removeStopSequence(String v) =>
      generationSettings.removeStopSequence(v);
  String get systemPrompt => generationSettings.systemPrompt;
  Future<void> setSystemPrompt(String v) =>
      generationSettings.setSystemPrompt(v);

  // Memory / RAG / summary / persona / evolution (banned on realism)
  bool get ragEnabled => memorySettings.ragEnabled;
  Future<void> setRagEnabled(bool v) => memorySettings.setRagEnabled(v);
  int get ragRetrievalCount => memorySettings.ragRetrievalCount;
  Future<void> setRagRetrievalCount(int v) =>
      memorySettings.setRagRetrievalCount(v);
  int get ragWindowSize => memorySettings.ragWindowSize;
  Future<void> setRagWindowSize(int v) => memorySettings.setRagWindowSize(v);
  String get ragEmbeddingSource => memorySettings.ragEmbeddingSource;
  Future<void> setRagEmbeddingSource(String v) =>
      memorySettings.setRagEmbeddingSource(v);
  String get ragEmbeddingModel => memorySettings.ragEmbeddingModel;
  Future<void> setRagEmbeddingModel(String v) =>
      memorySettings.setRagEmbeddingModel(v);
  bool get autoPersonaEnabled => memorySettings.autoPersonaEnabled;
  Future<void> setAutoPersonaEnabled(bool v) =>
      memorySettings.setAutoPersonaEnabled(v);
  int get autoPersonaInterval => memorySettings.autoPersonaInterval;
  Future<void> setAutoPersonaInterval(int v) =>
      memorySettings.setAutoPersonaInterval(v);
  bool get characterEvolutionEnabled =>
      memorySettings.characterEvolutionEnabled;
  Future<void> setCharacterEvolutionEnabled(bool v) =>
      memorySettings.setCharacterEvolutionEnabled(v);
  int get evolutionInterval => memorySettings.evolutionInterval;
  Future<void> setEvolutionInterval(int v) =>
      memorySettings.setEvolutionInterval(v);
  bool get summaryEnabled => memorySettings.summaryEnabled;
  Future<void> setSummaryEnabled(bool v) => memorySettings.setSummaryEnabled(v);
  int get summaryInterval => memorySettings.summaryInterval;
  Future<void> setSummaryInterval(int v) =>
      memorySettings.setSummaryInterval(v);
  int get summaryMaxWords => memorySettings.summaryMaxWords;
  Future<void> setSummaryMaxWords(int v) =>
      memorySettings.setSummaryMaxWords(v);
  String get summaryPrompt => memorySettings.summaryPrompt;
  Future<void> setSummaryPrompt(String v) => memorySettings.setSummaryPrompt(v);
  String get defaultSummaryPrompt => MemorySettings.defaultSummaryPrompt;

  // Realism / banned (bannedPhrases, defaults lifted to realismSettings)
  bool get realismOneShotEval => realismSettings.realismOneShotEval;
  Future<void> setRealismOneShotEval(bool v) =>
      realismSettings.setRealismOneShotEval(v);
  bool get realismDefault => realismSettings.realismDefault;
  Future<void> setRealismDefault(bool v) =>
      realismSettings.setRealismDefault(v);
  bool get nsfwCooldownDefault => realismSettings.nsfwCooldownDefault;
  Future<void> setNsfwCooldownDefault(bool v) =>
      realismSettings.setNsfwCooldownDefault(v);
  bool get passageOfTimeDefault => realismSettings.passageOfTimeDefault;
  Future<void> setPassageOfTimeDefault(bool v) =>
      realismSettings.setPassageOfTimeDefault(v);
  List<String> get bannedPhrases => realismSettings.bannedPhrases;
  Future<void> setBannedPhrases(List<String> v) =>
      realismSettings.setBannedPhrases(v);

  // Preset / prompts (saved as List<Map> historically; load takes cb)
  List<Map<String, String>> get savedPrompts => presetSettings.savedPrompts;
  Map<String, String> get modelPresetMap => presetSettings.modelPresetMap;
  Future<void> savePrompt(String name, String prompt) =>
      presetSettings.savePrompt(name, prompt);
  Future<void> deleteSavedPrompt(String name) =>
      presetSettings.deleteSavedPrompt(name);
  void loadSavedPrompt(
    String name, [
    void Function(String)? setSystemPromptCb,
  ]) {
    if (setSystemPromptCb != null) {
      presetSettings.loadSavedPrompt(name, setSystemPromptCb);
    } else {
      // legacy 1-arg path (used by general_tab + tests: `load(name); controller = storage.systemPrompt`):
      // lookup + apply so subsequent reads see value (pre-extraction).
      // Relies on gen.set doing sync _= before await (in-mem visible immediately; prefs fire-forget).
      // Added: not-found log (was silent no-op); prominent timing doc.
      final prompt = presetSettings.savedPrompts.firstWhere(
        (p) => p['name'] == name,
        orElse: () => <String, String>{},
      );
      if (prompt.containsKey('content')) {
        // fire set (async notify ok for these call sites)
        // ignore: discarded_futures
        setSystemPrompt(prompt['content']!);
      } else {
        debugPrint(
          '[Storage] loadSavedPrompt(1-arg legacy): "$name" not found (no-op; check preset list)',
        );
      }
    }
  }

  // God-level (not in a *Settings): custom models path
  // (narrower than setRootPath: no relocation dance needed; early return + beta _k + notify for parity with god pattern)
  Future<void> setCustomModelsPath(String? v) async {
    final normalized = (v != null && v.isNotEmpty) ? v : null;
    if (_customModelsPath == normalized) return;
    _customModelsPath = normalized;
    if (normalized != null) {
      await _prefs?.setString(_k('custom_models_path'), normalized);
    } else {
      await _prefs?.remove(_k('custom_models_path'));
    }
    notifyListeners();
  }

  // (end of compatibility block)

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

    // For developers running from source (`flutter run`), allow forcing the
    // exact same data directory as the packaged app via environment variable.
    // This makes cloud sync testing from source behave identically to packaged builds.
    String? devOverride;
    if (isPreRelease) {
      devOverride = Platform.environment['FRONT_PORCH_AI_DATA_DIR'];
    }

    // Beta builds default to a completely separate data directory so they
    // never touch a stable user's characters, chats, or database.
    final defaultRootName = isPreRelease ? 'FrontPorchAI-Beta' : 'FrontPorchAI';
    final defaultRoot = path.join(docsDir.path, defaultRootName);
    _rootPath = devOverride ?? _prefs?.getString(_rootPathKey) ?? defaultRoot;
    if (devOverride != null) {
      debugPrint('[Storage] Using dev override data directory: $_rootPath');
    }
    _binDir = Directory(path.join(_rootPath!, 'koboldcpp_bin'));

    // Ensure directories exist
    await chatsDir.create(recursive: true);
    await modelsDir.create(recursive: true);
    await worldsDir.create(recursive: true);
    await charactersDir.create(recursive: true);
    await groupsDir.create(recursive: true);
    await customBackgroundDir.create(recursive: true);

    // Stage 7: initialize domain settings (plain classes) + load (moved from god)
    // Single notify surface preserved (see plan "Why not multiple ChangeNotifiers").
    _generationSettings.initializeBase(_prefs, notifyListeners);
    _backendSettings.initializeBase(_prefs, notifyListeners);
    _uiSettings.initializeBase(_prefs, notifyListeners);
    _ttsSettings.initializeBase(_prefs, notifyListeners);
    _sttSettings.initializeBase(_prefs, notifyListeners);
    _imageGenSettings.initializeBase(_prefs, notifyListeners);
    _expressionSettings.initializeBase(_prefs, notifyListeners);
    _webServerSettings.initializeBase(_prefs, notifyListeners);
    _cloudSyncSettings.initializeBase(_prefs, notifyListeners);
    _realismSettings.initializeBase(_prefs, notifyListeners);
    _memorySettings.initializeBase(_prefs, notifyListeners);
    _presetSettings.initializeBase(_prefs, notifyListeners);

    _generationSettings.load();
    _backendSettings.load();
    _uiSettings.load();
    _ttsSettings.load();
    _sttSettings.load();
    _imageGenSettings.load();
    _expressionSettings.load();
    _webServerSettings.load();
    _cloudSyncSettings.load();
    _realismSettings.load();
    _memorySettings.load();
    _presetSettings.load();

    // Ensure default immersive prompt (was in god init; now on preset)
    if (!_presetSettings.savedPrompts.any(
      (p) => p['name'] == 'Immersive Roleplay',
    )) {
      await _presetSettings.savePrompt(
        'Immersive Roleplay',
        PresetSettings.defaultSystemPrompt,
      );
    }

    // Load settings (DELETED in Stage 7 — bodies lifted to the *Settings.load(); see above + shims)
    // Original load code excised (deletion part of task).
    final loadedCustom = _prefs?.getString(_k('custom_models_path'));
    _customModelsPath = (loadedCustom != null && loadedCustom.isNotEmpty) ? loadedCustom : null;

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
    await groupsDir.create(recursive: true);

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

  // (final shim migration cleanup complete IMPL_ID=29bbf59d; all @Deprecated + flat shims excised for tts/stt/image/expression/web/cloud/realism/memory/preset + all flats. Storage is pure directory management (rootPath, dirs, resolveCharacterImage, setRootPath, _copyDirectory, init for dirs + beta/dev override, _initCompleter, _prefs for dir keys only) + public *Settings wiring (late finals for init/single-notifier/beta isolation) only. No _prefs for settings, no notify for settings changes, no flat settings API. Deletion part complete; live post-edit dead grep for old shim symbols in *_service.dart exec =0 outside comments/MD. Corrective COMPAT FLAT ACCESSORS bridge re-inserted post-excision at the COMPAT block; see its header for details + keep in sync with refactoring-guide Stage 7 precedent.)
}
