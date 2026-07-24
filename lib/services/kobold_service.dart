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
import 'package:front_porch_ai/services/live_gen_progress.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/openai_chat_stream.dart';
import 'package:path/path.dart' as path;

class KoboldService extends ChangeNotifier
    with WidgetsBindingObserver
    implements LLMService {
  final StorageService _storageService;
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

  KoboldService(this._storageService) {
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
          _modelReady = true;
          _modelJustLoaded = true;
          notifyListeners();
          await _syncVersionFromResponse(response);
        } else {
          // Orphaned zombie from a previous app instance (e.g. after update).
          // Kill it so we can start fresh on the same port.
          debugPrint(
            '[KoboldService] Found orphaned KoboldCPP on $_baseUrl — killing it.',
          );
          await killOrphanedBackend();
        }
      }
    } catch (_) {
      // Not running — normal on first launch, ignore silently.
    } finally {
      client.close();
    }
  }

  /// Kill any KoboldCPP processes that were left behind by a previous app
  /// instance (e.g. after an update where exit(0) bypassed cleanup).
  /// This is a best-effort cleanup — it won't fail if nothing is found.
  Future<void> killOrphanedBackend() async {
    try {
      if (Platform.isWindows) {
        // Kill all koboldcpp.exe processes — there should only be zombies.
        await Process.run('taskkill', ['/F', '/IM', 'koboldcpp.exe']);
        await Process.run('taskkill', ['/F', '/IM', 'koboldcpp_nocuda.exe']);
        // Non-AVX2 machines run the oldpc build (distinct image name).
        await Process.run('taskkill', ['/F', '/IM', 'koboldcpp-oldpc.exe']);
        _addLog('Killed orphaned KoboldCPP processes.');
      } else {
        // macOS/Linux: kill by process name
        await Process.run('pkill', ['-KILL', '-f', 'koboldcpp']);
        _addLog('Killed orphaned KoboldCPP processes.');
      }
    } catch (e) {
      debugPrint('[KoboldService] killOrphanedBackend failed (OK): $e');
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
    // If the previous process is still alive (e.g. stopKobold was not awaited
    // or the stop is racing with start), kill it first to prevent zombie
    // processes from accumulating — especially on Windows where port reuse
    // isn't immediate.
    if (_isRunning || _process != null) {
      debugPrint(
        '[KoboldService] startKobold called while still running — stopping first.',
      );
      await stopKobold();
      // Give the OS a moment to release the port
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _isStarting = true;

    // Store the executable path for cleanup
    _executablePath = executablePath;

    List<String> args;

    if (kcppsPath != null) {
      // ── Preset mode (.kcpps) ────────────────────────────────────────────────
      // Let KoboldCpp load GPU, context, and all other settings from the file.
      // We only force the port so the app's _baseUrl doesn't break.
      //
      // If the .kcpps file has NO model key (StorageService.kcppsHasModel is
      // false), the user selected one via the Flutter model picker and we pass
      // it via --model.  Without this KoboldCPP would open its own native file
      // picker — which is the bug we're fixing.
      //
      // If the .kcpps file DOES have a model, modelPath is empty here and we
      // let the preset handle it entirely.
      args = [
        '--config',
        kcppsPath,
        '--port',
        port.toString(),
        if (modelPath.isNotEmpty) ...['--model', modelPath],
      ];
    } else {
      // ── Standard UI-driven mode ─────────────────────────────────────────────
      args = [
        '--model',
        modelPath,
        '--port',
        port.toString(),
        '--contextsize',
        contextSize.toString(),
        '--gpulayers',
        gpuLayers.toString(),
      ];

      // \u2500\u2500 GPU backend flags \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

      if (useVulkan) args.add('--usevulkan');

      if (useCublas) {
        // Always pass an explicit GPU ID with --usecublas to prevent KoboldCPP
        // from defaulting to GPU 0 which may be an iGPU on multi-GPU systems.
        // Bug fix: on a system with both an iGPU (GPU 0) and a discrete RTX (GPU 1)
        // the old code silently ran everything on the iGPU at ~0.5 t/s.
        args.addAll(['--usecublas', _storageService.gpuId.toString()]);
      }

      if (useRocm) {
        // Explicit device index — same iGPU-defaulting hazard as CUDA on
        // APU + dGPU systems.
        args.addAll(['--usehipblas', _storageService.gpuId.toString()]);
        // Flash attention kernel crashes on many AMD GPUs — always disable for ROCm.
        args.add('--noflashattention');
      }
      // Note: Metal is used automatically on macOS Apple Silicon, no flag needed.

      // \u2500\u2500 FlashAttention \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
      // Bug fix: previously only added when KV quantization was also enabled,
      // meaning CUDA/Metal users without KV quant never got the ~30% speed boost.
      // Now enabled independently for CUDA and Metal. ROCm is excluded above.
      final wantsFlashAttn = _storageService.flashAttentionEnabled;
      final canUseFlashAttn = (useCublas || useMetal) && !useRocm;
      if (wantsFlashAttn && canUseFlashAttn) {
        args.add('--flashattention');
      }

      // \u2500\u2500 KV Cache Quantization \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
      // Flash attention is a prerequisite for V-cache quantization. Since we
      // may have already added it above, only add the flag if it wasn\u2019t added.
      if (_storageService.kvQuantizationLevel > 0) {
        args.add('--quantkv');
        args.add(_storageService.kvQuantizationLevel.toString());
        // Ensure flash attention is present for quantised V-cache even if the
        // user disabled it in Advanced settings (quantkv requires it).
        if (!args.contains('--flashattention') && !useRocm) {
          args.add('--flashattention');
        }
      }

      // \u2500\u2500 mlock \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
      // Prevents the OS from paging model weights to disk under memory pressure.
      // Without this, a system at the edge of RAM capacity can drop from 20 t/s
      // to 0.5 t/s mid-session. Default ON for Win/Mac, OFF for Linux (requires
      // root or ulimit -l unlimited which most users haven\u2019t set).
      if (_storageService.mlockEnabled) {
        args.add('--usemlock');
      }

      // \u2500\u2500 BLAS batch size \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
      // Controls how many tokens are processed in parallel during prefill (prompt
      // evaluation). Higher = faster context loading, more VRAM. Default 512.
      // Large-VRAM users (24 GB+) benefit from 1024\u20132048.
      if (_storageService.blasBatchSize != 512) {
        final batch = _storageService.blasBatchSize;
        if (batch > 4096) {
          // KoboldCpp's CLI rejects anything above 4096 \u2014 but that cap is
          // launcher-only (an argparse `choices` list); the engine itself has
          // no upper clamp for GGUF models and sets n_ubatch = n_batch from
          // whatever arrives. Values loaded from a --config file are applied
          // with setattr AFTER argument parsing \u2014 no choices validation \u2014 and
          // Kobold's loader is explicitly designed so CLI flags override
          // config keys, so this one-key config carries ONLY the batch size
          // while every other flag stays authoritative on the CLI. If a
          // future build hardens config validation, the worst case is the
          // key failing to apply (Kobold runs at its default batch instead
          // of refusing to start, which is what the raw CLI flag did).
          final overrides = File(
            path.join(
              path.dirname(executablePath),
              'fpai_batch_override.kcpps',
            ),
          );
          await overrides.writeAsString(jsonEncode({'batchsize': batch}));
          args.addAll(['--config', overrides.path]);
        } else {
          // Only pass the flag when non-default so KoboldCPP's built-in
          // default applies for users who haven't changed this setting.
          args.addAll(['--blasbatchsize', batch.toString()]);
        }
      }
    }

    // ── Jinja chat templates ─────────────────────────────────────────────────
    // Run each model's OWN embedded chat template server-side instead of
    // KoboldCpp's built-in AutoGuess string adapter. This is what lets a model's
    // `chat_template_kwargs` (notably enable_thinking) actually take effect —
    // without --jinja, Kobold discards that field, so reasoning/thinking models
    // whose template defaults to suppressed (Gemma-4-class channel reasoners)
    // never think, and the "Request Reasoning" toggle is a no-op locally.
    // Applied to BOTH launch paths (preset .kcpps and standard) since both drive
    // the shared /v1/chat/completions transport. Safe as a global default: if a
    // model's embedded template is missing or malformed, KoboldCpp automatically
    // falls back to its heuristic adapter (verified — the server still starts and
    // answers), so this never blocks a model from loading. Plain --jinja keeps
    // tool calls on the non-jinja path (unchanged); --jinja_tools is intentionally
    // NOT used.
    args.add('--jinja');

    // ── Vision projector (mmproj) ────────────────────────────────────────────
    // A multimodal model whose projector is NOT baked into the GGUF (it ships in
    // a separate mmproj file) can actually see images only when KoboldCpp is
    // handed that file. Added for BOTH preset and standard modes, and only when
    // a non-empty path is configured AND the file exists on disk — a stale or
    // missing mmproj must never abort the launch.
    if (mmprojPath != null &&
        mmprojPath.isNotEmpty &&
        File(mmprojPath).existsSync()) {
      args.addAll(['--mmproj', mmprojPath]);
    }

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

      _process!.exitCode.then((code) {
        _isRunning = false;
        _process = null;
        _addLog('Process exited with code $code');
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
    // Serialize politely on the single-slot local engine: wait for any
    // in-flight request first, and register on the SAME _pendingRequest slot
    // generateStream uses — so waitForIdle callers (text evals, the Scene
    // Guest mint's background-safe path) genuinely wait for an in-flight
    // tools call instead of racing it.
    await waitForIdle();
    final completer = Completer<void>();
    _pendingRequest = completer.future;
    try {
      return await postOpenAiChatWithTools(
        _baseUrl,
        params,
        tools,
        registerClient: (client) => _activeClient = client,
        onDone: () => _activeClient = null,
      );
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
    try {
      yield* streamOpenAiChat(
        _baseUrl,
        params,
        registerClient: (client) => _activeClient = client,
        onDone: () => _activeClient = null,
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
        _modelLoadingStatus = '';
        _modelReady = true;
        _modelJustLoaded = true;
        _stopReadinessProbe();
        notifyListeners();
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
      _modelLoadingStatus = '';
      _modelReady = true;
      _modelJustLoaded = true;
      _stopReadinessProbe();
      notifyListeners();
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
    if (_process != null) {
      final pid = _process!.pid;
      _addLog('Stopping Backend (PID: $pid)...');

      if (Platform.isWindows) {
        try {
          // Force kill process tree on Windows
          await Process.run('taskkill', ['/F', '/T', '/PID', pid.toString()]);
          _addLog('Force killed process tree.');
        } catch (e) {
          _addLog('Taskkill failed, trying standard kill: $e');
          _process!.kill();
        }
      } else {
        // Linux/macOS: Dart's Process.start() does NOT create a new process group,
        // so the child inherits our PGID. We can't use kill(-pid) reliably.
        // Instead: kill all child processes first, then the parent.
        try {
          // Step 1: Kill all child processes of the koboldcpp parent
          _addLog('Killing child processes of PID $pid...');
          await Process.run('pkill', ['-TERM', '-P', pid.toString()]);

          // Step 2: Kill the parent process itself
          _process?.kill(ProcessSignal.sigterm);
          _addLog('Sent SIGTERM to parent and children.');

          // Wait up to 3 seconds for graceful shutdown
          bool exited = false;
          for (int i = 0; i < 6; i++) {
            await Future.delayed(const Duration(milliseconds: 500));
            try {
              final check = await Process.run('kill', ['-0', pid.toString()]);
              if (check.exitCode != 0) {
                exited = true;
                break;
              }
            } catch (_) {
              exited = true;
              break;
            }
          }

          if (!exited) {
            // Force kill with SIGKILL — children first, then parent
            _addLog('Process did not exit gracefully, sending SIGKILL...');
            await Process.run('pkill', ['-KILL', '-P', pid.toString()]);
            _process?.kill(ProcessSignal.sigkill);
          }

          // Step 3: Final safety net — kill any remaining processes matching the
          // executable name. This catches deeply nested children or processes
          // that reparented to init (PID 1) after their parent was killed.
          if (_executablePath != null) {
            final exeName = path.basename(_executablePath!);
            _addLog('Cleaning up any remaining $exeName processes...');
            await Process.run('pkill', ['-KILL', '-f', exeName]);
          }
        } catch (e) {
          _addLog('Process cleanup failed, using fallback: $e');
          _process?.kill(ProcessSignal.sigkill);
          // Still try the executable-name fallback
          if (_executablePath != null) {
            final exeName = path.basename(_executablePath!);
            try {
              await Process.run('pkill', ['-KILL', '-f', exeName]);
            } catch (_) {}
          }
        }
      }

      // Wait briefly for process to fully exit before clearing state
      try {
        await _process?.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        // Timeout is fine — we've already sent kill signals
      }

      _process = null;
      _isRunning = false;
      _modelLoadingStatus = '';
      _modelReady = false;
      _stopReadinessProbe();
      notifyListeners();
    }
  }
}
