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
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show ClientException;
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
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

  bool get isRunning => _isRunning;
  List<String> get logs => List.unmodifiable(_logs);
  String get modelLoadingStatus => _modelLoadingStatus;
  bool get modelReady => _modelReady;

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
      debugPrint('[KoboldService] startKobold called while still running — stopping first.');
      await stopKobold();
      // Give the OS a moment to release the port
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _isStarting = true;

    // Store the executable path for cleanup
    _executablePath = executablePath;

    final args = [
      '--model',
      modelPath,
      '--port',
      port.toString(),
      '--contextsize',
      contextSize.toString(),
      '--gpulayers',
      gpuLayers.toString(),
    ];

    if (useVulkan) args.add('--usevulkan');
    if (useCublas) args.add('--usecublas');
    if (useRocm) {
      args.add('--usehipblas');
      args.add(
        '--noflashattention',
      ); // Flash attention kernel crashes on many AMD GPUs
    }
    // Note: Metal is used automatically on macOS Apple Silicon, no flag needed

    // Add KV Cache Quantization if enabled
    if (_storageService.kvQuantizationLevel > 0) {
      args.add('--quantkv');
      args.add(_storageService.kvQuantizationLevel.toString());
      if (!useRocm) {
        // Flash attention is strictly required to quantize V-cache. ROCm falls back to K-cache quantization implicitly.
        args.add('--flashattention');
      }
    }

    try {
      print('AG_DEBUG: === STARTING KOBOLDCPP ===');
      print('AG_DEBUG: Executable: $executablePath');
      print('AG_DEBUG: Args: ${args.join(' ')}');
      print('AG_DEBUG: Working dir: ${path.dirname(executablePath)}');
      print('AG_DEBUG: File exists: ${File(executablePath).existsSync()}');
      print('AG_DEBUG: Model exists: ${File(modelPath).existsSync()}');

      _process = await Process.start(
        executablePath,
        args,
        workingDirectory: path.dirname(executablePath),
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
            _addLog(data.trim());
            _parseLoadingStatus(data);
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

  Stream<String> _generateStreamInternal(
    String prompt, {
    int maxLength = 80,
    int minLength = 0,
    double temp = 0.7,
    double repPenalty = 1.1,
    double topP = 0.9,
    double minP = 0.0,
    int repPenTokens = 64,
    double? dynatempRange,
    double xtcThreshold = 0.1,
    double xtcProbability = 0.5,
    List<String>? stopSequences,
    List<String>? bannedPhrases,
    String? grammar,
    bool banEosToken = false,
    bool trimStop = true,
  }) async* {
    final uri = Uri.parse('$_baseUrl/api/extra/generate/stream');
    final Map<String, dynamic> payload = {
      'prompt': prompt,
      'max_length': maxLength,
      'min_length': minLength,
      'temperature': temp,
      'rep_pen': repPenalty,
      'top_p': topP,
      'min_p': minP,
      'rep_pen_range': repPenTokens,
      'singleline': false,
      'trim_stop': trimStop,
      'stream': true,
      if (banEosToken) 'ban_eos_token': true,
    };

    if (dynatempRange != null && dynatempRange > 0) {
      payload['dynatemp_range'] = dynatempRange;
    }

    if (xtcThreshold > 0 && xtcProbability > 0) {
      payload['xtc_threshold'] = xtcThreshold;
      payload['xtc_probability'] = xtcProbability;
    }

    if (stopSequences != null && stopSequences.isNotEmpty) {
      payload['stop_sequence'] = stopSequences;
    }

    // Anti-slop phrase banning (KoboldCpp-specific)
    if (bannedPhrases != null && bannedPhrases.isNotEmpty) {
      payload['banned_tokens'] = bannedPhrases;
    }

    // GBNF grammar-constrained output (KoboldCpp-specific, local non-thinking models only)
    if (grammar != null && grammar.isNotEmpty) {
      payload['grammar'] = grammar;
    }

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(payload);

    final estimatedTokens = (prompt.length / 4).ceil();
    debugPrint(
      '[KoboldCpp] Streaming request: prompt=${prompt.length} chars (~$estimatedTokens tokens), max_length=$maxLength, stop_sequences=${stopSequences?.length ?? 0}',
    );

    final client = http.Client();
    _activeClient = client;
    try {
      // Thinking models (especially large ones like 24B+) can take several
      // minutes during the prefill phase before the first token is generated.
      // 60 s was too aggressive — raise to 5 minutes so long-context eval
      // calls don't time out before the model even starts streaming.
      final response = await client
          .send(request)
          .timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        if (response.statusCode == 405) {
          throw Exception(
            'STREAMING_NOT_SUPPORTED: The server returned HTTP 405. Streaming may not be supported by this backend.',
          );
        }
        throw Exception('HTTP ${response.statusCode}');
      }

      try {
        int _sseDataEvents = 0;
        bool _inThinkPhase = false; // Track thinking model state
        await for (final line
            in response.stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (line.startsWith('data: ')) {
            _sseDataEvents++;
            final data = line.substring(6);
            try {
              final json = jsonDecode(data);
              final rawToken = (json['token'] as String?) ?? '';
              final thinkToken = (json['thinking_token'] as String?) ?? '';
              final textToken = (json['text'] as String?) ?? '';

              // Log first few events and any unexpected patterns for debugging
              if (_sseDataEvents <= 3 || (rawToken.isEmpty && thinkToken.isEmpty && textToken.isEmpty)) {
                debugPrint('[KoboldCpp:SSE] Event #$_sseDataEvents — '
                    'token=${rawToken.length}ch, '
                    'thinking_token=${thinkToken.length}ch, '
                    'text=${textToken.length}ch');
              }

              // KoboldCPP thinking models send reasoning in 'thinking_token'
              // while 'token' is "" during the think phase. We emit synthetic
              // <think>/<think> tags at boundaries but skip the actual content.
              if (thinkToken.isNotEmpty && rawToken.isEmpty && textToken.isEmpty) {
                if (!_inThinkPhase) {
                  _inThinkPhase = true;
                  yield '<think>';
                }
                continue;
              }

              // Real output token — prefer 'token', fall back to 'text'
              final token = rawToken.isNotEmpty ? rawToken : textToken;
              if (token.isNotEmpty) {
                if (_inThinkPhase) {
                  _inThinkPhase = false;
                  yield '</think>';
                }
                yield token;
              }
            } catch (e) {
              // Skip malformed SSE events (e.g. data: [DONE])
            }
          }
        }
        debugPrint(
          '[KoboldCpp:SSE] Stream closed — data_events=$_sseDataEvents',
        );
      } on ClientException catch (e) {
        // The HTTP client was closed mid-stream. This happens in two cases:
        //   1. User hit Stop → abortGeneration() called client.close() intentionally.
        //   2. The KoboldCPP process crashed/restarted and dropped the socket.
        // In both cases we want a clean exit, not a raw ClientException in chat.
        // Re-throw only if the client is still alive (i.e. we didn't close it ourselves),
        // which indicates an unexpected network error rather than a user-initiated abort.
        if (_activeClient != null) {
          // Client still set means abortGeneration() hasn't run — genuine error.
          rethrow;
        }
        debugPrint(
          '[KoboldCpp] Stream ended by client close (abort or process exit): $e',
        );
        // Fall through — generator returns normally.
      }
    } finally {
      _activeClient = null;
      client.close();
    }
  }

  /// LLMService interface implementation — delegates to the existing method.
  @override
  Stream<String> generateStream(GenerationParams params) {
    return _generateStreamInternal(
      params.prompt,
      maxLength: params.maxLength,
      minLength: params.minLength,
      temp: params.temperature,
      repPenalty: params.repeatPenalty,
      topP: params.topP,
      minP: params.minP,
      repPenTokens: params.repPenTokens,
      dynatempRange: params.dynatempRange,
      xtcThreshold: params.xtcThreshold,
      xtcProbability: params.xtcProbability,
      stopSequences: params.stopSequences,
      bannedPhrases: params.bannedPhrases,
      grammar: params.grammar,
      banEosToken: params.banEosToken,
      trimStop: params.trimStop,
    );
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

  /// Fire-and-forget server-side abort (used by abortGeneration).
  void _postAbort() {
    ensureServerIdle().catchError((_) {});
  }

  Future<String> generate(
    String prompt, {
    int maxLength = 80,
    int minLength = 0,
    double temp = 0.7,
    double repPenalty = 1.1,
    double topP = 0.9,
    double minP = 0.0,
    int repPenTokens = 64,
    double? dynatempRange,
    double xtcThreshold = 0.1,
    double xtcProbability = 0.5,
    List<String>? stopSequences,
    List<String>? bannedPhrases,
  }) async {
    if (!_isRunning && !Platform.environment.containsKey('FLUTTER_TEST')) {
      _addLog(
        'Warning: internal backend not running, trying to connect anyway...',
      );
    }

    int retryCount = 0;
    while (retryCount < 5) {
      final client = http.Client();
      try {
        final uri = Uri.parse('$_baseUrl/api/v1/generate');

        final Map<String, dynamic> payload = {
          'prompt': prompt,
          'max_length': maxLength,
          'min_length': minLength,
          'temperature': temp,
          'rep_pen': repPenalty,
          'top_p': topP,
          'min_p': minP,
          'rep_pen_range': repPenTokens,
          'singleline': false,
          'trim_stop': true,
        };

        if (dynatempRange != null && dynatempRange > 0) {
          payload['dynatemp_range'] = dynatempRange;
        }

        if (xtcThreshold > 0 && xtcProbability > 0) {
          payload['xtc_threshold'] = xtcThreshold;
          payload['xtc_probability'] = xtcProbability;
        }

        if (stopSequences != null && stopSequences.isNotEmpty) {
          payload['stop_sequence'] = stopSequences;
        }

        // Anti-slop phrase banning (KoboldCpp-specific)
        if (bannedPhrases != null && bannedPhrases.isNotEmpty) {
          payload['banned_tokens'] = bannedPhrases;
        }

        final body = jsonEncode(payload);

        final response = await client
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final text = data['results'][0]['text'] as String;
          return text;
        } else {
          if (response.statusCode == 503) {
            _addLog('Server returned 503 (Busy/Loading), retrying...');
            await Future.delayed(const Duration(seconds: 2));
            throw const SocketException('Service Unavailable');
          }
          if (response.statusCode == 405) {
            // 405 won't succeed on retry — break immediately
            throw Exception(
              'The server returned HTTP 405 (Method Not Allowed). Check that your API URL is correct and the backend supports this endpoint.',
            );
          }
          if (response.statusCode == 408) {
            throw Exception(
              'Request timed out (HTTP 408). The model may be too slow for the configured timeout.',
            );
          }
          if (response.statusCode == 422) {
            throw Exception(
              'Invalid request (HTTP 422). The prompt may be too long for the model\'s context window.',
            );
          }
          if (response.statusCode >= 500) {
            _addLog('Server error ${response.statusCode}, retrying...');
            await Future.delayed(const Duration(seconds: 2));
            throw Exception('Server error (HTTP ${response.statusCode})');
          }
          throw Exception('API error: HTTP ${response.statusCode}');
        }
      } catch (e) {
        if (!isProcessAlive && _isRunning) {
          _addLog('Backend process crashed during generation! (Likely OOM)');
          throw Exception(
            'Backend process crashed. This usually happens when the GPU runs out of VRAM.',
          );
        }

        retryCount++;

        if (retryCount >= 5) {
          _addLog('Generation error after 5 attempts: $e');
          rethrow;
        }

        _addLog('Connection failed ($e), retrying in 2s...');
        await Future.delayed(const Duration(seconds: 2));
      } finally {
        client.close();
      }
    }
    throw Exception('Failed to generate after retries');
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

  void _addLog(String data) {
    if (data.trim().isEmpty) return;
    _logs.add(data);
    _writeToLogFile(data);
    if (_logs.length > 1000) _logs.removeAt(0);
    notifyListeners();
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
