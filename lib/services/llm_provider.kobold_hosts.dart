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
      purpose: _koboldRolePurpose(role),
      swapLock: _koboldService.adminSwapLock,
      noteLoadedPair: (model, kcpps) => _koboldService.noteAdminLoadedPair(
        modelPath: model,
        kcppsPath: kcpps,
      ),
      stopProcess: _koboldService.stopKobold,
      // A restart after a reload that was not acted on loads the same pair
      // the reload asked for: for chat, the one Settings has now. One that
      // is refused fails the swap here, in words, instead of leaving it to
      // wait for an engine that was never started.
      startProcess: () async {
        final pair = _koboldRolePair(role, model, kcpps);
        final started = await _ensureManagedKobold(
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
  /// name, and a restart when the engine never acts on it. What loaded is
  /// recorded as the model in use. Nothing happens when KoboldCpp is not
  /// running or chat's pair is loaded already.
  ///
  /// When it could not be loaded KoboldCpp has gone back to the model it
  /// had, which still works. The reason is noted first, on the status line
  /// and in the log. If a fresh start would be refused (the new model file
  /// cannot be read, the preset is one the app will not start) nothing is
  /// stopped, the stored choice goes back to what runs ([_putChoiceBack]),
  /// and the answer is a refusal saying why. Otherwise the engine is stopped
  /// and started, and the start's answer is the answer. Null: nothing to
  /// report.
  Future<KoboldLaunchResult?> _reloadChatKobold() async {
    if (!_koboldService.isProcessRunning) return null;
    // Before the engine is touched, and before the first wait: the choice
    // this reload is for, what the service recorded as loaded, and the
    // config staged for it.
    final asked = resolveKoboldLaunch(_storageService);
    final model = _koboldService.loadedModelPath;
    final kcpps = _koboldService.loadedKcppsPath;
    final was = (
      model: model,
      kcpps: kcpps,
      asked: asked,
      staged: await readStagedKoboldConfig(
        koboldAdminDirFor(_storageService),
        kStagedChatConfig,
      ),
    );
    try {
      await _koboldSwapHost(
        role: kKoboldChatRole,
        model: '',
        kcpps: '',
      ).restore();
      await recordKoboldModelInUse(_storageService);
      return null;
    } on KoboldPresetProblem catch (e) {
      // Refused before anything was sent: the engine runs what it ran.
      _koboldService.noteReloadFailed(e.message);
      await _putChoiceBack(was);
      return _refusedKeepingEngine(e.message);
    } on KoboldSwapFailed catch (e) {
      _koboldService.noteReloadFailed(e.message);
      // The swap's own last resort stops the engine for a restart. When that
      // restart was refused, there is no previous model left to keep.
      if (!_koboldService.isProcessRunning) {
        return KoboldLaunchResult.refused(e.message);
      }
      final problem = await koboldLaunchProblem(_storageService);
      if (problem != null) {
        await _putChoiceBack(was);
        return _refusedKeepingEngine(problem);
      }
      await _koboldService.stopKobold();
      return _ensureManagedKobold();
    }
  }

  KoboldLaunchResult _refusedKeepingEngine(String why) =>
      KoboldLaunchResult.refused(
        'The new model was not loaded. The previous one is still running. '
        '$why',
      );

  /// The old model is kept running: chat's stored choice (the model in use,
  /// the preset, and the link between them) goes back to exactly the pair the
  /// service recorded as loaded before the reload, so every screen names what
  /// runs,
  /// and the staged chat config is the one that was there, which an idle
  /// unload loads back. The record is put back too, so the next refused
  /// reload can do the same.
  ///
  /// Only the record is trusted, and only when KoboldCpp itself says that
  /// model is the one running (a helper model loaded at the time, or an
  /// engine that went back to another, is not what the record says) and the
  /// choice is still the one this reload was for (one made meanwhile is the
  /// user's newer one). Otherwise nothing is guessed and nothing changes.
  Future<void> _putChoiceBack(
    ({String? model, String? kcpps, KoboldLaunch asked, String? staged}) was,
  ) async {
    final model = was.model;
    if (model == null || model.isEmpty) return;
    final runs = await koboldEngineModel(_koboldService.baseUrl);
    if (!koboldModelNameMatches(
      runs,
      koboldExpectedModelName({'model_param': model}),
    )) {
      return;
    }
    final now = resolveKoboldLaunch(_storageService);
    if (now.modelPath != was.asked.modelPath ||
        now.kcppsPath != was.asked.kcppsPath) {
      return;
    }
    final recorded = was.kcpps ?? '';
    final kcpps = recorded.isNotEmpty && await File(recorded).exists()
        ? recorded
        : '';
    // Exactly the recorded pair, written as it is. Not through
    // chooseKoboldPreset, which works out the model in use again and, for a
    // preset whose model has appeared on disk since the launch, would name
    // that one while KoboldCpp runs the model it was given.
    final b = _storageService.backendSettings;
    await b.setLastUsedModelPath(model);
    await b.setActiveKcppsPath(kcpps.isEmpty ? null : kcpps);
    await _storageService.presetSettings.setModelPreset(model, kcpps);
    _koboldService.noteAdminLoadedPair(modelPath: model, kcppsPath: kcpps);
    final staged = was.staged;
    final dir = koboldAdminDirFor(_storageService);
    if (staged != null && dir.isNotEmpty) {
      await stageKoboldConfig(dir, kStagedChatConfig, staged);
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
        role: kKoboldTrialRole,
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
