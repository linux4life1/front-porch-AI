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

part of 'kobold_service.dart';

/// Admin extras, readiness, swap restore, and model-info probes.
extension KoboldServiceAdmin on KoboldService {
  // ── Readiness probe ───────────────────────────────────────────────────
  // Instead of relying solely on log-string matching (which is fragile
  // across KoboldCPP versions), poll /api/extra/version every 5 s.
  // If 200 OK → model is ready.  Log-parsing is kept as a fast-path so
  // the UI can update the moment the log line appears.

  static final RegExp _readyPattern = RegExp(
    r'(please connect|server listen|starting server|ready to)',
    caseSensitive: false,
  );
  static final RegExp _loadModelPattern = RegExp(
    r'loading (the )?model',
    caseSensitive: false,
  );
  static final RegExp _loadFilePattern = RegExp(
    r'loading (hf|gguf|safetensors|model file)',
    caseSensitive: false,
  );
  static final RegExp _mappingPattern = RegExp(
    r'(mapping model|ggml_backend|allocat)',
    caseSensitive: false,
  );
  static final RegExp _warmupPattern = RegExp(
    r'warm(ing)? up',
    caseSensitive: false,
  );

  /// The ONE "the model is up" transition. Three call sites used to inline
  /// the same five statements (the readiness poll, the log fast-path, and the
  /// hot-restart reconnect), which is how the reconnect path quietly ended up
  /// missing `_stopReadinessProbe()`. Folded into one so anything that must
  /// happen on model-ready — like arming the system-role probe — happens on
  /// EVERY path by construction.
  void _markModelReady() {
    _modelLoadingStatus = '';
    _modelReady = true;
    _stopReadinessProbe();
    _idleTouch();
    // Resolve the probe key and arm the measurement in the idle window right
    // after load — the only place it is cheap. See [KoboldSystemRole].
    //
    // BEFORE notifyListeners, not after: a listener woken by that call can
    // reach straight back in and generate, and until this line runs the key
    // still names the PREVIOUS model — so a notify-first ordering leaves a
    // window where the workaround is decided from a stale verdict.
    _armedProbe = _systemRole.arm(
      baseUrl: _baseUrl,
      backendName: backendName,
      storage: _storageService,
      modelPath: requestModel,
      runExclusive: _runSerialized,
      log: _addLog,
    );
    // A start comes up with its config noted; a swap is confirmed later, by
    // [noteResident].
    if ((_residentKey ?? '').isNotEmpty) _residentGeneration++;
    notify();
  }

  /// Test hooks: the model-ready transition that only a real process would
  /// otherwise drive — returning the measurement it armed — and the key it
  /// resolved.
  @visibleForTesting
  Future<void> debugMarkModelReady() {
    _markModelReady();
    return _armedProbe;
  }

  /// Admin unload leaves the process up. Clear ready so swap restore cannot
  /// treat a stale [isReady] as a loaded model. Keep [_loadedKcppsPath]:
  /// last start or last [noteAdminLoadedPair] `--config`. Stop the probe
  /// so a late startKobold tick cannot flip ready during unload.
  void markModelNotReady() => _clearReady('Unloading model...');

  /// A reload was accepted: the old model may answer for a moment longer,
  /// so nothing is ready until the new one is. [status] says what is
  /// loading; the unload wording would be wrong here. A model unloaded for
  /// being idle is not loaded back after it: this load replaces it.
  void markModelLoading(String status) {
    _idle
      ..unloaded = null
      ..failed = null;
    _clearReady(status);
  }

  void _clearReady(String status) {
    _stopReadinessProbe();
    _idleTouch();
    _modelReady = false;
    _loadedModelPath = null;
    _residentKey = null;
    _loadGeneration++;
    _modelLoadingStatus = status;
    notify();
  }

  /// In-process `reload_config` loaded this pair. Stamp paths only.
  /// Version 200 is HTTP-up, not generation-ready — [waitUntilReadyAfterSwap]
  /// probes a tiny completion before [isReady] / evals / mouth generate.
  void noteAdminLoadedPair({String? modelPath, String? kcppsPath}) {
    final model = modelPath?.trim() ?? '';
    _loadGeneration++;
    if (model.isNotEmpty) _loadedModelPath = model;
    if (kcppsPath != null) {
      final kcpps = kcppsPath.trim();
      _loadedKcppsPath = kcpps.isEmpty ? null : kcpps;
    }
  }

  /// Whether the config with this content is loaded and ready: the one
  /// answer every swap asks for, so a swap that is not needed is not sent.
  bool isResident(String key) => _modelReady && _residentKey == key;

  /// The model file this engine's answers come from, when that is known: the
  /// one a start loaded or a swap was read back as running, or the one an
  /// idle unload will load back. [loadedModelPath] is only what the engine
  /// was told to load; this is what it is known to run. Null while the engine
  /// is not running, is loading, or went back to a model nobody has named
  /// after a reload that did not load what it asked for.
  String? get answeringModelPath {
    if (!_isRunning) return null;
    final unloaded = _idle.unloaded;
    if (unloaded != null) return unloaded.model;
    if (!_modelReady || (_residentKey ?? '').isEmpty) return null;
    return _loadedModelPath;
  }

  /// A swap finished loading the config with this content ('' when what
  /// loaded is not known). Either way something is loaded again.
  void noteResident(String key) {
    final changed = _residentKey != key;
    _residentKey = key;
    if (key.isNotEmpty && _modelReady) _residentGeneration++;
    _idleTouch();
    // Loaded again after an idle unload: every status shows it now.
    final loadedBack = _idle.unloaded != null;
    _idle.unloaded = null;
    // What the engine is known to run changed: everything that names the
    // model (the tool-calling pill's identity) answers differently now.
    if (loadedBack || changed) notify();
  }

  /// The model a request goes to: the one loaded (a helper or story model
  /// after a swap), else chat's. Its template decides the thinking cap and
  /// whether system messages are folded into the user turn.
  String? get requestModel =>
      _loadedModelPath ?? _storageService.backendSettings.lastUsedModelPath;

  /// A reload did not load what it asked for: the pair noted for it is not
  /// what runs.
  void forgetAdminLoadedPair() {
    _loadedModelPath = null;
    _loadedKcppsPath = null;
    _loadGeneration++;
  }

  /// Says in the engine log and on the status line that a reload did not
  /// load what it asked for.
  void noteReloadFailed(String message) {
    _addLog(message);
    showSwapStep(message);
  }

  /// Once the launch of [generation] is ready, chat's prompts are held to
  /// the context the engine really runs: a preset may set none, and then
  /// KoboldCpp runs its own default. A swap or stop before then cancels it.
  void _followLaunchContext(int generation) {
    late final VoidCallback check;
    check = () {
      if (generation != _loadGeneration || !_isRunning) {
        removeListener(check);
      } else if (_modelReady) {
        removeListener(check);
        unawaited(_readLaunchContext(generation));
      }
    };
    addListener(check);
  }

  Future<void> _readLaunchContext(int generation) async {
    final context = await koboldEngineContext(_baseUrl);
    if (context != null && generation == _loadGeneration) {
      _storageService.backendSettings.setEngineContextSize(context);
    }
  }

  /// Says on the status line what a swap is doing.
  void showSwapStep(String step) {
    _modelLoadingStatus = step;
    notify();
  }

  /// Waits for an admin reload that was just asked for to really happen: a
  /// new model process, and that one generating. The reload call answers
  /// before the engine acts, and the old model answers for a moment more,
  /// so "ready" alone would be the old model. [since]: when the reload was
  /// asked for (see [waitForKoboldReload]).
  Future<void> waitForSwap({required Duration timeout, DateTime? since}) async {
    await waitForKoboldReload(
      uptime: () => koboldEngineUptime(_baseUrl),
      ready: () => probeKoboldGenerationReady(baseUrl: _baseUrl),
      timeout: timeout,
      since: since,
    );
    if (!_modelReady) _markModelReady();
  }

  /// Waits until an unload that was just asked for has happened: a new
  /// model process that reports nothing loaded. [since]: when the unload
  /// was asked for (see [waitForKoboldReload]).
  Future<void> waitForUnload({DateTime? since}) => waitForKoboldReload(
    uptime: () => koboldEngineUptime(_baseUrl),
    ready: () async => await koboldEngineModel(_baseUrl) == 'inactive',
    timeout: const Duration(seconds: 60),
    since: since,
  );

  /// Poll a tiny `/v1/chat/completions` until the swapped GGUF generates.
  /// Version 200 alone is not enough (empty streams / 0-token pings).
  Future<void> waitUntilReadyAfterSwap({
    required int attempts,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    final n = attempts < 1 ? 1 : attempts;
    for (var i = 0; i < n; i++) {
      final ready = await probeKoboldGenerationReady(baseUrl: _baseUrl);
      if (ready) {
        if (!_modelReady) _markModelReady();
        return;
      }
      if (i < n - 1 && delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    }
    throw StateError('Kobold was not generation-ready after GPU swap restore');
  }

  /// Test hook: pretend the managed process is up (admin swap leaves it up).
  @visibleForTesting
  void debugMarkProcessRunning() {
    _isRunning = true;
  }

  @visibleForTesting
  String get systemRoleIdentity => _systemRole.identity;

  void _startReadinessProbe() {
    _stopReadinessProbe(); // Cancel any prior timer.
    _readinessProbe = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _probeVersion(),
    );
  }

  void _stopReadinessProbe() {
    _readinessProbe?.cancel();
    _readinessProbe = null;
  }

  Future<void> _probeVersion() async {
    // Only the process this service runs is waited for. One that exited on
    // its own leaves why on the status line until the next Start or Stop,
    // and whatever answers on its port now is not it.
    final engine = _process;
    if (_modelReady || engine == null) {
      _stopReadinessProbe();
      return;
    }
    final client = http.Client();
    try {
      final uri = Uri.parse('$_baseUrl/api/extra/version');
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        // It may have exited, or been replaced, while the answer was coming.
        if (!identical(_process, engine)) return;
        debugPrint('[KoboldService] Readiness probe: 200 OK — model ready.');
        _markModelReady();
        await _syncVersionFromResponse(response);
      }
    } catch (_) {
      // Not ready yet — silently retry on the next tick.
    } finally {
      client.close();
    }
  }

  /// Parse KoboldCPP process output to determine model loading status.
  /// Kept as a secondary fast-path alongside the periodic readiness probe.
  void _parseLoadingStatus(String data) {
    // Unloaded for being idle, the engine's empty model process prints
    // "Please connect…" too; and a load back owns the status line.
    if (_idle.unloaded != null) return;
    // Model is ready when server starts listening (fast-path).
    if (_readyPattern.hasMatch(data)) {
      _markModelReady();
      return;
    }

    // Track loading phases from KoboldCPP output — but only before the model
    // has finished loading. After _modelReady is true, ignore these patterns
    // (KoboldCPP can output "warm up" during normal operation, e.g. large prefills).
    if (!_modelReady) {
      if (_loadModelPattern.hasMatch(data)) {
        _modelLoadingStatus = 'Loading model into device memory...';
        notify();
      } else if (_loadFilePattern.hasMatch(data)) {
        _modelLoadingStatus = 'Loading model file...';
        notify();
      } else if (_mappingPattern.hasMatch(data)) {
        _modelLoadingStatus = 'Mapping model to memory...';
        notify();
      } else if (_warmupPattern.hasMatch(data)) {
        _modelLoadingStatus = 'Warming up model...';
        notify();
      }
    }
  }

  Future<void> _syncVersionFromResponse(http.Response response) async {
    if (_executablePath == null) return;
    try {
      final v = jsonDecode(response.body)['version'] as String?;
      if (v != null && v.isNotEmpty) {
        await KoboldBinaryVersion.write(
          path.dirname(_executablePath!),
          version: v,
          size: File(_executablePath!).lengthSync(),
        );
      }
    } catch (_) {}
  }

  /// Poll KoboldCPP's /api/extra/perf endpoint for real-time performance data.
  /// Returns a map with fields like last_process_speed, last_eval_speed,
  /// last_input_count, idle (0=busy, 1=idle), queue, etc.
  /// Returns null if the endpoint is unreachable or the response is invalid.
  Future<Map<String, dynamic>?> fetchPerf() async {
    final client = http.Client();
    try {
      final uri = Uri.parse('$_baseUrl/api/extra/perf');
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      // Connection refused / timeout — server unreachable
    } finally {
      client.close();
    }
    return null;
  }

  /// Count tokens using the loaded model's actual tokenizer.
  /// Falls back to chars/4 estimate if the endpoint is unavailable.
  /// A model unloaded for being idle is loaded back first: with no model,
  /// KoboldCpp's tokenizer has nothing to count with, and callers keep the
  /// answer.
  Future<int> countTokens(String text) async {
    if (text.isEmpty) return 0;
    try {
      await _idleRequestStart();
      final uri = Uri.parse('$_baseUrl/api/extra/tokencount');
      final client = http.Client();
      try {
        final response = await client
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'prompt': text}),
            )
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return (data['value'] as num?)?.toInt() ?? (text.length / 4).ceil();
        }
      } finally {
        client.close();
      }
    } on Object catch (e) {
      debugPrint('[Kobold] token count falls back to an estimate: $e');
    } finally {
      _idleRequestEnd();
    }
    return (text.length / 4).ceil();
  }
}
