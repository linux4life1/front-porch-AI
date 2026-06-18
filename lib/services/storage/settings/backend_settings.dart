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

import 'dart:io';
import 'settings_base.dart';
import 'preset_settings.dart'; // for parseKcppsFile (static)

/// Backend, remote API, reasoning, Kobold launch flags, model/kcpps paths,
/// GPU/context etc.
///
/// Lifted Stage 7. kcppsHasModel + context override from active preset logic
/// preserved exactly.
class BackendSettings with SettingsBase {
  String _backendType = 'kobold'; // 'kobold' or 'openRouter'
  String _remoteApiKey = '';
  String _remoteApiUrl = 'https://openrouter.ai/api/v1';
  String _remoteModelName = '';

  bool _reasoningEnabled = false;
  String _reasoningEffort = 'medium';
  bool _koboldThinkingModel = false;

  bool _autostartBackend = false;
  bool _autostartPseudoRemote = false;
  String? _lastUsedModelPath;
  String? _activeKcppsPath;
  bool _kcppsHasModel = false;

  bool? _useCublas;
  bool? _useVulkan;
  bool? _useMetal;
  bool? _useRocm;
  bool _flashAttentionEnabled = true;
  bool _mlockEnabled =
      !( /* platform default computed at load if needed, but we persist */ false);
  int _blasBatchSize = 512;
  int _gpuId = 0;
  int _gpuLayers = 0;
  int _contextSize = 8192;
  int _kvQuantizationLevel = 0;

  String get backendType => _backendType;
  String get remoteApiKey => _remoteApiKey;
  String get remoteApiUrl => _remoteApiUrl;
  String get remoteModelName => _remoteModelName;
  bool get reasoningEnabled => _reasoningEnabled;
  String get reasoningEffort => _reasoningEffort;
  bool get koboldThinkingModel => _koboldThinkingModel;
  bool get autostartBackend => _autostartBackend;
  bool get autostartPseudoRemote => _autostartPseudoRemote;
  String? get lastUsedModelPath => _lastUsedModelPath;
  String? get activeKcppsPath => _activeKcppsPath;
  bool get kcppsHasModel => _kcppsHasModel;

  /// Exact lift of original god kcppsModelFileExists (using moved static parse + existsSync).
  /// Returns whether the model file referenced in the active .kcpps preset exists on disk.
  /// When false the Flutter model picker should allow selection even if kcppsHasModel.
  bool get kcppsModelFileExists {
    final parsed = PresetSettings.parseKcppsFile(_activeKcppsPath);
    if (parsed == null) return false;
    final modelPath =
        parsed['model_param'] is String &&
            (parsed['model_param'] as String).trim().isNotEmpty
        ? (parsed['model_param'] as String).trim()
        : parsed['model'] is String
        ? (parsed['model'] as String).trim()
        : null;
    if (modelPath == null) return false;
    return File(modelPath).existsSync();
  }

  bool? get useCublas => _useCublas;
  bool? get useVulkan => _useVulkan;
  bool? get useMetal => _useMetal;
  bool? get useRocm => _useRocm;
  bool get flashAttentionEnabled => _flashAttentionEnabled;
  bool get mlockEnabled => _mlockEnabled;
  int get blasBatchSize => _blasBatchSize;
  int get gpuId => _gpuId;
  int get gpuLayers => _gpuLayers;
  int get contextSize => _contextSize;
  int get kvQuantizationLevel => _kvQuantizationLevel;

  void load() {
    _backendType = prefs?.getString(k('backend_type')) ?? 'kobold';
    _remoteApiKey = prefs?.getString(k('remote_api_key')) ?? '';
    _remoteApiUrl =
        prefs?.getString(k('remote_api_url')) ?? 'https://openrouter.ai/api/v1';
    _remoteModelName = prefs?.getString(k('remote_model_name')) ?? '';
    _reasoningEnabled = prefs?.getBool(k('reasoning_enabled')) ?? false;
    _reasoningEffort = prefs?.getString(k('reasoning_effort')) ?? 'medium';
    _koboldThinkingModel = prefs?.getBool(k('kobold_thinking_model')) ?? false;

    _autostartBackend =
        prefs?.getBool(k('autostart_backend')) ?? _autostartBackend;
    _autostartPseudoRemote =
        prefs?.getBool(k('autostart_pseudo_remote')) ?? _autostartPseudoRemote;
    _lastUsedModelPath = prefs?.getString(k('last_used_model_path'));
    _activeKcppsPath = prefs?.getString(k('active_kcpps_path'));

    // Restore the kcppsHasModel flag and context size from the persisted preset path
    final parsed = PresetSettings.parseKcppsFile(_activeKcppsPath);
    _kcppsHasModel =
        parsed != null &&
        ((parsed['model_param'] is String &&
                (parsed['model_param'] as String).trim().isNotEmpty) ||
            (parsed['model'] is String &&
                (parsed['model'] as String).trim().isNotEmpty));
    if (parsed != null && parsed['contextsize'] is int) {
      _contextSize = parsed['contextsize'] as int;
    }

    _useCublas = prefs?.getBool(k('use_cublas'));
    _useVulkan = prefs?.getBool(k('use_vulkan'));
    _useMetal = prefs?.getBool(k('use_metal'));
    _useRocm = prefs?.getBool(k('use_rocm'));
    _flashAttentionEnabled =
        prefs?.getBool(k('flash_attention_enabled')) ?? _flashAttentionEnabled;
    _mlockEnabled = prefs?.getBool(k('mlock_enabled')) ?? _mlockEnabled;
    // Cleanup orphaned prefs (original migration)
    prefs?.remove(k('context_shift_enabled'));
    _blasBatchSize = prefs?.getInt(k('blas_batch_size')) ?? _blasBatchSize;
    _gpuId = prefs?.getInt(k('gpu_id')) ?? _gpuId;
    _gpuLayers = prefs?.getInt(k('gpu_layers')) ?? _gpuLayers;
    _contextSize = prefs?.getInt(k('context_size')) ?? _contextSize;
    _kvQuantizationLevel =
        prefs?.getInt(k('kv_quantization_level')) ?? _kvQuantizationLevel;
  }

  Future<void> setBackendType(String value) async {
    _backendType = value;
    await prefs?.setString(k('backend_type'), value);
    notify();
  }

  Future<void> setRemoteApiKey(String value) async {
    _remoteApiKey = value;
    await prefs?.setString(k('remote_api_key'), value);
    notify();
  }

  Future<void> setRemoteApiUrl(String value) async {
    _remoteApiUrl = value;
    await prefs?.setString(k('remote_api_url'), value);
    notify();
  }

  Future<void> setRemoteModelName(String value) async {
    _remoteModelName = value;
    await prefs?.setString(k('remote_model_name'), value);
    notify();
  }

  Future<void> setReasoningEnabled(bool value) async {
    _reasoningEnabled = value;
    await prefs?.setBool(k('reasoning_enabled'), value);
    notify();
  }

  Future<void> setReasoningEffort(String value) async {
    _reasoningEffort = value;
    await prefs?.setString(k('reasoning_effort'), value);
    notify();
  }

  Future<void> setKoboldThinkingModel(bool value) async {
    _koboldThinkingModel = value;
    await prefs?.setBool(k('kobold_thinking_model'), value);
    notify();
  }

  Future<void> setAutostartBackend(bool value) async {
    _autostartBackend = value;
    await prefs?.setBool(k('autostart_backend'), value);
    notify();
  }

  Future<void> setAutostartPseudoRemote(bool value) async {
    _autostartPseudoRemote = value;
    await prefs?.setBool(k('autostart_pseudo_remote'), value);
    notify();
  }

  Future<void> setLastUsedModelPath(String? value) async {
    _lastUsedModelPath = value;
    if (value != null) {
      await prefs?.setString(k('last_used_model_path'), value);
    } else {
      await prefs?.remove(k('last_used_model_path'));
    }
    notify();
  }

  Future<void> setActiveKcppsPath(String? value) async {
    _activeKcppsPath = value;
    // Parse synchronously so _kcppsHasModel and _contextSize are accurate in the same notifyListeners call.
    final parsed = PresetSettings.parseKcppsFile(value);
    _kcppsHasModel =
        parsed != null &&
        ((parsed['model_param'] is String &&
                (parsed['model_param'] as String).trim().isNotEmpty) ||
            (parsed['model'] is String &&
                (parsed['model'] as String).trim().isNotEmpty));
    if (parsed != null && parsed['contextsize'] is int) {
      _contextSize = parsed['contextsize'] as int;
      await prefs?.setInt(k('context_size'), _contextSize);
    }
    if (value != null) {
      await prefs?.setString(k('active_kcpps_path'), value);
    } else {
      await prefs?.remove(k('active_kcpps_path'));
    }
    notify();
  }

  Future<void> setUseCublas(bool? value) async {
    _useCublas = value;
    if (value != null) {
      await prefs?.setBool(k('use_cublas'), value);
    } else {
      await prefs?.remove(k('use_cublas'));
    }
    notify();
  }

  Future<void> setUseVulkan(bool? value) async {
    _useVulkan = value;
    if (value != null) {
      await prefs?.setBool(k('use_vulkan'), value);
    } else {
      await prefs?.remove(k('use_vulkan'));
    }
    notify();
  }

  Future<void> setUseMetal(bool? value) async {
    _useMetal = value;
    if (value != null) {
      await prefs?.setBool(k('use_metal'), value);
    } else {
      await prefs?.remove(k('use_metal'));
    }
    notify();
  }

  Future<void> setUseRocm(bool? value) async {
    _useRocm = value;
    if (value != null) {
      await prefs?.setBool(k('use_rocm'), value);
    } else {
      await prefs?.remove(k('use_rocm'));
    }
    notify();
  }

  Future<void> setFlashAttentionEnabled(bool value) async {
    _flashAttentionEnabled = value;
    await prefs?.setBool(k('flash_attention_enabled'), value);
    notify();
  }

  Future<void> setMlockEnabled(bool value) async {
    _mlockEnabled = value;
    await prefs?.setBool(k('mlock_enabled'), value);
    notify();
  }

  Future<void> setBlasBatchSize(int value) async {
    _blasBatchSize = value;
    await prefs?.setInt(k('blas_batch_size'), value);
    notify();
  }

  Future<void> setGpuId(int value) async {
    _gpuId = value;
    await prefs?.setInt(k('gpu_id'), value);
    notify();
  }

  Future<void> setGpuLayers(int value) async {
    _gpuLayers = value;
    await prefs?.setInt(k('gpu_layers'), value);
    notify();
  }

  Future<void> setContextSize(int value) async {
    _contextSize = value;
    await prefs?.setInt(k('context_size'), value);
    notify();
  }

  Future<void> setKvQuantizationLevel(int value) async {
    _kvQuantizationLevel = value;
    await prefs?.setInt(k('kv_quantization_level'), value);
    notify();
  }
}
