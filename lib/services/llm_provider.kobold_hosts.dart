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

part of 'llm_provider.dart';

/// The role name of the chat model in a swap.
const String kKoboldChatRole = 'chat';

/// The role name of the helper model (Realism evals) in a swap.
const String kKoboldWorkerRole = 'worker';

/// Swap hosts for the app's own KoboldCpp. Every role (the chat model, the
/// helper model, a story job) is loaded the same way a launch loads the
/// chat model: its config is staged in the admin folder and the engine is
/// asked to reload it by name.
extension LLMProviderKoboldHosts on LLMProvider {
  /// [role] names the staged file (`fpai-<role>.kcpps`). The chat role
  /// ignores [model] and [kcpps]: what chat loads is worked out when the
  /// swap happens, so a model picked in Settings mid-run is the one put
  /// back.
  KoboldProcessHost _koboldSwapHost({
    required String role,
    required String model,
    required String kcpps,
    Future<KoboldStagedRole> Function()? stage,
  }) {
    Duration limit() {
      final file = File(_koboldRolePair(role, model, kcpps).model);
      return koboldLoadTimeout(file.existsSync() ? file.lengthSync() : 0);
    }

    return KoboldProcessHost(
      baseUrl: _koboldService.baseUrl,
      requestedModelPath: model.trim().isEmpty ? null : model,
      requestedKcppsPath: kcpps.trim().isEmpty ? null : kcpps,
      stageConfig:
          stage ??
          () => _stageKoboldRole(role: role, model: model, kcpps: kcpps),
      isResident: _koboldService.isResident,
      noteResident: _koboldService.noteResident,
      onEngineContext: _storageService.backendSettings.setEngineContextSize,
      forgetLoadedPair: _koboldService.forgetAdminLoadedPair,
      onStep: _koboldService.showSwapStep,
      purpose: role == kKoboldChatRole
          ? 'chat'
          : role == kKoboldWorkerRole
          ? 'Realism checks'
          : 'the story',
      swapLock: _koboldService.adminSwapLock,
      noteLoadedPair: (model, kcpps) => _koboldService.noteAdminLoadedPair(
        modelPath: model,
        kcppsPath: kcpps,
      ),
      stopProcess: _koboldService.stopKobold,
      // A restart after a reload that was not acted on loads the same pair
      // the reload asked for: for chat, the one Settings has now.
      startProcess: () {
        final pair = _koboldRolePair(role, model, kcpps);
        return ensureManagedBackendIsRunning(
          forGpuSwap: true,
          modelPath: pair.model,
          kcppsPath: pair.kcpps,
        );
      },
      isProcessRunning: () => _koboldService.isProcessRunning,
      markNotReady: _koboldService.markModelNotReady,
      markLoading: _koboldService.markModelLoading,
      waitForReload: () => _koboldService.waitForSwap(timeout: limit()),
      waitForUnload: _koboldService.waitForUnload,
      // After a restart there is no old model to tell apart: ready is
      // ready. The limit still grows with the model.
      waitUntilReady: () => _koboldService.waitUntilReadyAfterSwap(
        attempts: limit().inMilliseconds ~/ 250,
      ),
      admin: HttpGpuSwapHost(
        kind: LocalSwapKind.koboldProcess,
        apiUrl: _koboldService.baseUrl,
        modelId: model,
      ),
    );
  }

  /// Puts what Settings now says chat runs (a new chat preset or model)
  /// into the running KoboldCpp: a reload of the staged chat config by
  /// name, and a restart when the reload is not acted on or KoboldCpp
  /// could not load it. What loaded is recorded as the model in use.
  /// Nothing happens when KoboldCpp is not running or chat's pair is
  /// loaded already.
  Future<void> _reloadChatKobold() async {
    if (!_koboldService.isProcessRunning) return;
    try {
      await _koboldSwapHost(
        role: kKoboldChatRole,
        model: '',
        kcpps: '',
      ).restore();
      await recordKoboldModelInUse(_storageService);
    } on KoboldSwapFailed catch (e) {
      // A fresh start loads the new config, or says in plain words why not.
      _koboldService.noteReloadFailed(e.message);
      await _koboldService.stopKobold();
      await ensureManagedBackendIsRunning();
    }
  }

  /// Loads [config], which belongs to no role (a timing trial), into the
  /// running KoboldCpp the way a swap loads a role: staged in the admin
  /// folder as [name], reloaded by name, waited for. True when it is what
  /// runs afterwards.
  Future<bool> loadKoboldTrial(String name, Map<String, dynamic> config) async {
    final dir = koboldAdminDirFor(_storageService);
    if (!_koboldService.isProcessRunning || dir.isEmpty) return false;
    final json = encodeKcpps(config);
    final file = await stageKoboldConfig(dir, name, json);
    final staged = KoboldStagedRole(
      filename: name,
      path: file.path,
      key: json,
      modelPath: kcppsModelOf(config),
      kcppsPath: '',
      expectedModel: koboldExpectedModelName(config),
      contextSize: koboldExpectedContext(config),
    );
    try {
      await _koboldSwapHost(
        role: 'trial',
        model: staged.modelPath,
        kcpps: '',
        stage: () async => staged,
      ).restore();
    } on KoboldSwapFailed catch (e) {
      debugPrint('[Presets] the trial $name did not load: $e');
      return false;
    }
    return _koboldService.isResident(json);
  }

  /// The model and preset [role] loads. The chat role's pair is worked out
  /// each time it is needed, never when its host was made.
  ({String model, String kcpps}) _koboldRolePair(
    String role,
    String model,
    String kcpps,
  ) {
    if (role != kKoboldChatRole) return (model: model, kcpps: kcpps);
    final chat = resolveKoboldLaunch(_storageService);
    return (model: chat.modelPath, kcpps: chat.kcppsPath ?? '');
  }

  Future<KoboldStagedRole> _stageKoboldRole({
    required String role,
    required String model,
    required String kcpps,
  }) {
    final chat = resolveKoboldLaunch(_storageService);
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
    final b = _storageService.backendSettings;
    return stageKoboldRole(
      storage: _storageService,
      executablePath: _backendManager.backendPath ?? '',
      name: asChat ? kStagedChatConfig : '$kStagedConfigPrefix$role.kcpps',
      modelPath: m,
      kcppsPath: k.isEmpty ? null : k,
      // Vision rides with the chat model only. Helper models never use it.
      mmprojPath: asChat && m.isNotEmpty
          ? _storageService.presetSettings.modelMmprojMap[m]
          : null,
      gpuLayers: b.gpuLayers,
      contextSize: b.contextSize,
      useVulkan: b.useVulkan ?? false,
      useCublas: b.useCublas ?? false,
      useMetal: b.useMetal ?? false,
      useRocm: b.useRocm ?? false,
      hardware: _koboldService.hardwareInfo?.call(),
      free: _koboldService.freeBeforeLaunch,
    );
  }
}
