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

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Web adapter for local-backend lifecycle, local-model switching, and the
/// HuggingFace model browser/downloader. Reuses [LLMProvider]'s managed-backend
/// start/stop (which reads the user's stored GPU flags + model — so no GPU-flag
/// wizard is reimplemented here) and [ModelManager]'s search/download queue.
class BackendFacade {
  BackendFacade(this._llm, this._storage, this._models, [this._hardware]);

  final LLMProvider _llm;
  final StorageService _storage;
  final ModelManager _models;
  final HardwareService? _hardware;

  /// Live backend status for the web Models page (read-only).
  Map<String, dynamic> status() {
    final k = _llm.koboldService;
    final engine = _llm.backendManager;
    return {
      'backend': _storage.backendSettings.remoteModelName.isEmpty,
      'isLocal': _llm.isLocal,
      'running': k.isRunning,
      'starting': k.isStarting,
      'modelReady': k.modelReady,
      'statusMessage': k.modelLoadingStatus,
      'loadedModel': _loadedModelName(),
      // The active REMOTE model id (additive; '' on local). loadedModel above
      // is the local .gguf name — the web AI Enhance model picker needs the
      // remote one to label its "current model" default.
      'remoteModel': _storage.backendSettings.remoteModelName,
      // True when the desktop host can only run local models on the CPU, slowly
      // (no AVX2 + no NVIDIA GPU → KoboldCpp's oldpc build, which has no ROCm/
      // Vulkan). Mirrors the desktop warning so the web Models page warns too.
      'cpuOnlyLowPerf': _hardware?.cpuOnlyLowPerf ?? false,
      // Managed-engine acquisition state (additive — first-launch rework):
      // the binary no longer downloads at boot, so the web Models page shows
      // install/progress just like the desktop engine chip.
      'engineInstalled': engine.backendPath != null,
      'engineDownloading': engine.isDownloading,
      'engineProgress': engine.downloadProgress,
      'engineStatusMessage': engine.isDownloading ? engine.statusMessage : '',
      'engineError': engine.error ?? '',
      // Remote live ping (additive). Green "Ready" on the web strip is
      // isReachable, not "a key is saved".
      'isReady': _llm.activeService.isReady,
      'remoteConfigured': _llm.openRouterService.isConfigured,
      'remoteReachable': _llm.openRouterService.isReachable,
      'remoteReachability': _llm.openRouterService.reachability.name,
    };
  }

  String _loadedModelName() {
    final path = _storage.lastUsedModelPath;
    if (path == null || path.isEmpty) return 'No model selected';
    return path.split(RegExp(r'[/\\]')).last;
  }

  /// Restart the managed local backend with the current model + stored flags.
  Future<void> restart() async {
    await _llm.stopAllManagedProcesses();
    await _llm.ensureManagedBackendIsRunning();
  }

  Future<void> stop() => _llm.stopAllManagedProcesses();

  /// List installed local .gguf models (rescans disk first).
  Future<List<Map<String, dynamic>>> localModels() async {
    await _models.refreshModels();
    final current = _storage.lastUsedModelPath;
    return _models.localModels
        .map(
          (m) => {
            'name': m.filename,
            'path': m.path,
            'sizeBytes': m.sizeBytes,
            'quant': m.quantType.name,
            'paramCountB': m.paramCountB,
            'loaded': m.path == current,
          },
        )
        .toList();
  }

  /// Switch the loaded local model and restart the backend so it takes effect.
  /// Reuses the stored launch flags (no GPU config is exposed). Returns false if
  /// the path isn't a known local model.
  Future<bool> switchModel(String path) async {
    final known = _models.localModels.any((m) => m.path == path);
    if (!known) return false;
    await _storage.backendSettings.setLastUsedModelPath(path);
    await restart();
    return true;
  }

  /// Delete an installed local model file. The path MUST be a currently-known
  /// local model — the web server is internet-exposable, so we never accept an
  /// arbitrary filesystem path for deletion. Returns false if it isn't a known
  /// model (treated as 404 by the route).
  Future<bool> deleteModel(String path) async {
    final known = _models.localModels.any((m) => m.path == path);
    if (!known) return false;
    await _models.deleteModel(path);
    return true;
  }

  /// Where installed models live (read-only on the web — a remote client can't
  /// safely point an internet-exposable server at an arbitrary host directory;
  /// changing the folder stays a host-only action in the desktop app).
  Map<String, dynamic> modelsFolder() => {
    'path': _models.modelsPath,
    'custom': _storage.customModelsPath != null,
  };

  // ── HuggingFace browser + downloader ─────────────────────────────────────
  Future<List<Map<String, dynamic>>> searchHf(String query) async {
    final results = await _models.searchHFModels(query);
    return results
        .map(
          (m) => {
            'id': m.id,
            'name': m.name,
            'author': m.author,
            'likes': m.likes,
            'downloads': m.downloads,
            'description': m.description,
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> modelFiles(String repoId) async {
    final files = await _models.getModelFiles(repoId);
    return files
        .map(
          (f) => {
            'filename': f.filename,
            'sizeBytes': f.sizeBytes,
            'repoId': f.repoId,
            'quant': f.quantType.name,
          },
        )
        .toList();
  }

  /// Queue a GGUF file for download. The client supplies repoId + filename; we
  /// re-resolve the typed [HFModelFile] so the download has the correct URL/hash.
  /// Returns the new task id, or null if the file isn't found in the repo.
  Future<String?> queueDownload(String repoId, String filename) async {
    final files = await _models.getModelFiles(repoId);
    for (final f in files) {
      if (f.filename == filename) {
        // Downloading a model IS local intent — fetch the managed engine
        // alongside it (same trigger as the desktop Models page; no-op when
        // installed/downloading/remote).
        unawaited(_llm.backendManager.ensureEngineInstalled());
        return _models.queueDownload(f).id;
      }
    }
    return null;
  }

  /// Explicit engine install/retry from the web Models page — same guarded
  /// background acquisition as everywhere else. Returns the fresh status.
  Future<Map<String, dynamic>> installEngine() async {
    unawaited(_llm.backendManager.ensureEngineInstalled());
    return status();
  }

  bool cancelDownload(String taskId) => _models.cancelDownload(taskId);

  // ── Remote (OpenAI-compatible) model picker ──────────────────────────────
  // Resolve the credentials to probe a remote provider with: the caller may
  // supply an as-yet-unsaved [apiUrl]/[apiKey] (so the Settings page can preview
  // a provider before the user saves), otherwise we fall back to the stored
  // remote settings. Local servers (oMLX / vLLM at localhost) need no key.
  /// Caller-supplied [apiUrl] is the SSRF vector (unsaved Settings preview).
  /// The stored remote URL is whatever the desktop user configured — including
  /// localhost / LAN oMLX — and must stay usable from web.
  ({String url, String key})? _remoteCreds(String? apiUrl, String? apiKey) {
    final b = _storage.backendSettings;
    final override = apiUrl != null && apiUrl.trim().isNotEmpty;
    final url = override ? apiUrl.trim() : b.remoteApiUrl;
    final key = (apiKey != null && apiKey.isNotEmpty)
        ? apiKey
        : b.remoteApiKeyFor(url);
    if (override) {
      final uri = Uri.tryParse(url);
      if (uri == null || !isSafeOutboundUrl(uri)) return null;
    }
    return (url: url, key: key);
  }

  /// Fetch the provider's available models for the Settings model dropdown.
  /// Reuses [OpenRouterService.fetchAvailableModels] via a throwaway client so
  /// the live backend config isn't mutated until the user actually saves.
  /// Returns id + display name + pricing label (empty list on failure/no key).
  Future<List<Map<String, dynamic>>> remoteModels({
    String? apiUrl,
    String? apiKey,
  }) async {
    final c = _remoteCreds(apiUrl, apiKey);
    if (c == null) return [];
    final svc = OpenRouterService(apiUrl: c.url, apiKey: c.key);
    final models = await svc.fetchAvailableModels();
    return models
        .map(
          (m) => {
            'id': m.id,
            'name': m.name,
            'pricing': m.pricingLabel,
            'free': m.isFree,
          },
        )
        .toList();
  }

  /// Poke the provider for [model]'s real reasoning.effort menu (Nano has
  /// none in /models). Returns chips + whether Off is locked.
  ///
  /// oMLX is not a poke: caller-supplied localhost URLs fail the SSRF
  /// gate in [_remoteCreds], and a completions probe would load the model.
  /// Resolve from `/v1/models/status` + the on-disk template instead.
  Future<Map<String, dynamic>> reasoningMenu({
    required String model,
    String? apiUrl,
    String? apiKey,
  }) async {
    if (_llm.activeBackend == BackendType.omlx) {
      await ReasoningSupportResolver.instance.resolveOmlx(
        apiUrl: 'http://localhost:8000/v1',
        modelName: model,
        apiKey: apiKey ?? _storage.backendSettings.remoteApiKey,
      );
      return {
        'efforts': reasoningEffortChipsFor(model),
        'mandatory': reasoningEffortIsMandatory(model),
        'localSupport': ReasoningSupportResolver.instance.peek(model)?.name,
      };
    }
    // Stored localhost / LAN URL (LM Studio). Caller-supplied override is
    // the SSRF vector — use the desktop-configured URL only.
    final stored = _storage.backendSettings.remoteApiUrl;
    if (isLocalRemoteUrl(stored)) {
      await ReasoningSupportResolver.instance.resolveLmStudio(
        apiUrl: stored,
        modelName: model,
        apiKey: apiKey ?? _storage.backendSettings.remoteApiKey,
      );
      return {
        'efforts': reasoningEffortChipsFor(model),
        'mandatory': reasoningEffortIsMandatory(model),
        'localSupport': ReasoningSupportResolver.instance.peek(model)?.name,
      };
    }
    final c = _remoteCreds(apiUrl, apiKey);
    if (c == null) {
      return {
        'efforts': reasoningEffortChipsFor(model),
        'mandatory': reasoningEffortIsMandatory(model),
      };
    }
    await probeReasoningEfforts(model: model, apiUrl: c.url, apiKey: c.key);
    return {
      'efforts': reasoningEffortChipsFor(model),
      'mandatory': reasoningEffortIsMandatory(model),
    };
  }

  /// Test the remote API connection (same credential fallback as
  /// [remoteModels]). Returns the human-readable status from the service.
  Future<String> testRemoteConnection({String? apiUrl, String? apiKey}) async {
    final c = _remoteCreds(apiUrl, apiKey);
    if (c == null) {
      return 'Connection refused: URL is not a public http(s) address.';
    }
    final svc = OpenRouterService(apiUrl: c.url, apiKey: c.key);
    return svc.testConnection();
  }

  bool pauseDownload(String taskId) =>
      _models.downloadManager.pauseDownload(taskId);
  bool resumeDownload(String taskId) =>
      _models.downloadManager.resumeDownload(taskId);
  void pauseAllDownloads() => _models.downloadManager.pauseAll();
  void resumeAllDownloads() => _models.downloadManager.resumeAll();
  void clearCompletedDownloads() => _models.downloadManager.clearCompleted();

  /// Download queue + roll-up for the web to poll while active. Carries every
  /// field the desktop queue shows (size, ETA, error, a ready-made status line)
  /// plus the overall progress/speed/active-count so the page can show one bar.
  Map<String, dynamic> downloadsState() {
    final dm = _models.downloadManager;
    return {
      'downloads': dm.queue
          .map(
            (t) => {
              'id': t.id,
              'filename': t.filename,
              'repoId': t.repoId,
              'state': t.state.name,
              'progress': t.progress,
              'bytesDownloaded': t.bytesDownloaded,
              'totalBytes': t.totalBytes,
              'speedBytesPerSec': t.speedBytesPerSec,
              'etaSeconds': t.etaSeconds,
              'status': t.statusString,
              'errorMessage': t.errorMessage,
            },
          )
          .toList(),
      'overallProgress': dm.overallProgress,
      'overallSpeed': dm.overallSpeed,
      'activeCount': dm.activeDownloads.length,
    };
  }

  // ── Hardware + model recommendations ─────────────────────────────────────
  /// Detected GPU/VRAM/RAM (null when the hardware service isn't wired). Drives
  /// the web Hardware panel + the VRAM-based search recommendations below.
  Map<String, dynamic>? hardware() {
    final h = _hardware?.hardwareInfo;
    if (h == null) return null;
    return {
      'gpuName': h.gpuName,
      'vramMb': h.vramMb,
      'ramMb': h.ramMb,
      'vendor': h.vendor,
      'hasCuda': h.hasCuda,
      'hasRocm': h.hasRocm,
      'hasMetal': h.hasMetal,
      'isSharedMemory': h.isSharedMemory,
      'detecting': _hardware?.isDetecting ?? false,
    };
  }

  Future<Map<String, dynamic>?> redetectHardware() async {
    await _hardware?.detectHardware();
    return hardware();
  }

  /// VRAM-appropriate search queries (reuses ModelManager's existing heuristic),
  /// surfaced as one-tap chips that pre-fill the model search.
  List<String> recommendations() =>
      _models.getRecommendedSearchQueries(_hardware?.hardwareInfo?.vramMb ?? 0);
}
