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
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/live_gen_progress.dart';
import 'package:front_porch_ai/services/llm_provider/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router/open_router.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/remote_reachability.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/worker_backend.dart';
import 'package:front_porch_ai/services/worker_gpu_swap.dart';
import 'package:front_porch_ai/services/xai/xai.dart';

export 'package:front_porch_ai/services/llm_provider/llm_provider.dart'
    show
        BackendType,
        LLMProviderLaneApi,
        LaneHost,
        SamplerKnob,
        kKoboldChatRole,
        kKoboldTrialRole,
        kKoboldWorkerRole,
        remoteProviderLabel,
        samplerKnobsFor;

/// Manages switching between LLM backends (local KoboldCPP, remote APIs).
///
/// Sits between ChatService and the actual backend implementations.
/// Listens to StorageService for config changes and hot-swaps the active service.
class LLMProvider extends ChangeNotifier {
  final KoboldService _koboldService;
  final OpenRouterService _openRouterService;
  final StorageService _storageService;
  final BackendManager _backendManager;

  BackendType _activeBackend = BackendType.kobold;

  /// Unofficial SuperGrok sign-in; its token rides every api.x.ai request
  /// through [BackendSettings.bearerOverlay].
  late final SuperGrokAuth superGrok = SuperGrokAuth.inPrefs(
    () => _storageService.backendSettings.prefs,
    _storageService.backendSettings.k('xai_supergrok_session'),
  );

  /// The worker lane's own remote client and eval identity.
  late final WorkerLaneConfig _worker = WorkerLaneConfig(
    storage: _storageService,
    kobold: _koboldService,
  );

  /// One shared struct per non-Kobold source; [activeLiveProgress] resolves
  /// which one the UIs read.
  late final LiveStatusSources _live = LiveStatusSources(
    isGenerationActive: () => isGenerationActive?.call() ?? false,
  );

  late final ManagedKoboldLauncher _launcher = ManagedKoboldLauncher(
    kobold: _koboldService,
    storage: _storageService,
    backendManager: _backendManager,
    anyProcessRunning: () => hasAnyManagedProcessRunning,
    workerRefusedDualLocal: () => workerRefusedDualLocal,
    onChanged: _onServiceChanged,
  );

  late final LaneHostFactory _hosts = LaneHostFactory(
    kobold: _koboldService,
    storage: _storageService,
    backendManager: _backendManager,
    ensureKobold: _launcher.ensure,
  );

  late final WorkerLaneSwap _lane = WorkerLaneSwap(
    pairSupported: () =>
        workerConfigured && savedPairSupportsGpuSwap(_storageService),
    build: _hosts.workerOccupancy,
  );

  late final KoboldChatReload _reload = KoboldChatReload(
    kobold: _koboldService,
    storage: _storageService,
    hosts: _hosts,
    ensureKobold: _launcher.ensure,
  );

  late final StoryLaneHosts _storyLanes = StoryLaneHosts(
    kobold: _koboldService,
    storage: _storageService,
    hosts: _hosts,
    koboldLaunchPath: _launcher.effectiveLaunchPath,
  );

  late final LlmProviderParts _parts;

  LLMService? _workerOverride;

  /// Set from main.dart wiring (mirrors the setX style): lets the status
  /// sources gate their work on ChatService.isGenerating without this class
  /// depending on ChatService.
  bool Function()? isGenerationActive;

  /// The live progress source for the ACTIVE backend, or null when none can
  /// exist (plain remote APIs — providers expose no prefill data).
  LiveGenProgress? get activeLiveProgress =>
      _live.progressFor(_activeBackend, kobold: _koboldService.liveProgress);

  /// Start/stop the per-backend live-status sources for the current backend
  /// + URL. Called on backend switches; safe to call repeatedly.
  void _syncLiveStatusSources() => _live.sync(
    active: _activeBackend,
    runOmlx: shouldRunOmlxPoller(
      mouthType: _storageService.backendSettings.backendType,
      workerType: _storageService.workerBackendType,
      pairAllowed: !workerRefusedDualLocal,
    ),
    mouthUrl: _openRouterService.apiUrl,
    workerUrl: _storageService.workerRemoteApiUrl,
  );

  BackendType get activeBackend => _activeBackend;
  LLMService get activeService {
    switch (_activeBackend) {
      case BackendType.kobold:
        return _koboldService;
      case BackendType.openRouter:
      case BackendType.omlx:
        return _openRouterService;
    }
  }

  /// Worker picker type, or null when the worker is off.
  BackendType? get workerBackend =>
      workerBackendTypeFrom(_storageService.workerBackendType);

  bool get workerConfigured =>
      !workerBackendIsOff(_storageService.workerBackendType);

  bool get workerRefusedDualLocal =>
      workerConfigured &&
      !workerPairAllowed(
        mouthType: _storageService.backendSettings.backendType,
        mouthUrl: _storageService.backendSettings.remoteApiUrl,
        workerType: _storageService.workerBackendType,
        workerUrl: _storageService.workerRemoteApiUrl,
        gpuSwapAvailable: workerGpuSwapAvailable,
      );

  /// Side-lane service when the worker is on and the pair is allowed.
  LLMService? get workerService {
    if (!workerConfigured || workerRefusedDualLocal) return null;
    return _workerOverride ??
        switch (workerBackend) {
          BackendType.kobold => _koboldService,
          BackendType.openRouter || BackendType.omlx => _worker.remote,
          null => null,
        };
  }

  /// Evals / clerk / journal / growth. Mouth stays [activeService].
  LLMService get sideLaneService => workerService ?? activeService;

  bool get sideLaneIsKobold => sideLaneService is KoboldService;

  /// Plain-English reason the worker host is picked but not ready.
  String? get workerUnreadyMessage {
    if (!workerConfigured || workerRefusedDualLocal) return null;
    final svc = workerService;
    if (svc == null || svc.isReady) return null;
    return workerLaneUnreadyMessage(_storageService.workerBackendType);
  }

  OpenRouterService get workerRemoteService => _worker.remote;

  String get workerEvalIdentity => workerEvalIdentityNamed();

  /// [workerEvalIdentity] with a local helper's model named by [modelKey]
  /// (what the engine runs, for a helper the lane does not swap in) instead of
  /// by the file the helper setting names.
  String workerEvalIdentityNamed({String? modelKey}) => _worker.evalIdentity(
    service: workerService ?? _worker.remote,
    modelKey: modelKey,
  );

  @visibleForTesting
  bool get debugOmlxPollerStarted => _live.omlxStarted;

  @visibleForTesting
  set debugGpuSwap(GpuSwapOccupancy? occupancy) => _lane.override = occupancy;

  @visibleForTesting
  GpuSwapOccupancy? get debugGpuSwap => _lane.current;

  /// Production occupancy only. Mid-hold rebuild must not write here.
  @visibleForTesting
  GpuSwapOccupancy? get debugGpuSwapExpando => _lane.swap;

  @visibleForTesting
  set debugWorkerService(LLMService? service) => _workerOverride = service;

  /// Whether the active backend is the local KoboldCpp instance (native or
  /// launched from a .kcpps preset). Gates the local niceties — real
  /// tokenizer counts and prefill perf metrics — and sequential eval dispatch
  /// (one KoboldCpp generation slot).
  bool get isLocal => _activeBackend == BackendType.kobold;

  /// Whether the chat model runs on the user's own machine or network:
  /// KoboldCpp, oMLX, or a Custom / LM Studio URL at a local address
  /// (127.0.0.1 is a loopback, so it is local). Not [isLocal], which means
  /// the managed KoboldCpp only.
  bool get modelIsLocal =>
      evalLaneIsHomeNetwork(_activeBackend.name, _openRouterService.apiUrl);

  /// [modelIsLocal] for the helper model. One-Shot Auto reads it: a helper
  /// on the home network stays multi-call. It answers only while
  /// [workerService] is on. The pair gate is [backendLaneIsLocal].
  bool get workerModelIsLocal {
    final type = _storageService.workerBackendType;
    final url = _storageService.workerRemoteApiUrl;
    return evalLaneIsHomeNetwork(type, resolvedLaneApiUrl(type, url));
  }

  /// Whether the active backend manages a local subprocess.
  bool get hasManagedProcess => _activeBackend == BackendType.kobold;

  /// Composer placeholder connection. Local GGUF load/swap flips
  /// [LLMService.isReady] and must not restyle the input — process-up
  /// (or still starting) is enough. Remote keeps [LLMService.isReady].
  bool get composerConnectionReady {
    if (hasManagedProcess) {
      return _koboldService.isProcessRunning || _koboldService.isStarting;
    }
    return activeService.isReady;
  }

  /// Resolve the service a model-pickable generation feature (the AI
  /// character creator, AI Enhance) should run against, or null when nothing
  /// is ready. A managed local backend generates with its loaded model (the
  /// per-run "model choice" for local IS backend management, so there is
  /// nothing to pick); on a remote backend, a [selectedModelId] different
  /// from the active model gets an ad-hoc [OpenRouterService] against the
  /// configured credentials — the app's active model is left untouched.
  /// Extracted from the creator's `_resolveLlmService` so Enhance and the
  /// wizard share one implementation.
  LLMService? serviceForModel(String selectedModelId) {
    if (hasManagedProcess) {
      final svc = activeService;
      return svc.isReady ? svc : null;
    }
    if (selectedModelId.isNotEmpty &&
        selectedModelId != _openRouterService.modelName) {
      // oMLX is a fixed local URL. Using remoteApiUrl here sent Enhance
      // at OpenRouter (or whatever Remote API is set to) with an MLX
      // model id — or, when that URL happened to be oMLX, still worked
      // only by accident. Same literal LLMProvider configures on sync.
      return OpenRouterService(
        apiUrl: _activeBackend == BackendType.omlx
            ? kOmlxApiUrl
            : _storageService.backendSettings.remoteApiUrl,
        apiKey: _storageService.backendSettings.remoteApiKey,
        modelName: selectedModelId,
      );
    }
    final active = activeService;
    return active.isReady ? active : null;
  }

  /// True when the managed process is currently running.
  bool get hasAnyManagedProcessRunning => _koboldService.isRunning;

  /// Start Kobold on chat entry, or inside a GPU swap (`forGpuSwap`).
  /// [modelPath] / [kcppsPath] are the GGUF + `.kcpps` pair to load on swap;
  /// omitted = Models-tab mouth pair. Mouth restore keeps the Models-tab
  /// `--mmproj`; a worker/evals pair never gets a projector. Says why when
  /// the start was refused; null when nothing needed starting.
  Future<KoboldLaunchResult?> ensureManagedBackendIsRunning({
    bool forGpuSwap = false,
    String? modelPath,
    String? kcppsPath,
  }) => _launcher.ensure(
    forGpuSwap: forGpuSwap,
    modelPath: modelPath,
    kcppsPath: kcppsPath,
  );

  /// Chat's new preset or model into the running KoboldCpp, live. Says why
  /// when it was not loaded; null when there is nothing to report.
  Future<KoboldLaunchResult?> reloadChatKobold() => _reload.reloadChat();

  /// Loads a timing trial's [config] into the running KoboldCpp, staged as
  /// [name]. True when it is what runs afterwards; throws
  /// [KoboldPresetProblem] for a config the app will not start.
  Future<bool> loadKoboldTrial(String name, Map<String, dynamic> config) =>
      _reload.loadTrial(name, config);

  /// The host for a story lane, or null when it cannot be built (no model).
  LaneHost? laneHost({
    required String type,
    required String url,
    required String model,
    String kcpps = '',
  }) => _storyLanes.host(type: type, url: url, model: model, kcpps: kcpps);

  /// Convenience getters for the underlying services (for UI that needs specifics).
  KoboldService get koboldService => _koboldService;
  OpenRouterService get openRouterService => _openRouterService;
  BackendManager get backendManager => _backendManager;

  LLMProvider(
    this._koboldService,
    this._openRouterService,
    this._storageService,
    this._backendManager,
  ) {
    _parts = LlmProviderParts(lane: _lane, launcher: _launcher)..attachTo(this);
    _storageService.backendSettings.bearerOverlay = superGrok.bearerFor;
    superGrok.addListener(_syncFromStorage);
    // Prefs are still null until storage init binds them; loading earlier
    // reads no session and every launch looks signed out.
    unawaited(_storageService.initialized.then((_) => superGrok.load()));
    _syncFromStorage();
    _storageService.addListener(_syncFromStorage);
    _koboldService.addListener(_onServiceChanged);
    _parts.speedTest = KoboldSpeedTestWiring(
      kobold: _koboldService,
      storage: _storageService,
      backendManager: _backendManager,
      hosts: _hosts,
      hasManagedProcess: () => hasManagedProcess,
    ).build(loadTrial: loadKoboldTrial, reloadChat: reloadChatKobold);
  }

  @override
  void dispose() {
    _storageService.removeListener(_syncFromStorage);
    _koboldService.removeListener(_onServiceChanged);
    superGrok.removeListener(_syncFromStorage);
    final backend = _storageService.backendSettings;
    if (backend.bearerOverlay == superGrok.bearerFor) {
      backend.bearerOverlay = null;
    }
    superGrok.dispose();
    _live.stop();
    final occupancy = _lane.current;
    if (occupancy != null) unawaited(occupancy.ensureMouth());
    super.dispose();
  }

  void _onServiceChanged() {
    notifyListeners();
  }

  void _syncFromStorage() {
    final typeStr = _storageService.backendSettings.backendType;
    final newType = backendTypeFromStored(typeStr);
    final cfgChanged = _configureMouth(newType);
    _maybePingRemote(newType, configChanged: cfgChanged);
    debugPrint(
      '[LLMProvider] Synced from storage: backend=$typeStr, URL=${_storageService.backendSettings.remoteApiUrl}',
    );

    // Drop cached vision/tool-calling verdicts whenever the model identity the
    // app is pointed at changes — backend type, remote URL/model, or active
    // preset. Otherwise a switch from a vision model to a text-only one on the
    // same endpoint keeps reporting the old "supported" verdict, and the photo
    // attach path trusts it. (Local-model verdicts are re-derived from config
    // each call, so this mainly guards the remote /models-metadata cache.)
    final identity =
        '$typeStr|${_storageService.backendSettings.remoteApiUrl}|'
        '${_storageService.backendSettings.remoteModelName}|${_storageService.backendSettings.activeKcppsPath}|'
        '${_storageService.backendSettings.lastUsedModelPath}';
    if (identity != _lastModelIdentity) {
      _lastModelIdentity = identity;
      VisionSupportResolver.instance.clear();
      // URL/model changes without a backend-type flip must also re-evaluate
      // the live-status sources (e.g. the remote URL edited from a cloud
      // host to a localhost LM Studio, or an oMLX port change) — review
      // finding: type-only syncing left the streamer attached/detached
      // against the wrong server.
      _syncLiveStatusSources();
      _kickLocalThinkingResolve(newType);
    }

    var notified = false;
    if (newType != _activeBackend) {
      _activeBackend = newType;
      _syncLiveStatusSources();
      notifyListeners();
      notified = true;
    }
    if (_syncWorkerFromStorage() && !notified) notifyListeners();
  }

  /// Last model-identity string synced from storage; used to clear stale
  /// capability verdicts on change (see [_syncFromStorage]).
  String? _lastModelIdentity;

  /// Point the mouth's OpenAI-compatible client at [type]'s address: oMLX's
  /// fixed localhost URL, else the saved remote URL. True when it changed.
  bool _configureMouth(BackendType type) {
    final b = _storageService.backendSettings;
    return _openRouterService.configure(
      apiUrl: type == BackendType.omlx ? kOmlxApiUrl : b.remoteApiUrl,
      apiKey: b.remoteApiKey,
      modelName: b.remoteModelName,
    );
  }

  /// Point the worker's remote client at the saved worker host/model.
  /// Returns true when the pair identity changed.
  bool _syncWorkerFromStorage() {
    if (!_worker.sync()) return false;
    _syncLiveStatusSources();
    _lane.rebuild();
    return true;
  }

  void _kickLocalThinkingResolve(BackendType type) => kickLocalThinkingResolve(
    type,
    settings: _storageService.backendSettings,
    openAiUrl: _openRouterService.apiUrl,
  );

  /// Live `GET /models` when the remote backend is (or becomes) active.
  /// Skipped under `flutter test` so constructing a provider never hits
  /// the network; tests that care call [OpenRouterService.refreshReachability].
  void _maybePingRemote(BackendType type, {required bool configChanged}) {
    if (kSkipRemoteAutoPing) return;
    if (!isRemoteBackendType(type)) return;
    if (!configChanged && type == _activeBackend) return;
    unawaited(_openRouterService.refreshReachability());
  }

  /// Switch the active backend and persist the choice.
  /// Does NOT start or stop any processes — that is handled by the caller (UI).
  Future<void> setActiveBackend(BackendType type) async {
    if (type == _activeBackend) return;

    _activeBackend = type;
    await _storageService.backendSettings.setBackendType(type.name);

    // oMLX is a fixed localhost URL. Nano/OpenRouter/LM Studio use the
    // parked remoteApiUrl — must reconfigure even when that URL did not
    // change (oMLX never writes remoteApiUrl, so setRemoteApiUrl is a
    // no-op and Waifu would keep hitting oMLX).
    if (type != BackendType.kobold) _configureMouth(type);

    _syncLiveStatusSources();
    _maybePingRemote(type, configChanged: true);
    _kickLocalThinkingResolve(type);
    notifyListeners();
  }

  /// Stop the managed KoboldCpp process if it is running, or call off a start
  /// that is still being prepared (nothing is spawned then).
  Future<void> stopAllManagedProcesses() async {
    if (_koboldService.isRunning || _koboldService.isStarting) {
      await _koboldService.stopKobold();
    }
  }
}
