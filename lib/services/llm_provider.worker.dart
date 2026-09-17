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

extension LLMProviderWorker on LLMProvider {
  OpenRouterService get workerRemoteService => _workerRemote;

  LLMService? _liveWorkerService() {
    if (!workerConfigured || workerRefusedDualLocal) return null;
    return _providerWorkerOverride[this] ??
        switch (workerBackend) {
          BackendType.kobold => _koboldService,
          BackendType.openRouter || BackendType.omlx => _workerRemote,
          null => null,
        };
  }

  @visibleForTesting
  bool get debugOmlxPollerStarted => _omlxPoller.isStarted;

  String get workerEvalIdentity {
    final type = _storageService.workerBackendType;
    final url = resolvedLaneApiUrl(type, _storageService.workerRemoteApiUrl);
    final svc = workerService ?? _workerRemote;
    return workerEvalIdentityFor(
      backendName: svc.backendName,
      remoteApiUrl: url,
      remoteModelName: _storageService.workerRemoteModelName,
      modelPath: type == 'kobold'
          ? _storageService.resolvedWorkerKoboldModelPath()
          : null,
    );
  }

  /// Point [_workerRemote] at the saved worker host/model. Returns true
  /// when the pair identity changed. Does not touch [activeService].
  bool _syncWorkerFromStorage() {
    final type = _storageService.workerBackendType;
    final url = resolvedLaneApiUrl(type, _storageService.workerRemoteApiUrl);
    final model = _storageService.workerRemoteModelName;
    final key = (type == 'openRouter' || type == 'omlx')
        ? _storageService.remoteApiKeyFor(url)
        : '';
    // Mouth host rides this key so a mouth URL flip (OpenRouter → LM Studio)
    // re-evaluates dual-local without waiting for a worker-field edit.
    // The vault key is included so a key typed last still reconfigures.
    final identity =
        '${_storageService.backendType}|${_storageService.remoteApiUrl}|'
        '$type|$url|$model|$key|${_mouthSwapModelId()}|'
        '${_workerSwapModelId()}|${_koboldKcppsId(worker: false)}|'
        '${_koboldKcppsId(worker: true)}';
    if (identity == _lastWorkerIdentity) return false;
    _lastWorkerIdentity = identity;
    if (type == 'openRouter' || type == 'omlx') {
      _workerRemote.configure(apiUrl: url, apiKey: key, modelName: model);
    }
    _syncLiveStatusSources();
    _rebuildGpuSwap();
    return true;
  }

  /// Dual-local unload/swap is available for this pair. Widget tests
  /// stay fail-closed unless they inject [debugGpuSwap] (V1 pins).
  bool get workerGpuSwapAvailable {
    if (_providerSwapOverride[this] != null) return true;
    if (runningUnderFlutterTestBinding() || kSkipRemoteAutoPing) {
      return false;
    }
    return _pairSupportsGpuSwap();
  }

  @visibleForTesting
  set debugGpuSwap(GpuSwapOccupancy? occupancy) {
    _providerSwapOverride[this] = occupancy;
  }

  @visibleForTesting
  set debugWorkerService(LLMService? service) {
    _providerWorkerOverride[this] = service;
  }

  @visibleForTesting
  GpuSwapOccupancy? get debugGpuSwap =>
      _providerHeldSwap[this] ??
      _providerSwapOverride[this] ??
      _providerSwap[this];

  /// Production Expando only. Mid-hold rebuild must not write here.
  @visibleForTesting
  GpuSwapOccupancy? get debugGpuSwapExpando => _providerSwap[this];

  Future<T> withWorkerLane<T>(Future<T> Function() work) {
    final occupancy = _occupancyForLane();
    if (occupancy == null) return work();
    _pinHeldSwap(occupancy);
    return occupancy.hold(work).whenComplete(() {
      _releaseHeldSwapIfIdle(occupancy);
    });
  }

  Future<void> openWorkerLane() async {
    final occupancy = _occupancyForLane();
    if (occupancy == null) return;
    _pinHeldSwap(occupancy);
    try {
      await occupancy.open();
    } catch (_) {
      _releaseHeldSwapIfIdle(occupancy);
      rethrow;
    }
  }

  Future<void> closeWorkerLane() async {
    final occupancy = _occupancyForLane();
    if (occupancy == null) return;
    try {
      await occupancy.close();
    } finally {
      _releaseHeldSwapIfIdle(occupancy);
    }
  }

  bool get isWorkerLaneHeld =>
      _providerHeldSwap[this]?.isHeld ??
      _providerSwapOverride[this]?.isHeld ??
      _providerSwap[this]?.isHeld ??
      false;

  bool get gpuSwapBusy => _occupancyForLane()?.isBusy ?? false;

  /// Auto-ping may open the worker only after an explicit handoff
  /// (worker resident). Mouth-up / mid-swap must not start prepare-worker.
  bool get workerLaneReadyForAutoPing {
    final occ = _occupancyForLane();
    if (occ == null || occ.sameResident) return true;
    if (occ.isBusy || occ.speechHeld) return false;
    return occ.mouthDown;
  }

  Future<void> waitForWorkerLaneIdle({bool pinSpeech = false}) async {
    while (isWorkerLaneHeld) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final occupancy =
        _providerHeldSwap[this] ??
        _providerSwapOverride[this] ??
        _providerSwap[this];
    // Pin BEFORE restore. `_markModelReady` notifies during the await; a
    // listener that `openWorkerLane`s must not unload-mouth in the gap
    // before beginSpeech (live: restore-mouth → PRE-GEN → unload, no
    // speech stream).
    if (pinSpeech) occupancy?.beginSpeech();
    try {
      if (occupancy != null) await occupancy.ensureMouth();
    } catch (_) {
      if (pinSpeech) occupancy?.endSpeech();
      rethrow;
    }
    if (!pinSpeech) _dropHeldSwapIfMouthUp();
  }

  /// Release the speech pin so post-eval [hold] may unload the mouth.
  void endMouthSpeech() {
    final occupancy =
        _providerHeldSwap[this] ??
        _providerSwapOverride[this] ??
        _providerSwap[this];
    occupancy?.endSpeech();
  }

  void _pinHeldSwap(GpuSwapOccupancy occupancy) {
    _providerHeldSwap[this] ??= occupancy;
    _providerHeldPins[this] = (_providerHeldPins[this] ?? 0) + 1;
  }

  void _releaseHeldSwapIfIdle(GpuSwapOccupancy occupancy) {
    if (!identical(_providerHeldSwap[this], occupancy)) return;
    final pins = (_providerHeldPins[this] ?? 1) - 1;
    if (pins > 0) {
      _providerHeldPins[this] = pins;
      return;
    }
    _providerHeldPins[this] = null;
    // Worker-hot residency: keep the acquired token and park it on the
    // Expando so a dirty rebuild cannot mint a fresh mouth-up occupancy.
    if (occupancy.mouthDown || occupancy.isBusy) {
      _providerSwap[this] = occupancy;
      return;
    }
    _providerHeldSwap[this] = null;
    if (_providerSwapDirty[this] == true) {
      _providerSwapDirty[this] = null;
      _rebuildGpuSwap();
    }
  }

  void _dropHeldSwapIfMouthUp() {
    final held = _providerHeldSwap[this];
    if (held == null || held.isHeld || held.mouthDown || held.isBusy) return;
    _providerHeldSwap[this] = null;
    _providerHeldPins[this] = null;
    if (_providerSwapDirty[this] == true) {
      _providerSwapDirty[this] = null;
      _rebuildGpuSwap();
    }
  }

  bool _pairSupportsGpuSwap() {
    if (!workerConfigured) return false;
    return workerGpuSwapSupported(
      mouthType: _storageService.backendType,
      mouthUrl: _storageService.remoteApiUrl,
      mouthModel: _mouthSwapModelId(),
      workerType: _storageService.workerBackendType,
      workerUrl: _storageService.workerRemoteApiUrl,
      workerModel: _workerSwapModelId(),
      mouthKcpps: _koboldKcppsId(worker: false),
      workerKcpps: _koboldKcppsId(worker: true),
    );
  }

  String _mouthSwapModelId() {
    if (_storageService.backendType == 'kobold') {
      return _storageService.lastUsedModelPath?.trim() ?? '';
    }
    return _storageService.remoteModelName;
  }

  String _workerSwapModelId() {
    if (_storageService.workerBackendType == 'kobold') {
      return _storageService.resolvedWorkerKoboldModelPath();
    }
    return _storageService.workerRemoteModelName;
  }

  Future<void> _ensureManagedKobold({
    bool forGpuSwap = false,
    String? modelPath,
    String? kcppsPath,
  }) async {
    final requested = _effectiveKoboldLaunchPath(modelPath);
    final kcpps = forGpuSwap
        ? (kcppsPath?.trim() ?? '')
        : (_storageService.activeKcppsPath?.trim() ?? '');
    if (hasAnyManagedProcessRunning) {
      if (!forGpuSwap) return;
      if (_managedKoboldAlreadyHas(requested, kcpps)) return;
    } else if (!forGpuSwap &&
        !shouldEnsureKoboldProcess(
          mouthType: _storageService.backendType,
          workerType: _storageService.workerBackendType,
          pairAllowed: !workerRefusedDualLocal,
          mouthIsLocal: backendLaneIsLocal(
            _storageService.backendType,
            _storageService.remoteApiUrl,
          ),
        )) {
      return;
    }

    if (_backendManager.backendPath == null) {
      await _backendManager.checkBackendAvailability();
      if (_backendManager.backendPath == null) {
        unawaited(_backendManager.ensureEngineInstalled());
        return;
      }
    }

    try {
      final hasPresetWithModel =
          _storageService.kcppsHasModel && _storageService.kcppsModelFileExists;
      if (requested.isEmpty) {
        if (forGpuSwap) {
          if (kcpps.isEmpty) return;
        } else if (!hasPresetWithModel) {
          return;
        }
      }
      final mouthModel = normalizeLocalModelPath(
        _storageService.lastUsedModelPath ?? '',
      );
      final mouthKcpps = normalizeLocalModelPath(
        _storageService.activeKcppsPath?.trim() ?? '',
      );
      final mouthPair =
          normalizeLocalModelPath(requested) == mouthModel &&
          normalizeLocalModelPath(kcpps) == mouthKcpps;
      // Chat-entry and mouth restore keep vision. Worker/evals never do.
      final attachMmproj = !forGpuSwap || mouthPair;
      await _koboldService.startKobold(
        _backendManager.backendPath!,
        requested,
        kcppsPath: kcpps.isEmpty ? null : kcpps,
        mmprojPath: attachMmproj && requested.isNotEmpty
            ? _storageService.mmprojForModel(requested)
            : null,
        gpuLayers: _storageService.gpuLayers,
        contextSize: _storageService.contextSize,
        useVulkan: _storageService.useVulkan ?? false,
        useCublas: _storageService.useCublas ?? false,
        useMetal: _storageService.useMetal ?? false,
        useRocm: _storageService.useRocm ?? false,
      );
    } catch (e) {
      debugPrint('[LLMProvider] ensureManagedBackendIsRunning failed: $e');
    }
  }

  String _effectiveKoboldLaunchPath(String? modelPath) {
    final raw = modelPath?.trim() ?? '';
    if (raw.isEmpty || raw == 'kobold') {
      return _storageService.lastUsedModelPath?.trim() ?? '';
    }
    return raw;
  }

  String _koboldKcppsId({required bool worker}) {
    if (worker) return _storageService.resolvedWorkerKoboldKcppsPath();
    return _storageService.activeKcppsPath?.trim() ?? '';
  }

  bool _managedKoboldAlreadyHas(String requested, String kcpps) {
    if (!_koboldService.isReady) return false;
    if (normalizeLocalModelPath(_koboldService.loadedModelPath ?? '') !=
        normalizeLocalModelPath(requested)) {
      return false;
    }
    return normalizeLocalModelPath(_koboldService.loadedKcppsPath ?? '') ==
        normalizeLocalModelPath(kcpps);
  }

  GpuSwapOccupancy? _occupancyForLane() {
    final held = _providerHeldSwap[this];
    if (held != null) return held;
    final injected = _providerSwapOverride[this];
    if (injected != null) return injected;
    if (!workerGpuSwapAvailable) return null;
    if (!_pairSupportsGpuSwap()) return null;
    return _providerSwap[this] ?? _rebuildGpuSwap();
  }

  GpuSwapOccupancy? _rebuildGpuSwap() {
    final live = _providerSwap[this];
    final held = _providerHeldSwap[this];
    if (held != null ||
        (_providerHeldPins[this] ?? 0) > 0 ||
        (live != null && (live.isHeld || live.mouthDown || live.isBusy))) {
      _providerSwapDirty[this] = true;
      return held ?? live;
    }
    if (!_pairSupportsGpuSwap()) {
      _providerSwap[this] = null;
      return null;
    }
    final mouth = _hostForLane(
      type: _storageService.backendType,
      url: _storageService.remoteApiUrl,
      model: _mouthSwapModelId(),
      kcpps: _koboldKcppsId(worker: false),
      key: _storageService.remoteApiKeyFor(
        resolvedLaneApiUrl(
          _storageService.backendType,
          _storageService.remoteApiUrl,
        ),
      ),
    );
    final worker = _hostForLane(
      type: _storageService.workerBackendType,
      url: _storageService.workerRemoteApiUrl,
      model: _workerSwapModelId(),
      kcpps: _koboldKcppsId(worker: true),
      key: _storageService.remoteApiKeyFor(
        resolvedLaneApiUrl(
          _storageService.workerBackendType,
          _storageService.workerRemoteApiUrl,
        ),
      ),
    );
    if (mouth == null || worker == null) {
      _providerSwap[this] = null;
      return null;
    }
    final occupancy = GpuSwapOccupancy(
      mouth: mouth,
      worker: worker,
      sameResident: workerLanesShareResident(
        mouthType: _storageService.backendType,
        mouthUrl: _storageService.remoteApiUrl,
        mouthModel: _mouthSwapModelId(),
        workerType: _storageService.workerBackendType,
        workerUrl: _storageService.workerRemoteApiUrl,
        workerModel: _workerSwapModelId(),
        mouthKcpps: _koboldKcppsId(worker: false),
        workerKcpps: _koboldKcppsId(worker: true),
      ),
    );
    _providerSwap[this] = occupancy;
    return occupancy;
  }

  GpuSwapHost? _hostForLane({
    required String type,
    required String url,
    required String model,
    required String key,
    String kcpps = '',
  }) {
    final kind = localSwapKindFor(backendType: type, apiUrl: url);
    if (kind == null) return null;
    if (kind == LocalSwapKind.koboldProcess) {
      return KoboldProcessHost(
        baseUrl: _koboldService.baseUrl,
        requestedModelPath: model.trim().isEmpty ? null : model,
        requestedKcppsPath: kcpps.trim().isEmpty ? null : kcpps,
        launchedKcppsPath: () => _koboldService.loadedKcppsPath ?? '',
        swapLock: _koboldService.adminSwapLock,
        adminDir: koboldAdminDirFor(_storageService),
        noteLoadedPair: (model, kcpps) => _koboldService.noteAdminLoadedPair(
          modelPath: model,
          kcppsPath: kcpps,
        ),
        stopProcess: _koboldService.stopKobold,
        startProcess: () => ensureManagedBackendIsRunning(
          forGpuSwap: true,
          modelPath: model,
          kcppsPath: kcpps,
        ),
        isProcessRunning: () => _koboldService.isProcessRunning,
        markNotReady: _koboldService.markModelNotReady,
        waitUntilReady: _koboldService.waitUntilReadyAfterSwap,
        admin: HttpGpuSwapHost(
          kind: LocalSwapKind.koboldProcess,
          apiUrl: _koboldService.baseUrl,
          modelId: model,
        ),
      );
    }
    final apiUrl = type == 'omlx' ? kOmlxApiV1 : resolvedLaneApiUrl(type, url);
    return HttpGpuSwapHost(
      kind: kind,
      apiUrl: apiUrl,
      modelId: model,
      apiKey: key,
    );
  }
}

final Expando<GpuSwapOccupancy> _providerSwap = Expando<GpuSwapOccupancy>(
  'fpai.gpuSwap',
);
final Expando<GpuSwapOccupancy> _providerSwapOverride =
    Expando<GpuSwapOccupancy>('fpai.gpuSwapOverride');
final Expando<GpuSwapOccupancy> _providerHeldSwap = Expando<GpuSwapOccupancy>(
  'fpai.gpuSwapHeld',
);
final Expando<int> _providerHeldPins = Expando<int>('fpai.gpuSwapHeldPins');
final Expando<bool> _providerSwapDirty = Expando<bool>('fpai.gpuSwapDirty');
final Expando<LLMService> _providerWorkerOverride = Expando<LLMService>(
  'fpai.workerServiceOverride',
);
