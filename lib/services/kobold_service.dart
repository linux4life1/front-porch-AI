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
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/kobold_binary_version.dart';
import 'package:front_porch_ai/services/kobold_launch_args.dart';
import 'package:front_porch_ai/services/kobold_process_control.dart';
import 'package:front_porch_ai/services/kobold_system_role.dart';
import 'package:front_porch_ai/services/live_gen_progress.dart';
import 'package:front_porch_ai/services/model_file_check.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/openai_chat_stream.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';
import 'package:path/path.dart' as path;

class KoboldService extends ChangeNotifier
    with WidgetsBindingObserver
    implements LLMService {
  final StorageService _storageService;

  /// See [KoboldSystemRole]: resolved once per model load, read once per
  /// generation, forgotten on stop.
  final KoboldSystemRole _systemRole;

  Process? _process;
  bool _isRunning = false;
  bool _isStarting = false;
  final List<String> _logs = [];
  String _modelLoadingStatus = '';
  bool _modelReady = false;

  /// One-shot flag for UI notifications (e.g. snackbar). Set to true when the
  /// model finishes loading, consumed once by the home page. Unlike _modelReady,
  /// this is reset after reading so it only triggers the notification once.
  bool _modelJustLoaded = false;
  String? _executablePath;
  Timer? _readinessProbe;

  /// Ground-truth per-request progress parsed from the managed process's own
  /// console output (see live_gen_progress.dart) — what the status bar
  /// shows instead of a black box. Covers WHATEVER request Kobold is working
  /// on, including queued background passes.
  final LiveGenProgress liveProgress = LiveGenProgress();
  DateTime _lastLiveNotify = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isRunning => _isRunning;
  bool get isStarting => _isStarting;
  List<String> get logs => List.unmodifiable(_logs);
  String get modelLoadingStatus => _modelLoadingStatus;
  bool get modelReady => _modelReady;

  /// Feed a console chunk to [liveProgress]; notify at most every 150ms
  /// (Generating lines arrive once per token).
  void _ingestLiveProgress(String data) {
    if (!liveProgress.ingest(data)) return;
    final now = DateTime.now();
    if (now.difference(_lastLiveNotify).inMilliseconds >= 150) {
      _lastLiveNotify = now;
      notifyListeners();
    }
  }

  /// Consume the one-shot "model just loaded" notification flag.
  /// Returns true exactly once after each model load, for UI notifications
  /// (e.g. snackbar). Does NOT affect [isReady] or [modelReady].
  bool consumeModelReady() {
    if (_modelJustLoaded) {
      _modelJustLoaded = false;
      return true;
    }
    return false;
  }

  String _baseUrl = 'http://127.0.0.1:5001';
  String get baseUrl => _baseUrl;
  http.Client? _activeClient;

  /// Tracks the completion of the current generation stream.
  /// Used by waitForIdle() to serialize requests without aborting in-flight ones.
  Future<void>? _pendingRequest;

  // LLMService interface
  @override
  /// True only when the process is running AND the model is fully loaded.
  /// Use [isProcessRunning] if you only need to know if the process is alive.
  bool get isReady => _isRunning && _modelReady;

  /// True if the KoboldCPP process has been started (model may still be loading).
  bool get isProcessRunning => _isRunning;
  @override
  String get backendName => 'KoboldCPP';

  /// The `--jinja` system-message workaround's wiring (arm / read / forget).
  /// [systemRoleProbe] is a test seam: production takes the app-wide probe.
  KoboldService(this._storageService, {SystemRoleProbe? systemRoleProbe})
    : _systemRole = KoboldSystemRole(probe: systemRoleProbe) {
    _purgeLogs();
    WidgetsBinding.instance.addObserver(this);
    // Best-effort fast path: probe on construction so hot restarts pick up
    // existing KoboldCPP instances before the first eval call.
    reconnectIfAlive();
  }

  /// Probe the KoboldCPP server. If it responds, mark the service as running
  /// and model-ready so hot restarts and app reconnections don't silently skip evals.
  /// Uses /api/extra/version which is always present in KoboldCPP.
  ///
  /// IMPORTANT: This deliberately does NOT reconnect if we have no _process
  /// reference, because that means the server was started by a previous app
  /// instance (zombie after update). In that case it kills the orphan instead.
  Future<void> reconnectIfAlive() async {
    if (_isRunning) return; // Already known-good — skip.
    final client = http.Client();
    try {
      final uri = Uri.parse('$_baseUrl/api/extra/version');
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        if (_process != null) {
          // We started this process — safe to reconnect (hot restart path).
          debugPrint(
            '[KoboldService] Reconnected to existing KoboldCPP instance.',
          );
          _isRunning = true;
          _markModelReady();
          await _syncVersionFromResponse(response);
        } else {
          // Orphaned zombie from a previous app instance (e.g. after update).
          // Kill it so we can start fresh on the same port — but ONLY when the
          // managed local backend is the selected one. killOrphanedKobold-
          // Processes sweeps the whole MACHINE by image name, and this probe
          // runs from the constructor on every launch, so on Remote API / oMLX
          // (pointing at 127.0.0.1:5001 without an API key is a supported
          // setup) it would SIGKILL a server the app neither started nor is
          // about to replace. Same gate the other backend-owning paths use
          // (backend_manager.dart, setup_service.dart).
          await _storageService.initialized;
          final backendType = _storageService.backendType;
          if (backendType == 'openRouter' || backendType == 'omlx') {
            debugPrint(
              '[KoboldService] KoboldCPP is answering on $_baseUrl but the '
              'selected backend is $backendType — leaving it alone.',
            );
            return;
          }
          debugPrint(
            '[KoboldService] Found orphaned KoboldCPP on $_baseUrl — killing it.',
          );
          await killOrphanedKoboldProcesses(_addLog);
        }
      }
    } catch (_) {
      // Not running — normal on first launch, ignore silently.
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _stopReadinessProbe();
    WidgetsBinding.instance.removeObserver(this);
    stopKobold();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      stopKobold();
    }
  }

  void setBaseUrl(String url) {
    // Force IPv4 for consistency
    String cleanUrl = url.replaceAll('localhost', '127.0.0.1');
    if (cleanUrl.endsWith('/')) {
      _baseUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    } else {
      _baseUrl = cleanUrl;
    }
    notifyListeners();
  }

  File get _logFile => File(
    path.join(_storageService.rootPath!, 'characters', 'session_log.txt'),
  );

  void _purgeLogs() {
    try {
      if (_storageService.rootPath != null && _logFile.existsSync()) {
        _logFile.deleteSync();
      }
    } catch (e) {
      print('Error purging logs: $e');
    }
  }

  void _writeToLogFile(String data) {
    try {
      if (_storageService.rootPath != null) {
        _logFile.writeAsStringSync(data, mode: FileMode.append);
      }
    } catch (e) {
      // Don't let logging errors crash the app
    }
  }

  Future<void> startKobold(
    String executablePath,
    String modelPath, {
    String? kcppsPath,
    String? mmprojPath,
    int port = 5001,
    int gpuLayers = 0,
    int contextSize = 4096,
    bool useVulkan = false,
    bool useCublas = false,
    bool useMetal = false,
    bool useRocm = false,
  }) async {
    if (_isStarting) return;
    // Claim the slot BEFORE the stop ladder below, not after it. That ladder
    // awaits for 1–6s with `_isRunning` already false, and a second caller
    // arriving in that window used to see both flags clear, walk straight to
    // Process.start, and have its handle overwritten by the first caller
    // resuming — one KoboldCpp process left with no owner, holding the port
    // and the VRAM. Every early return below must clear it again.
    _isStarting = true;
    // If the previous process is still alive (e.g. stopKobold was not awaited
    // or the stop is racing with start), kill it first to prevent zombie
    // processes from accumulating — especially on Windows where port reuse
    // isn't immediate.
    if (_isRunning || _process != null) {
      debugPrint(
        '[KoboldService] startKobold called while still running — stopping first.',
      );
      try {
        await stopKobold();
        // Give the OS a moment to release the port
        await Future<void>.delayed(const Duration(seconds: 1));
      } catch (e) {
        // The slot is claimed above, so a throwing stop must release it or
        // no launch would ever be possible again this session.
        _isStarting = false;
        _addLog('Could not stop the previous backend: $e');
        notifyListeners();
        rethrow;
      }
    }

    // ── Model file pre-flight ────────────────────────────────────────────────
    // Verify the .gguf is genuinely readable BEFORE spawning KoboldCpp, so a
    // missing/placeholder/corrupt file produces a sentence the user can act on
    // instead of a bare "Process exited with code 2" (issue #137). Skipped when
    // modelPath is empty, which is preset mode — there the .kcpps owns the
    // model and KoboldCpp resolves it itself.
    //
    // This is the single choke point for every launch path: two of them
    // (LLMProvider.ensureManagedBackendIsRunning and the SetupService
    // autostart) previously did no existence check at all and would launch
    // straight into the same unexplained exit 2.
    final modelProblem = await ModelFileCheck.validate(modelPath);
    if (modelProblem != null) {
      _addLog(modelProblem);
      _isStarting = false;
      notifyListeners();
      return;
    }

    // Store the executable path for cleanup
    _executablePath = executablePath;

    final args = await buildKoboldLaunchArgs(
      storage: _storageService,
      executablePath: executablePath,
      modelPath: modelPath,
      kcppsPath: kcppsPath,
      mmprojPath: mmprojPath,
      port: port,
      gpuLayers: gpuLayers,
      contextSize: contextSize,
      useVulkan: useVulkan,
      useCublas: useCublas,
      useMetal: useMetal,
      useRocm: useRocm,
    );

    try {
      print('AG_DEBUG: === STARTING KOBOLDCPP ===');
      print('AG_DEBUG: Executable: $executablePath');
      print('AG_DEBUG: Args: ${args.join(' ')}');
      print('AG_DEBUG: Working dir: ${path.dirname(executablePath)}');
      print('AG_DEBUG: File exists: ${File(executablePath).existsSync()}');
      print('AG_DEBUG: Model exists: ${File(modelPath).existsSync()}');

      // ROCm: consumer RDNA cards need HSA_OVERRIDE_GFX_VERSION or the
      // hipblas kernels abort at load — resolver detects the gfx arch and
      // supplies it (no-op when unnecessary or already exported).
      final extraEnv = useRocm
          ? await GpuBackendResolver.rocmEnvironment()
          : const <String, String>{};
      _process = await Process.start(
        executablePath,
        args,
        workingDirectory: path.dirname(executablePath),
        environment: extraEnv.isEmpty ? null : extraEnv,
        includeParentEnvironment: true,
      );
      print('AG_DEBUG: Process started successfully! PID: ${_process!.pid}');
      _isRunning = true;
      _modelLoadingStatus = 'Initializing model...';
      _modelReady = false;
      _addLog('Starting Koboldcpp...');
      _addLog('Command: $executablePath ${args.join(' ')}');
      notifyListeners();

      // Start periodic readiness probe — more reliable than log-watching.
      _startReadinessProbe();

      _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
            _addLog(data);
            _parseLoadingStatus(data);
            _ingestLiveProgress(data);
          });

      _process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
            // Many backends log everything to stderr even if not an error.
            var cleanData = data.trim();
            if (cleanData.isNotEmpty) {
              // Strip ALL occurrences of ERR: and filter out progress dots
              cleanData = cleanData
                  .replaceAll('ERR: ', '')
                  .replaceAll('ERR:', '');
              if (cleanData != '.' && cleanData != '..' && cleanData != '...') {
                _addLog(cleanData);
                _parseLoadingStatus(cleanData);
                _ingestLiveProgress(cleanData);
              }
            }
          });

      final launched = _process!;
      launched.exitCode.then((code) {
        _addLog('Process exited with code $code');
        // Only the process we are still tracking may clear the state — a
        // late-dying orphan from an overlapping start must not report the
        // LIVE backend as stopped.
        if (!identical(_process, launched)) {
          notifyListeners();
          return;
        }
        _isRunning = false;
        _process = null;
        // Exit 2 is KoboldCpp's "Cannot find text model file" path. The
        // pre-flight above catches most causes, but KoboldCpp resolves the
        // path through Python and can still reject a file we read fine, so
        // translate the bare exit code rather than leaving the user guessing.
        if (code == 2) {
          _addLog(ModelFileCheck.explainExitCode2(modelPath));
        }
        notifyListeners();
      });
    } catch (e, stack) {
      print('AG_DEBUG: === KOBOLDCPP START FAILED ===');
      print('AG_DEBUG: Error: $e');
      print('AG_DEBUG: Stack: $stack');
      _addLog('Failed to start process: $e');
      _isRunning = false;
      notifyListeners();
      rethrow;
    } finally {
      _isStarting = false;
    }
  }

  /// LLMService interface implementation.
  ///
  /// Routes generation through KoboldCpp's OpenAI-compatible
  /// `/v1/chat/completions` endpoint (via [streamOpenAiChat]) instead of the
  /// legacy raw `/api/extra/generate/stream`. The chat endpoint applies the
  /// loaded model's instruct template server-side, so instruct GGUFs follow
  /// instructions and stop naturally via EOS — the raw endpoint did neither
  /// (immediate empty responses or runaway repetition on un-templated prompts).
  /// This is the same transport the `.kcpps` pseudo-remote backend has always
  /// used against the same server. KoboldCpp ignores the model name.
  ///
  // Local tool calling: recent KoboldCpp supports OpenAI tools with
  // template-aware models (Qwen3 family etc.). Models/servers that can't
  // simply yield no tool calls and the caller's negotiation falls back to
  // its text transport (the Journal's XML floor).
  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    if (!isReady) return null;
    http.Client? mine;
    return _runSerialized<LlmToolResponse?>(() async {
      if (params.stillWantTools?.call() == false) return null;
      return postOpenAiChatWithTools(
        _baseUrl,
        params,
        tools,
        thinkingModelKey: _storageService.lastUsedModelPath,
        foldSystemIntoUser: _systemRole.foldSystemIntoUser,
        toolChoice: params.toolChoice,
        registerClient: (client) {
          mine = client;
          _activeClient = client;
        },
        // Same ownership rule the `_pendingRequest` slot two lines below
        // already follows (and OpenRouterService already applies to this
        // very field): a finishing call may only clear the abort handle if
        // it is still ITS handle. Clearing a newer request's client left
        // Stop/abort with nothing to close.
        onDone: () {
          if (identical(_activeClient, mine)) _activeClient = null;
        },
      );
    });
  }

  /// Run [body] with exclusive use of the single-slot local engine: wait for
  /// any in-flight request, then register on the SAME `_pendingRequest` slot
  /// [generateStream] uses, so other `waitForIdle` callers (text evals, the
  /// Scene Guest mint, the system-role probe) queue behind us instead of
  /// racing. Extracted from [generateWithTools], which was the only thing
  /// that did this dance — a second hand-rolled copy of a slot protocol is
  /// how one of them ends up subtly different.
  Future<T> _runSerialized<T>(Future<T> Function() body) async {
    await waitForIdle();
    final completer = Completer<void>();
    _pendingRequest = completer.future;
    try {
      return await body();
    } finally {
      if (!completer.isCompleted) completer.complete();
      // Only release the slot if it is still OURS — a stream that started
      // meanwhile (the main chat path doesn't waitForIdle) must not have its
      // registration nulled by this call's late finally.
      if (identical(_pendingRequest, completer.future)) _pendingRequest = null;
    }
  }

  /// `_activeClient` is registered for [abortGeneration]; `_pendingRequest`
  /// (a completer future) is tracked so [waitForIdle] still unblocks on close.
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final completer = Completer<void>();
    _pendingRequest = completer.future;
    http.Client? mine;
    try {
      yield* streamOpenAiChat(
        _baseUrl,
        params,
        thinkingModelKey: _storageService.lastUsedModelPath,
        foldSystemIntoUser: _systemRole.foldSystemIntoUser,
        registerClient: (client) {
          mine = client;
          _activeClient = client;
        },
        // Ownership guard — see generateWithTools: this stream's late
        // teardown must not null a newer request's abort handle.
        onDone: () {
          if (identical(_activeClient, mine)) _activeClient = null;
        },
      );
    } finally {
      if (!completer.isCompleted) completer.complete();
      // Same slot-ownership guard as generateWithTools: don't null a newer
      // request's registration from this one's late finally.
      if (identical(_pendingRequest, completer.future)) _pendingRequest = null;
    }
  }

  @override
  void abortGeneration() {
    _activeClient?.close();
    _activeClient = null;
    // Fire the server-side abort asynchronously so KoboldCPP stops the
    // current generation even after the socket is dropped. We don't await
    // here to keep the call non-blocking for the UI, but the server will
    // drain to idle before accepting the next request.
    _postAbort();
  }

  /// POST /api/extra/abort — KoboldCPP blocks until the active generation
  /// is fully stopped, then returns HTTP 200. Call this (and await it) before
  /// starting any new generation to guarantee the server is idle.
  Future<void> ensureServerIdle() async {
    if (!_isRunning) return;
    try {
      final client = http.Client();
      try {
        await client
            .post(
              Uri.parse('$_baseUrl/api/extra/abort'),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 30));
      } finally {
        client.close();
      }
    } catch (_) {
      // If the abort endpoint isn't available (older KoboldCPP build) or
      // the server isn't running, swallow the error — the generation request
      // will simply fail naturally.
    }
  }

  /// Wait for any in-flight generation to complete naturally.
  /// Unlike [ensureServerIdle], this does NOT abort the active request —
  /// it simply awaits the stream to close. Returns immediately if idle.
  Future<void> waitForIdle() async {
    final pending = _pendingRequest;
    if (pending != null) {
      await pending;
    }
  }

  /// Fire-and-forget server-side abort (used by abortGeneration).
  void _postAbort() {
    ensureServerIdle().catchError((_) {});
  }

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
    notifyListeners();
  }

  /// The measurement armed by the last [_markModelReady]. Production never
  /// waits on it (see [KoboldSystemRole.arm]); [debugMarkModelReady] does,
  /// because the alternative for a test is guessing when the probe finished —
  /// by sleeping, or by watching requests ARRIVE at a fake server. Arrival is
  /// the wrong event: the verdict is written after the last RESPONSE is
  /// parsed, so that guess is a race that passes alone and reddens CI at
  /// `--concurrency=4`.
  Future<void> _armedProbe = Future<void>.value();

  /// Test hooks: the model-ready transition that only a real process would
  /// otherwise drive — returning the measurement it armed — and the key it
  /// resolved.
  @visibleForTesting
  Future<void> debugMarkModelReady() {
    _markModelReady();
    return _armedProbe;
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
        notifyListeners();
      } else if (_loadFilePattern.hasMatch(data)) {
        _modelLoadingStatus = 'Loading model file...';
        notifyListeners();
      } else if (_mappingPattern.hasMatch(data)) {
        _modelLoadingStatus = 'Mapping model to memory...';
        notifyListeners();
      } else if (_warmupPattern.hasMatch(data)) {
        _modelLoadingStatus = 'Warming up model...';
        notifyListeners();
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
  /// would otherwise flood the log with thousands of identical-looking lines.
  static final RegExp _progressLinePattern = RegExp(
    r'^(Generating \(|Processing Prompt(?: \[BATCH\])? \()',
    caseSensitive: false,
  );

  void _addLog(String data) {
    if (data.trim().isEmpty) return;

    // KoboldCPP uses bare \r (carriage return) to overwrite the current
    // terminal line.  Split on any combination of \r\n, \r, or \n so each
    // logical line is processed individually.
    final rawLines = data.split(RegExp(r'\r\n|\r|\n'));
    bool changed = false;

    for (final rawLine in rawLines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final isProgress = _progressLinePattern.hasMatch(line);

      if (isProgress && _logs.isNotEmpty) {
        final lastEntry = _logs.last;
        // If the last stored log entry is also a progress line, overwrite it
        // in-place rather than appending a new entry.  This keeps the list
        // at O(1) growth during a long generation instead of O(n).
        if (_progressLinePattern.hasMatch(lastEntry)) {
          _logs.last = line;
          changed = true;
          // Do NOT write progress lines to the file — they are noise.
          continue;
        }
      }

      _logs.add(line);
      if (!isProgress) _writeToLogFile(line + '\n');
      if (_logs.length > 1000) _logs.removeAt(0);
      changed = true;
    }

    if (changed) notifyListeners();
  }

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

  Future<void> stopKobold() async {
    // Before anything else, and regardless of whether we own the process — a
    // hot-restart reconnect marks the model ready with `_process == null`,
    // and that verdict must not outlive the stop either. This also CANCELS a
    // measurement still on the wire: it is about to be a measurement of a
    // server that no longer exists, and it is holding this class's single
    // request slot while it waits. See [KoboldSystemRole.forget].
    _systemRole.forget();
    // Captured, because the exitCode listener installed by [startKobold] nulls
    // `_process` the moment the process dies — which can happen part-way
    // through the kill ladder below.
    final process = _process;
    if (process == null) return;
    _addLog('Stopping Backend (PID: ${process.pid})...');
    await terminateKoboldTree(
      process,
      executablePath: _executablePath,
      log: _addLog,
    );
    _process = null;
    _isRunning = false;
    _modelLoadingStatus = '';
    _modelReady = false;
    _stopReadinessProbe();
    notifyListeners();
  }
}
