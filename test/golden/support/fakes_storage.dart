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
// Callers read the *Settings objects (storage.uiSettings.textScale, etc.).
// Defaults below match the old flat-shim fake so goldens stay put.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Minimal [StorageService] double. Implements paths plus every *Settings
/// object widgets now read. All other members fall through to [noSuchMethod].
class FakeStorageService extends ChangeNotifier implements StorageService {
  FakeStorageService() {
    for (final s in [
      _generationSettings,
      _backendSettings,
      _uiSettings,
      _ttsSettings,
      _sttSettings,
      _imageGenSettings,
      _expressionSettings,
      _webServerSettings,
      _realismSettings,
      _webSearchSettings,
      _memorySettings,
      _presetSettings,
      _lorebookSettings,
    ]) {
      s.initializeBase(null, notifyListeners);
    }
    // Values the old flat fake returned that differ from Settings defaults.
    unawaited(_backendSettings.setBackendType('openRouter'));
    unawaited(_backendSettings.setRemoteApiUrl(''));
    unawaited(_backendSettings.setContextSize(8192));
    unawaited(_uiSettings.setBubbleOpacity(0.95));
    unawaited(_uiSettings.setGlobalUserBubbleColor(Colors.blueAccent));
    unawaited(_uiSettings.setGlobalUserTextColor(Colors.white));
    unawaited(_uiSettings.setGlobalAiBubbleColor(const Color(0xFF1E293B)));
    unawaited(_uiSettings.setGlobalAiTextColor(Colors.white));
    unawaited(_uiSettings.setGlobalDialogueColor(Colors.deepPurpleAccent));
    unawaited(_uiSettings.setGlobalActionColor(Colors.orangeAccent));
    unawaited(_ttsSettings.setTtsEngine('disabled'));
    unawaited(_ttsSettings.setTtsConcurrency(1));
    unawaited(_imageGenSettings.setImageGenEnabled(false));
    unawaited(_imageGenSettings.setImageGenNegativePrompt(''));
    unawaited(_imageGenSettings.setLocalImageGenUrl(''));
    unawaited(_imageGenSettings.setComfyUiUrl(''));
    unawaited(_imageGenSettings.setImageGenSeed(0));
    unawaited(_imageGenSettings.setDrawThingsGrpcHost(''));
    unawaited(_imageGenSettings.setDrawThingsGrpcPort(8080));
    unawaited(_realismSettings.setAdultThemesEnabled(true));
  }

  // Paths / directories
  @override
  String? get rootPath => null;
  @override
  Directory get chatsDir => Directory.systemTemp;
  @override
  Directory get toolsDir =>
      Directory('${Directory.systemTemp.path}/fpai_fake_tools');
  @override
  Directory get binDir => Directory.systemTemp;
  @override
  String? get customModelsPath => null;

  final _generationSettings = GenerationSettings();
  final _backendSettings = BackendSettings();
  final _uiSettings = UiSettings();
  final _ttsSettings = TtsSettings();
  final _sttSettings = SttSettings();
  final _imageGenSettings = ImageGenSettings();
  final _expressionSettings = ExpressionSettings();
  final _webServerSettings = WebServerSettings();
  final _realismSettings = RealismSettings();
  final _webSearchSettings = WebSearchSettings();
  final _memorySettings = MemorySettings();
  final _presetSettings = PresetSettings();
  final _lorebookSettings = LorebookSettings();

  @override
  GenerationSettings get generationSettings => _generationSettings;
  @override
  BackendSettings get backendSettings => _backendSettings;
  @override
  UiSettings get uiSettings => _uiSettings;
  @override
  TtsSettings get ttsSettings => _ttsSettings;
  @override
  SttSettings get sttSettings => _sttSettings;
  @override
  ImageGenSettings get imageGenSettings => _imageGenSettings;
  @override
  ExpressionSettings get expressionSettings => _expressionSettings;
  @override
  WebServerSettings get webServerSettings => _webServerSettings;
  @override
  RealismSettings get realismSettings => _realismSettings;
  @override
  WebSearchSettings get webSearchSettings => _webSearchSettings;
  @override
  MemorySettings get memorySettings => _memorySettings;
  @override
  PresetSettings get presetSettings => _presetSettings;
  @override
  LorebookSettings get lorebookSettings => _lorebookSettings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
