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
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
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

part 'kobold_service_admin.dart';
part 'kobold_service_process.dart';

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
  String? _loadedModelPath;
  String? _loadedKcppsPath;

  /// One-shot "load just finished" latch. Home drains it (no success toast —
  /// dual-local swaps would stack those). Unlike [_modelReady], reset after
  /// [consumeModelReady] so each load is seen once.
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

  /// GGUF last started or last admin-reloaded onto this process.
  String? get loadedModelPath => _loadedModelPath;

  /// `.kcpps` last started or last admin-reloaded. Empty = UI-flag launch.
  String? get loadedKcppsPath => _loadedKcppsPath;

  /// Mouth + worker hosts share this so nested reload_config cannot overlap.
  final KoboldAdminSwapLock adminSwapLock = KoboldAdminSwapLock();

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

  /// Consume the one-shot "model just loaded" latch.
  /// Returns true exactly once after each model load. Does NOT affect
  /// [isReady] or [modelReady]. Home drains this without a success toast.
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

  /// The measurement armed by the last [_markModelReady]. Production never
  /// waits on it (see [KoboldSystemRole.arm]); [debugMarkModelReady] does,
  /// because the alternative for a test is guessing when the probe finished —
  /// by sleeping, or by watching requests ARRIVE at a fake server. Arrival is
  /// the wrong event: the verdict is written after the last RESPONSE is
  /// parsed, so that guess is a race that passes alone and reddens CI at
  /// `--concurrency=4`.
  Future<void> _armedProbe = Future<void>.value();

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
          final backendType = _storageService.backendSettings.backendType;
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

  // Public notify for same-library extensions (avoids protected member warnings).
  void notify() => notifyListeners();

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
        thinkingModelKey: _storageService.backendSettings.lastUsedModelPath,
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
        thinkingModelKey: _storageService.backendSettings.lastUsedModelPath,
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

  // Class members so `import … show KoboldService` still resolves them.
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
  }) => _startKobold(
    executablePath,
    modelPath,
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

  Future<void> stopKobold() => _stopKobold();
}
