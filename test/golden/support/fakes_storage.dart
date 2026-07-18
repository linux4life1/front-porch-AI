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

// Fake StorageService for widget-golden tests.
//
// Implements only the getters that widget build trees actually read at build
// time (not those accessed only in event handlers). Everything else delegates
// to noSuchMethod so the fake stays small and future getters don't break here
// silently — instead they'll surface as NoSuchMethodError and remind the
// author to add them here.
//
// Surface covered (build-time reads audited against each consumer page/dialog):
//   BackgroundSettingsDialog: chatBackground, customBackgrounds
//   UiSettingsDialog:        bubbleOpacity, textScale, globalUserBubbleColor,
//                            globalUserTextColor, globalAiBubbleColor,
//                            globalAiTextColor, globalDialogueColor, globalActionColor
//   ChatSettingsDialog:      remoteApiKey, bannedPhrases, remoteModelName,
//                            activeKcppsPath
//   ModelSettingsDialog:     useCublas, useVulkan, useMetal, useRocm,
//                            lastUsedModelPath, gpuLayers, contextSize,
//                            remoteApiUrl, remoteApiKey, remoteModelName,
//                            binDir, activeKcppsPath
//   ModelManagerPage:        customModelsPath

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Minimal [StorageService] double. Implements only the getters that widget
/// build trees read at build time. All setter calls and unimplemented getters
/// fall through to [noSuchMethod].
class FakeStorageService extends ChangeNotifier implements StorageService {
  // Paths / directories
  @override
  String? get rootPath => null;
  @override
  Directory get chatsDir => Directory.systemTemp;
  @override
  Directory get binDir => Directory.systemTemp;
  @override
  String? get customModelsPath => null;

  // Chat background
  @override
  String get chatBackground => 'none';
  @override
  List<Map<String, String>> get customBackgrounds => const [];

  // UI / display
  @override
  double get bubbleOpacity => 0.95;
  @override
  double get textScale => 1.0;
  @override
  Color get globalUserBubbleColor => Colors.blueAccent;
  @override
  Color get globalUserTextColor => Colors.white;
  @override
  Color get globalAiBubbleColor => const Color(0xFF1E293B);
  @override
  Color get globalAiTextColor => Colors.white;
  @override
  Color get globalDialogueColor => Colors.deepPurpleAccent;
  @override
  Color get globalActionColor => Colors.orangeAccent;

  // API / backend
  @override
  String get remoteApiKey => '';
  @override
  String get remoteApiUrl => '';
  @override
  String get remoteModelName => '';
  @override
  String? get activeKcppsPath => null;
  @override
  String? get lastUsedModelPath => null;

  // Structured settings objects — ChatSettingsDialog.build() calls
  // _gen.resolveX(storage) helpers which delegate to these objects for their
  // fallback values (e.g. resolveTemperature → generationSettings.temperature,
  // resolveContextSize → backendSettings.contextSize).
  @override
  GenerationSettings get generationSettings => GenerationSettings();
  @override
  BackendSettings get backendSettings => BackendSettings();

  // Generation options (legacy flat getters, kept for ModelSettingsDialog etc.)
  @override
  List<String> get bannedPhrases => const [];
  @override
  int get gpuLayers => 0;
  @override
  int get contextSize => 8192;

  // GPU flags (nullable bools)
  @override
  bool? get useCublas => null;
  @override
  bool? get useVulkan => null;
  @override
  bool? get useMetal => null;
  @override
  bool? get useRocm => null;

  // TTS settings — TtsSettingsDialog reads these unconditionally in build()
  // via Consumer2<StorageService, TtsService>. Engine-specific sections are
  // gated on engineId; using 'disabled' keeps all engine branches hidden.
  @override
  String get ttsEngine => 'disabled';
  @override
  bool get ttsEnabled => false;
  @override
  double get ttsSpeechRate => 1.0;
  @override
  int get ttsConcurrency => 1;
  @override
  bool get ttsAutoPlay => false;
  @override
  bool get ttsNarrateQuotedOnly => false;
  @override
  bool get ttsIgnoreAsterisks => false;
  @override
  bool get ttsReplaceCurlyQuotes => false;
  @override
  String get ttsVoiceModel => '';
  // initState reads (TtsSettingsDialog creates TextEditingControllers from these)
  @override
  String get openaiTtsApiKey => '';
  @override
  String get openaiTtsBaseUrl => '';
  @override
  String get openaiTtsModel => '';

  // Image generation settings — GenerationOptionsTab reads these in build().
  // imageGenBackend='remote' causes initState to skip the local-model / sampler
  // / lora fetch calls, so only fetchImageModels() (a no-op on
  // FakeImageGenService) is triggered.
  @override
  String get imageGenBackend => 'remote';
  @override
  bool get imageGenEnabled => false;
  @override
  String get imageGenModel => '';
  @override
  String get imageGenSize => '1024x1024';
  @override
  String get imageGenStyle => 'photorealistic';
  @override
  String get imageGenPromptParadigm => 'natural';
  @override
  String get imageGenNegativePrompt => '';
  @override
  String get localImageGenUrl => '';
  @override
  String get comfyUiUrl => '';
  @override
  bool get imageGenPromptReview => true;
  @override
  int get imageGenSeed => 0;
  @override
  String get drawThingsGrpcHost => '';
  @override
  int get drawThingsGrpcPort => 8080;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
