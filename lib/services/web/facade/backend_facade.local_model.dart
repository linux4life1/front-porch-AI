// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'backend_facade.dart';

/// The phone's "Local model" card and chat-preset picker: the same facts
/// as the desktop card (KoboldStatusFacts), the presets in the engine
/// folder with a line each, and the two things the phone sets.
extension BackendFacadeLocalModel on BackendFacade {
  /// The card: the model and whether it runs, the preset chat uses (with
  /// what it does) or auto mode's lines and context verdicts, and every
  /// preset to pick from.
  Future<Map<String, dynamic>> localModel() async {
    final b = _storage.backendSettings;
    final k = _llm.koboldService;
    // What a launch loads: the preset's own model when it names one here.
    final model = resolveKoboldLaunch(_storage).modelPath;
    final active = b.activeKcppsPath;
    final presets = [
      for (final f in kcppsPresetFiles(_storage.binDir.path))
        await KcppsLibrary.open(f.path),
    ];
    Map<String, dynamic>? preset;
    if (active != null) {
      final read = (await KcppsLibrary.open(active)).read;
      preset = {
        'path': active,
        'name': kcppsPresetName(active),
        'words': switch (read) {
          KcppsOk(:final config) => kcppsPlainWords(config),
          KcppsBroken(:final reason) => 'This preset cannot be read: $reason',
        },
      };
    }
    Map<String, dynamic>? auto;
    if (active == null && model.isNotEmpty) {
      final read = await _cardModelFor(model);
      final facts = KoboldStatusFacts.of(
        storage: _storage,
        hardware: _hardware?.hardwareInfo,
        free: await _freeForCard(),
        info: read.info,
        bytes: read.bytes,
      );
      auto = facts?.toJson(b.contextSize);
    }
    return {
      'model': model,
      'modelName': model.isEmpty ? null : koboldModelName(model),
      'running': k.isRunning,
      'ready': k.isReady,
      'starting': k.isStarting,
      'preset': preset,
      'auto': auto,
      'presets': [
        for (final e in presets)
          {'path': e.path, 'name': e.name, 'line': kcppsShortLine(e.read)},
      ],
    };
  }

  /// Makes [path] chat's preset, or none (the app's own settings) when
  /// null. Only a preset in the engine folder is taken: the server may be
  /// reachable from the internet, so no other path is accepted. A running
  /// KoboldCpp loads it in place.
  Future<bool> setChatPreset(String? path) async {
    if (path != null &&
        !kcppsPresetFiles(_storage.binDir.path).any((f) => f.path == path)) {
      return false;
    }
    final b = _storage.backendSettings;
    await b.setActiveKcppsPath(path);
    // As a launch does: a preset's own model becomes the model, so every
    // screen names what KoboldCpp loads.
    final launch = resolveKoboldLaunch(_storage);
    if (launch.modelPath.isNotEmpty &&
        launch.modelPath != b.lastUsedModelPath) {
      await b.setLastUsedModelPath(launch.modelPath);
    }
    final model = b.lastUsedModelPath;
    if (model != null && model.isNotEmpty) {
      await _storage.presetSettings.setModelPreset(model, path ?? '');
    }
    if (_llm.koboldService.isProcessRunning) await _llm.reloadChatKobold();
    return true;
  }

  /// Sets the context in auto mode. A running KoboldCpp loads it once the
  /// phone stops changing it.
  Future<bool> setLocalContext(int context) async {
    if (context < 512 || context > 1048576) return false;
    await _storage.backendSettings.setContextSize(context);
    if (_llm.koboldService.isProcessRunning) {
      _cardReload?.cancel();
      _cardReload = Timer(
        const Duration(milliseconds: 1500),
        () => _llm.reloadChatKobold().catchError(
          (Object e) => debugPrint('[web] chat reload failed: $e'),
        ),
      );
    }
    return true;
  }

  Future<({String path, GGUFModelInfo? info, int? bytes})> _cardModelFor(
    String model,
  ) async {
    final known = _cardModel;
    if (known != null && known.path == model) return known;
    GGUFModelInfo? info;
    int? bytes;
    try {
      info = await _models.getModelArchitectureInfo(model);
      bytes = await File(model).length();
    } on FileSystemException catch (e) {
      debugPrint('[web] local model unreadable: $e');
    }
    return _cardModel = (path: model, info: info, bytes: bytes);
  }

  /// Free memory before the app's KoboldCpp took any: read now when it is
  /// not running, else the reading taken before it started.
  Future<FreeMemoryMb?> _freeForCard() async {
    final hardware = _hardware;
    final k = _llm.koboldService;
    final kept = hardware?.freeBeforeEngine ?? k.freeBeforeLaunch;
    if (kept != null || hardware == null || k.isRunning) return kept;
    final free = await hardware.readFreeMemory(
      gpuId: _storage.backendSettings.gpuId,
    );
    hardware.freeBeforeEngine = free;
    return free;
  }
}
