// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The slot keeper's place in the service: what it is given, and the plan it
// works from for the engine that is loaded.

part of 'kobold_service.dart';

extension KoboldServiceKeeper on KoboldService {
  /// Made when first needed. It reads the service's port and load generation
  /// at each call, and does its work inside the swap lock.
  KoboldSlotKeeper get _keeper => _requests.keeper ??= KoboldSlotKeeper(
    api: KoboldHttpSlotApi(() => _baseUrl),
    loadGeneration: () => _loadGeneration,
    plan: _keeperPlan,
    underSwapLock: adminSwapLock.enqueue,
    log: _addLog,
    onFailure: _keeperFailed,
    recent: () => _storageService.backendSettings.keepRecentChats,
  );

  /// A deleted chat's saved cache is let go at once; emptying the slots when
  /// no chat is kept any more waits its turn in the line ([_settleKeeper]).
  /// A keeper that was never needed is not made for it.
  void _forgetChat(String chat) {
    final keeper = _requests.keeper;
    if (keeper != null && keeper.forget(chat)) _settleKeeper(keeper);
  }

  /// The chat the user has open changed. A keeper that was never needed
  /// holds nothing to let go of.
  void _openChat(String? chat) {
    final keeper = _requests.keeper;
    if (keeper != null && keeper.open(chat)) _settleKeeper(keeper);
  }

  /// What the keeper lets go of, and emptying the slots, waits its turn in
  /// the line: a save still running for a chat left finishes first. It never
  /// wakes a model unloaded for being idle (its slots went with it).
  void _settleKeeper(KoboldSlotKeeper keeper) =>
      unawaited(_requests.queue.run(keeper.settle));

  /// The engine could not do what the keeper asked. In auto mode that is
  /// remembered for this model on this engine version, and the next start
  /// leaves the chats to KoboldCpp's own smart cache, so the user is never
  /// worse off than before the keeper. A preset runs as its owner wrote it,
  /// and a keeper that only chose to stay out is not a failure.
  void _keeperFailed(String why) {
    if ((_loadedKcppsPath ?? '').isNotEmpty) return;
    unawaited(_rememberKeeperFailure());
  }

  Future<void> _rememberKeeperFailure() async {
    try {
      final model = path.basename(_loadedModelPath ?? '');
      final exe = _executablePath;
      if (model.isEmpty) return;
      final version = exe == null
          ? null
          : await KoboldBinaryVersion.versionFor(exe);
      final settings = _storageService.backendSettings;
      if (settings.keeperFailedFor(version, model)) return;
      await settings.noteKeeperFailed(version, model);
      _addLog(
        'The next time KoboldCpp starts with $model, its own smart cache will '
        'look after chats instead.',
      );
    } on Object catch (e) {
      debugPrint('[Kobold] the keeper failure could not be remembered: $e');
    }
  }

  /// Whether the keeper may act for the config the engine runs, from what it
  /// was given. See [koboldKeeperPlan].
  Future<KoboldKeeperPlan> _keeperPlan() async {
    final test = _requests.debugPlan;
    if (test != null) return test();
    final own = _process != null && _isRunning;
    final key = _residentKey;
    if (!own || key == null || key.isEmpty) {
      return koboldKeeperPlan(ownEngine: own, config: null, info: null);
    }
    try {
      final read = readKcpps(key);
      if (read is! KcppsOk) {
        return const KoboldKeeperPlan.off(
          'The settings KoboldCpp was given could not be read, so no chats '
          'are kept ready.',
        );
      }
      final config = read.config;
      final model = config.modelPath.isNotEmpty
          ? config.modelPath
          : (_loadedModelPath ?? '');
      final info = await koboldModelHeader(model);
      return koboldKeeperPlan(
        ownEngine: own,
        config: read.raw,
        info: info,
        memory: info == null ? null : await _keeperMemory(config, info, model),
      );
    } on Object catch (e) {
      return KoboldKeeperPlan.off(
        'Whether chats can be kept ready could not be worked out ($e).',
      );
    }
  }

  /// The memory the saved chats may use next to this model, or null when
  /// the machine's figures are not known.
  Future<KoboldKeeperMemory?> _keeperMemory(
    KoboldLaunchConfig config,
    GGUFModelInfo info,
    String model,
  ) async {
    final hardware = hardwareInfo?.call();
    if (hardware == null) return null;
    final int bytes;
    try {
      bytes = await File(model).length();
    } on FileSystemException {
      return null;
    }
    final gpu = koboldBackendFor(
      hardware: hardware,
      preset: config.backend,
      presetGpuId: config.gpuId,
      rocm: _storageService.backendSettings.useRocm,
    );
    final machine = gpu.machineFor(
      hardware,
      freeBeforeLaunch,
      cards: koboldCardsUsed(config, machineCards: hardware.cardCount),
    );
    final fit = KoboldFit(
      info: info,
      fileSizeBytes: bytes,
      contextSize: config.contextSize,
      batchSize: config.batchSize,
      backend: gpu.memory,
      kvQuant: config.kvQuant,
      flashAttention: config.flashAttention,
    );
    final load = config.gpuLayers == KoboldLaunchConfig.autoLayers
        ? koboldAutoTuning(fit, machine, batchSize: config.batchSize).load
        : fit.load(gpuLayers: config.gpuLayers);
    return (
      slotMb: fit.slotMb,
      freeRamMb: machine.systemMb,
      modelRamMb: koboldModelSystemMb(load, machine),
    );
  }

  /// Test hook: the engine program the service says it started.
  @visibleForTesting
  set debugEngineFile(String path) => _executablePath = path;

  /// Test hook: decides for the keeper in place of the real rules.
  @visibleForTesting
  set debugKeeperPlan(Future<KoboldKeeperPlan> Function()? plan) =>
      _requests.debugPlan = plan;

  /// Test hook: chat replies still waiting for their turn at the engine.
  @visibleForTesting
  int get debugRepliesWaiting => _requests.waiting.length;

  /// Test hook: the keeper, to read what it holds.
  @visibleForTesting
  KoboldSlotKeeper get debugKeeper => _keeper;

  /// Test hook: [output] as if the engine had printed it.
  @visibleForTesting
  void debugEngineSaid(String output) {
    _ingestLiveProgress(output);
    _speed.lines.add(output);
  }
}
