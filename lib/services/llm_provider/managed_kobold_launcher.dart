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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/worker_backend.dart';

/// Starts the app's KoboldCpp for chat entry or for a swap, and keeps why
/// the last start was refused, for the chat screen's connection hint.
class ManagedKoboldLauncher {
  ManagedKoboldLauncher({
    required KoboldService kobold,
    required StorageService storage,
    required BackendManager backendManager,
    required bool Function() anyProcessRunning,
    required bool Function() workerRefusedDualLocal,
    required VoidCallback onChanged,
  }) : _kobold = kobold,
       _storage = storage,
       _backendManager = backendManager,
       _anyProcessRunning = anyProcessRunning,
       _workerRefusedDualLocal = workerRefusedDualLocal,
       _onChanged = onChanged;

  final KoboldService _kobold;
  final StorageService _storage;
  final BackendManager _backendManager;
  final bool Function() _anyProcessRunning;
  final bool Function() _workerRefusedDualLocal;
  final VoidCallback _onChanged;

  /// Why the last start was refused, and what the engine had loaded then.
  ({String words, int generation})? _refusal;

  /// Starts KoboldCpp and keeps what the start said, for [refusalHint].
  /// Null when nothing needed starting.
  Future<KoboldLaunchResult?> ensure({
    bool forGpuSwap = false,
    String? modelPath,
    String? kcppsPath,
  }) async {
    final result = await _start(
      forGpuSwap: forGpuSwap,
      modelPath: modelPath,
      kcppsPath: kcppsPath,
    );
    if (result != null) _noteStart(result);
    return result;
  }

  void _noteStart(KoboldLaunchResult result) {
    // A start refused because another is under way says nothing about how
    // that one ends.
    if (_kobold.isStarting) return;
    final words = result.refusal;
    final before = _refusal?.words;
    _refusal = words == null
        ? null
        : (words: words, generation: _kobold.loadGeneration);
    if (before != words) _onChanged();
  }

  /// Why the app's start of KoboldCpp was refused, in plain words. Null once
  /// what the engine has loaded has changed since the refusal (it was
  /// started some other way, and stopped), which makes the refusal no longer
  /// why nothing runs.
  String? get refusalHint {
    final refusal = _refusal;
    return refusal != null && refusal.generation == _kobold.loadGeneration
        ? refusal.words
        : null;
  }

  /// The model a launch of [modelPath] runs: none (or the backend name)
  /// means the one Settings has.
  String effectiveLaunchPath(String? modelPath) {
    final raw = modelPath?.trim() ?? '';
    if (raw.isEmpty || raw == 'kobold') {
      return _storage.backendSettings.lastUsedModelPath?.trim() ?? '';
    }
    return raw;
  }

  /// Null when nothing needed starting; otherwise what the start said. A
  /// swap needs the answer: a restart that was refused is not waited for.
  Future<KoboldLaunchResult?> _start({
    bool forGpuSwap = false,
    String? modelPath,
    String? kcppsPath,
  }) async {
    final requested = effectiveLaunchPath(modelPath);
    final kcpps = forGpuSwap
        ? (kcppsPath?.trim() ?? '')
        : (_storage.backendSettings.activeKcppsPath?.trim() ?? '');
    if (_anyProcessRunning()) {
      if (!forGpuSwap) return null;
      if (_alreadyHas(requested, kcpps)) return null;
    } else if (!forGpuSwap &&
        !shouldEnsureKoboldProcess(
          mouthType: _storage.backendSettings.backendType,
          workerType: _storage.workerBackendType,
          pairAllowed: !_workerRefusedDualLocal(),
          mouthIsLocal: backendLaneIsLocal(
            _storage.backendSettings.backendType,
            _storage.backendSettings.remoteApiUrl,
          ),
        )) {
      return null;
    }

    // Looked for again: the build on disk must be the one the acceleration
    // choice needs, whatever changed since the last look.
    final engine = await _backendManager.engineForStart();
    if (engine == null) {
      unawaited(_backendManager.ensureEngineInstalled());
      return const KoboldLaunchResult.refused(
        'The AI engine is not installed yet.',
      );
    }

    try {
      if (!forGpuSwap) {
        // Chat entry: the same rule as every other start.
        if (!resolveKoboldLaunch(_storage).canLaunch) return null;
        return await _kobold.launch(engine, port: _kobold.port);
      }
      // A swap names its own model and preset.
      if (requested.isEmpty && kcpps.isEmpty) {
        return const KoboldLaunchResult.refused(kKoboldNoModelWords);
      }
      // Putting chat back keeps vision; helper and story models never use
      // it. Chat is what the launch rule gives now, which can be a model
      // the active preset names rather than the last one picked.
      // The preset may be the rule's (which drops one whose file is gone)
      // or the one Settings has stored.
      final chat = resolveKoboldLaunch(_storage);
      final chatKcpps = {
        chat.kcppsPath ?? '',
        _storage.backendSettings.activeKcppsPath?.trim() ?? '',
      }.map(normalizeLocalModelPath);
      final mouthPair =
          normalizeLocalModelPath(requested) ==
              normalizeLocalModelPath(chat.modelPath) &&
          chatKcpps.contains(normalizeLocalModelPath(kcpps));
      final b = _storage.backendSettings;
      return await _kobold.startKobold(
        engine,
        requested,
        kcppsPath: kcpps.isEmpty ? null : kcpps,
        port: _kobold.port,
        mmprojPath: mouthPair && requested.isNotEmpty ? chat.mmprojPath : null,
        gpuLayers: b.gpuLayers,
        contextSize: b.contextSize,
        useVulkan: b.useVulkan ?? false,
        useCublas: b.useCublas ?? false,
        useMetal: b.useMetal ?? false,
        useRocm: b.useRocm ?? false,
      );
    } catch (e) {
      debugPrint('[LLMProvider] ensureManagedBackendIsRunning failed: $e');
      return KoboldLaunchResult.refused('KoboldCpp could not be started ($e).');
    }
  }

  bool _alreadyHas(String requested, String kcpps) {
    if (!_kobold.isReady) return false;
    if (normalizeLocalModelPath(_kobold.loadedModelPath ?? '') !=
        normalizeLocalModelPath(requested)) {
      return false;
    }
    return normalizeLocalModelPath(_kobold.loadedKcppsPath ?? '') ==
        normalizeLocalModelPath(kcpps);
  }
}
