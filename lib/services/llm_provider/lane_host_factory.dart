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

import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_launch_args.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider/lane_ids.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/worker_backend.dart';
import 'package:front_porch_ai/services/worker_gpu_swap.dart';

/// The role name of the chat model in a swap.
const String kKoboldChatRole = 'chat';

/// The role name of the helper model (Realism evals) in a swap.
const String kKoboldWorkerRole = 'worker';

/// The role name of the preset editor's speed test in a swap.
const String kKoboldTrialRole = 'trial';

/// What [role]'s model is loaded for, as the status line says it. Every
/// other role is a story job.
String _koboldRolePurpose(String role) => switch (role) {
  kKoboldChatRole => 'chat',
  kKoboldWorkerRole => 'Realism checks',
  kKoboldTrialRole => 'the speed test',
  _ => 'the story',
};

/// Starts the app's KoboldCpp for a swap and says what the start said.
typedef EnsureKobold =
    Future<KoboldLaunchResult?> Function({
      bool forGpuSwap,
      String? modelPath,
      String? kcppsPath,
    });

/// Builds the swap hosts every lane runs on. For the app's own KoboldCpp,
/// every role (the chat model, the helper model, a story job) is loaded the
/// same way a launch loads the chat model: its config is staged in the
/// admin folder and the engine is asked to reload it by name.
class LaneHostFactory {
  LaneHostFactory({
    required KoboldService kobold,
    required StorageService storage,
    required BackendManager backendManager,
    required EnsureKobold ensureKobold,
  }) : _kobold = kobold,
       _storage = storage,
       _backendManager = backendManager,
       _ensureKobold = ensureKobold;

  final KoboldService _kobold;
  final StorageService _storage;
  final BackendManager _backendManager;
  final EnsureKobold _ensureKobold;

  /// [role] names the staged file (`fpai-<role>.kcpps`). The chat role
  /// ignores [model] and [kcpps]: what chat loads is worked out when the
  /// swap happens, so a model picked in Settings mid-run is the one put
  /// back.
  KoboldProcessHost koboldSwapHost({
    required String role,
    required String model,
    required String kcpps,
    Future<KoboldStagedRole> Function()? stage,
  }) {
    Duration limit() {
      final file = File(_rolePair(role, model, kcpps).model);
      return koboldLoadTimeout(file.existsSync() ? file.lengthSync() : 0);
    }

    late final KoboldProcessHost host;
    return host = KoboldProcessHost(
      baseUrl: _kobold.baseUrl,
      requestedModelPath: model.trim().isEmpty ? null : model,
      requestedKcppsPath: kcpps.trim().isEmpty ? null : kcpps,
      stageConfig:
          stage ?? () => stageRole(role: role, model: model, kcpps: kcpps),
      isResident: _kobold.isResident,
      noteResident: _kobold.noteResident,
      onEngineContext: _storage.backendSettings.setEngineContextSize,
      forgetLoadedPair: _kobold.forgetAdminLoadedPair,
      onStep: _kobold.showSwapStep,
      purpose: _koboldRolePurpose(role),
      swapLock: _kobold.adminSwapLock,
      noteLoadedPair: (model, kcpps) =>
          _kobold.noteAdminLoadedPair(modelPath: model, kcppsPath: kcpps),
      stopProcess: _kobold.stopKobold,
      // A restart after a reload that was not acted on loads the same pair
      // the reload asked for: for chat, the one Settings has now. One that
      // is refused fails the swap here, in words, instead of leaving it to
      // wait for an engine that was never started.
      startProcess: () async {
        final pair = _rolePair(role, model, kcpps);
        final started = await _ensureKobold(
          forGpuSwap: true,
          modelPath: pair.model,
          kcppsPath: pair.kcpps,
        );
        if (started != null && !started.started) {
          throw KoboldSwapFailed(
            started.message ?? 'KoboldCpp could not be started.',
          );
        }
      },
      isProcessRunning: () => _kobold.isProcessRunning,
      markNotReady: _kobold.markModelNotReady,
      markLoading: _kobold.markModelLoading,
      // Counted from when the engine was asked, not from when the answer
      // was read.
      waitForReload: () =>
          _kobold.waitForSwap(timeout: limit(), since: host.adminAskedAt),
      waitForUnload: () => _kobold.waitForUnload(since: host.adminAskedAt),
      // After a restart there is no old model to tell apart: ready is
      // ready. The limit still grows with the model.
      waitUntilReady: () => _kobold.waitUntilReadyAfterSwap(
        attempts: limit().inMilliseconds ~/ 250,
      ),
      admin: HttpGpuSwapHost(
        kind: LocalSwapKind.koboldProcess,
        apiUrl: _kobold.baseUrl,
        modelId: model,
      ),
    );
  }

  /// The model and preset [role] loads. The chat role's pair is worked out
  /// each time it is needed, never when its host was made.
  ({String model, String kcpps}) _rolePair(
    String role,
    String model,
    String kcpps,
  ) {
    if (role != kKoboldChatRole) return (model: model, kcpps: kcpps);
    final chat = resolveKoboldLaunch(_storage);
    return (model: chat.modelPath, kcpps: chat.kcppsPath ?? '');
  }

  /// [trial] and [asName]: the speed test's try of chat's own config, staged
  /// under its own name (see `koboldLaunchMap`).
  Future<KoboldStagedRole> stageRole({
    required String role,
    required String model,
    required String kcpps,
    KoboldKnobs? trial,
    String? asName,
  }) {
    final chat = resolveKoboldLaunch(_storage);
    final chatKcpps = chat.kcppsPath ?? '';
    final isChat = role == kKoboldChatRole;
    final m = isChat ? chat.modelPath : model;
    final k = isChat ? chatKcpps : kcpps;
    // A role set to the chat model's own pair IS the chat model: it stages
    // the same content (vision file included), so nothing is reloaded.
    final asChat =
        isChat ||
        (normalizeLocalModelPath(m) ==
                normalizeLocalModelPath(chat.modelPath) &&
            normalizeLocalModelPath(k) == normalizeLocalModelPath(chatKcpps));
    final b = _storage.backendSettings;
    return stageKoboldRole(
      storage: _storage,
      executablePath: _backendManager.backendPath ?? '',
      name:
          asName ??
          (asChat ? kStagedChatConfig : '$kStagedConfigPrefix$role.kcpps'),
      trial: trial,
      modelPath: m,
      kcppsPath: k.isEmpty ? null : k,
      // Vision rides with the chat model only. Helper models never use it.
      mmprojPath: asChat && m.isNotEmpty
          ? _storage.presetSettings.modelMmprojMap[m]
          : null,
      gpuLayers: b.gpuLayers,
      contextSize: b.contextSize,
      useVulkan: b.useVulkan ?? false,
      useCublas: b.useCublas ?? false,
      useMetal: b.useMetal ?? false,
      useRocm: b.useRocm ?? false,
      hardware: _kobold.hardwareInfo?.call(),
      free: _kobold.freeBeforeLaunch,
    );
  }

  /// [role] names the staged config when the host is the app's own engine.
  GpuSwapHost? hostForLane({
    required String role,
    required String type,
    required String url,
    required String model,
    required String key,
    String kcpps = '',
  }) {
    final kind = localSwapKindFor(backendType: type, apiUrl: url);
    if (kind == null) return null;
    if (kind == LocalSwapKind.koboldProcess) {
      return koboldSwapHost(role: role, model: model, kcpps: kcpps);
    }
    final apiUrl = type == 'omlx' ? kOmlxApiV1 : resolvedLaneApiUrl(type, url);
    return HttpGpuSwapHost(
      kind: kind,
      apiUrl: apiUrl,
      modelId: model,
      apiKey: key,
    );
  }

  /// A fresh chat ↔ helper occupancy for the saved pair, or null when either
  /// side has no swap host.
  GpuSwapOccupancy? workerOccupancy() {
    final mouth = hostForLane(
      role: kKoboldChatRole,
      type: _storage.backendSettings.backendType,
      url: _storage.backendSettings.remoteApiUrl,
      model: mouthSwapModelId(_storage),
      kcpps: koboldKcppsId(_storage, worker: false),
      key: mouthLaneApiKey(_storage),
    );
    final worker = hostForLane(
      role: kKoboldWorkerRole,
      type: _storage.workerBackendType,
      url: _storage.workerRemoteApiUrl,
      model: workerSwapModelId(_storage),
      kcpps: koboldKcppsId(_storage, worker: true),
      key: workerLaneApiKey(_storage),
    );
    if (mouth == null || worker == null) return null;
    return GpuSwapOccupancy(
      mouth: mouth,
      worker: worker,
      sameResident: savedLanesShareResident(_storage),
      sharedEngine: mouth is KoboldProcessHost && worker is KoboldProcessHost,
      residentGeneration: worker is KoboldProcessHost
          ? () => _kobold.loadGeneration
          : null,
    );
  }
}
