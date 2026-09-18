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
    _modelJustLoaded = true;
    _stopReadinessProbe();
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
      runExclusive: _runSerialized,
      log: _addLog,
    );
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
  void markModelNotReady() {
    _stopReadinessProbe();
    _modelReady = false;
    _loadedModelPath = null;
    _modelLoadingStatus = 'Unloading model...';
    notify();
  }

  /// In-process `reload_config` loaded this pair. Stamp paths only.
  /// Version 200 is HTTP-up, not generation-ready — [waitUntilReadyAfterSwap]
  /// probes a tiny completion before [isReady] / evals / mouth generate.
  Future<void> noteAdminLoadedPair({
    String? modelPath,
    String? kcppsPath,
  }) async {
    final model = modelPath?.trim() ?? '';
    if (model.isNotEmpty) _loadedModelPath = model;
    if (kcppsPath != null) {
      final kcpps = kcppsPath.trim();
      _loadedKcppsPath = kcpps.isEmpty ? null : kcpps;
    }
  }

  /// Poll a tiny `/v1/chat/completions` until the swapped GGUF generates.
  /// Version 200 alone is not enough (empty streams / 0-token pings).
  Future<void> waitUntilReadyAfterSwap({
    int attempts = 40,
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
    if (_modelReady) {
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

  /// Regex matching KoboldCPP per-token / per-batch progress messages.
  /// These are purely informational counters that fire for every token and

  bool get isProcessAlive => _process != null && _isRunning;

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
  Future<int> countTokens(String text) async {
    if (text.isEmpty) return 0;
    try {
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
    } catch (_) {
      // Endpoint unavailable — fall back to estimate
    }
    return (text.length / 4).ceil();
  }
}
