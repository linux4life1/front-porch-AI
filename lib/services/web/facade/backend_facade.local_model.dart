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
        // As the picker lists a preset in the engine folder: one picked
        // from elsewhere on the desktop is in use but not in that list.
        'line': kcppsShortLine(read),
        'words': switch (read) {
          KcppsOk(:final config) => kcppsPlainWords(
            config,
            machineCards: _hardware?.hardwareInfo?.cardCount,
          ),
          KcppsBroken(:final reason) => 'This preset cannot be read: $reason',
        },
      };
    }
    Map<String, dynamic>? auto;
    var unreadable = false;
    if (active == null && model.isNotEmpty) {
      final read = await _cardModelFor(model);
      unreadable = read.info == null || read.bytes == null;
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
      'phase': k.phase.name,
      'preset': preset,
      'auto': auto,
      // Why a chosen model has no `auto`: its file could not be read (else
      // this computer is not known yet). Additive.
      'modelUnreadable': unreadable,
      'presets': [
        for (final e in presets)
          {'path': e.path, 'name': e.name, 'line': kcppsShortLine(e.read)},
      ],
    };
  }

  /// Makes [path] chat's preset, or none (the app's own settings) when
  /// null. Only a preset in the engine folder is taken: the server may be
  /// reachable from the internet, so no other path is accepted. A running
  /// KoboldCpp loads it in place, which takes as long as a model takes to
  /// load: the card is returned at once and shows the progress.
  Future<bool> setChatPreset(String? path) async {
    if (path != null &&
        !kcppsPresetFiles(_storage.binDir.path).any((f) => f.path == path)) {
      return false;
    }
    // A context tapped just before is superseded: this reloads at once.
    _cardReload?.cancel();
    final b = _storage.backendSettings;
    await b.setActiveKcppsPath(path);
    // As a launch does: a preset's own model becomes the model, so every
    // screen names what KoboldCpp loads.
    await recordKoboldModelInUse(_storage);
    final model = b.lastUsedModelPath;
    if (model != null && model.isNotEmpty) {
      await _storage.presetSettings.setModelPreset(model, path ?? '');
    }
    if (_llm.koboldService.isProcessRunning) {
      unawaited(
        _llm.reloadChatKobold().catchError(
          (Object e) => debugPrint('[web] chat reload failed: $e'),
        ),
      );
    }
    return true;
  }

  /// Sets the context in auto mode. A running KoboldCpp loads it once the
  /// phone stops changing it.
  Future<bool> setLocalContext(int context) async {
    if (context < kKoboldContextMin || context > kKoboldContextMax) {
      return false;
    }
    // A preset sets its own context; the desktop locks this field then too.
    if (_storage.backendSettings.activeKcppsPath != null) return false;
    await _storage.backendSettings.setContextSize(context);
    if (_llm.koboldService.isProcessRunning) {
      _cardReload?.cancel();
      _cardReload = Timer(
        kKoboldContextReloadDelay,
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
    final read = (path: model, info: info, bytes: bytes);
    // Only a read that worked is kept, so a file back in its folder is read.
    if (info != null && bytes != null) _cardModel = read;
    return read;
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
