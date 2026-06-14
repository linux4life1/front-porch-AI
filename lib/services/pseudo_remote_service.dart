import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:front_porch_ai/services/kobold_binary_version.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:path/path.dart' as path;

class PseudoRemoteService extends LLMService {
  Process? _process;
  bool _isRunning = false;
  bool _isStarting = false;
  String _baseUrl = 'http://127.0.0.1:5001';
  Timer? _readinessProbe;
  bool _modelReady = false;
  final List<String> _logs = [];
  String? _executablePath;
  http.Client? _activeClient;

  // LLMService interface
  @override
  bool get isReady => _isRunning && _modelReady;
  @override
  String get backendName => 'PseudoRemote';
  bool get isRunning => _isRunning;
  bool get isProcessRunning => _isRunning;
  bool get isStarting => _isStarting;
  List<String> get logs => List.unmodifiable(_logs);
  String get modelName => 'PseudoRemote (KoboldCPP)';

  PseudoRemoteService();

  /// Probe the KoboldCPP server — same as KoboldService.reconnectIfAlive().
  Future<void> reconnectIfAlive() async {
    if (_isRunning) return;
    if (_process == null) return;
    final client = http.Client();
    try {
      final uri = Uri.parse('$_baseUrl/api/extra/version');
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        debugPrint(
          '[PseudoRemote] Reconnected to existing KoboldCPP instance.',
        );
        _isRunning = true;
        _modelReady = true;
        notifyListeners();
        await _syncVersionFromResponse(response);
      }
    } catch (_) {
    } finally {
      client.close();
    }
  }

  Future<void> start({
    required String executablePath,
    required String kcppsPath,
    String? modelPath,
    int port = 5001,
  }) async {
    if (_isStarting) return;
    if (_isRunning || _process != null) {
      debugPrint(
        '[PseudoRemote] start called while still running — stopping first.',
      );
      await stop();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _isStarting = true;
    _executablePath = executablePath;

    final args = [
      '--config',
      kcppsPath,
      '--port',
      port.toString(),
      if (modelPath != null && modelPath.isNotEmpty) ...['--model', modelPath],
    ];

    try {
      _process = await Process.start(
        executablePath,
        args,
        workingDirectory: path.dirname(executablePath),
      );
      _isRunning = true;
      _modelReady = false;
      _addLog('Starting Koboldcpp (PseudoRemote)...');
      _addLog('Command: $executablePath ${args.join(' ')}');
      notifyListeners();

      _startReadinessProbe();

      _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
            _addLog(data);
            _parseLoadingStatus(data);
          });

      _process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
            var cleanData = data.trim();
            if (cleanData.isNotEmpty) {
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
    } catch (e) {
      _addLog('Failed to start process: $e');
      _isRunning = false;
      notifyListeners();
      rethrow;
    } finally {
      _isStarting = false;
    }
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (!isReady) {
      throw Exception('PseudoRemote backend not ready.');
    }

    final uri = Uri.parse('$_baseUrl/v1/chat/completions');

    final messages = <Map<String, String>>[];
    if (params.systemPrompt != null && params.systemPrompt!.isNotEmpty) {
      messages.add({'role': 'system', 'content': params.systemPrompt!});
    }
    messages.add({'role': 'user', 'content': params.prompt});

    final payload = <String, dynamic>{
      'model': 'koboldcpp',
      'stream': true,
      'max_tokens': params.maxLength,
      'temperature': params.temperature,
      'top_p': params.topP,
      'frequency_penalty': params.repeatPenalty > 1.0
          ? (params.repeatPenalty - 1.0).clamp(0.0, 2.0)
          : 0.0,
      'messages': messages,
    };

    if (params.reasoningEnabled || params.reasoningMaxTokens != null) {
      final reasoning = <String, dynamic>{
        'enabled': params.reasoningEnabled,
      };
      if (params.reasoningEnabled) {
        reasoning['effort'] = params.reasoningEffort;
      }
      if (params.reasoningMaxTokens != null) {
        reasoning['max_tokens'] = params.reasoningMaxTokens;
      }
      if (!params.reasoningEnabled) {
        reasoning['exclude'] = true;
      }
      payload['reasoning'] = reasoning;
    }

    if (params.stopSequences != null && params.stopSequences!.isNotEmpty) {
      payload['stop'] = params.stopSequences!.take(4).toList();
    }

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(payload);

    final client = http.Client();
    _activeClient = client;

    final completer = Completer<void>();

    try {
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        String errorMsg = 'HTTP ${response.statusCode}';
        try {
          final errJson = jsonDecode(body);
          errorMsg = errJson['error']?['message'] ?? errorMsg;
        } catch (_) {}
        throw Exception('API error: $errorMsg');
      }

      String buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);
          if (line.isEmpty) continue;
          if (line == 'data: [DONE]' || line == 'data:[DONE]') return;
          if (!line.startsWith('data:')) continue;
          final data = line.startsWith('data: ')
              ? line.substring(6)
              : line.substring(5);
          try {
            final json = jsonDecode(data);
            final choice = json['choices']?[0];
            final delta = choice?['delta'];
            if (delta == null) continue;
            final content = delta['content'];
            if (content != null && content is String && content.isNotEmpty) {
              yield content;
            }
          } catch (_) {}
        }
      }
    } finally {
      _activeClient = null;
      client.close();
      if (!completer.isCompleted) completer.complete();
    }
  }

  @override
  void abortGeneration() {
    _activeClient?.close();
    _activeClient = null;
  }

  // ── Readiness probe ──

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
  static final RegExp _progressLinePattern = RegExp(
    r'^(Generating \(|Processing Prompt(?: \[BATCH\])? \()',
    caseSensitive: false,
  );

  void _startReadinessProbe() {
    _stopReadinessProbe();
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
        _modelReady = true;
        _stopReadinessProbe();
        notifyListeners();
        await _syncVersionFromResponse(response);
      }
    } catch (_) {
    } finally {
      client.close();
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

  void _parseLoadingStatus(String data) {
    if (_readyPattern.hasMatch(data)) {
      _modelReady = true;
      _stopReadinessProbe();
      notifyListeners();
      return;
    }
    if (!_modelReady) {
      if (_loadModelPattern.hasMatch(data)) {
        notifyListeners();
      } else if (_loadFilePattern.hasMatch(data)) {
        notifyListeners();
      } else if (_mappingPattern.hasMatch(data)) {
        notifyListeners();
      } else if (_warmupPattern.hasMatch(data)) {
        notifyListeners();
      }
    }
  }

  void _addLog(String data) {
    if (data.trim().isEmpty) return;
    final rawLines = data.split(RegExp(r'\r\n|\r|\n'));
    bool changed = false;
    for (final rawLine in rawLines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final isProgress = _progressLinePattern.hasMatch(line);
      if (isProgress && _logs.isNotEmpty) {
        final lastEntry = _logs.last;
        if (_progressLinePattern.hasMatch(lastEntry)) {
          _logs.last = line;
          changed = true;
          continue;
        }
      }
      _logs.add(line);
      if (_logs.length > 1000) _logs.removeAt(0);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  // ── Utilities ──

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
    } finally {
      client.close();
    }
    return null;
  }

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
    } catch (_) {}
    return (text.length / 4).ceil();
  }

  Future<void> stop() async {
    if (_process != null) {
      final pid = _process!.pid;
      _addLog('Stopping PseudoRemote Backend (PID: $pid)...');

      if (Platform.isWindows) {
        try {
          await Process.run('taskkill', ['/F', '/T', '/PID', pid.toString()]);
          _addLog('Force killed process tree.');
        } catch (e) {
          _addLog('Taskkill failed, trying standard kill: $e');
          _process!.kill();
        }
      } else {
        try {
          _addLog('Killing child processes of PID $pid...');
          await Process.run('pkill', ['-TERM', '-P', pid.toString()]);
          _process?.kill(ProcessSignal.sigterm);
          _addLog('Sent SIGTERM to parent and children.');
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
            _addLog('Process did not exit gracefully, sending SIGKILL...');
            await Process.run('pkill', ['-KILL', '-P', pid.toString()]);
            _process?.kill(ProcessSignal.sigkill);
          }
          if (_executablePath != null) {
            final exeName = path.basename(_executablePath!);
            _addLog('Cleaning up any remaining $exeName processes...');
            await Process.run('pkill', ['-KILL', '-f', exeName]);
          }
        } catch (e) {
          _addLog('Process cleanup failed, using fallback: $e');
          _process?.kill(ProcessSignal.sigkill);
          if (_executablePath != null) {
            final exeName = path.basename(_executablePath!);
            try {
              await Process.run('pkill', ['-KILL', '-f', exeName]);
            } catch (_) {}
          }
        }
      }

      try {
        await _process?.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {}

      _process = null;
      _isRunning = false;
      _modelReady = false;
      _stopReadinessProbe();
      notifyListeners();
    }
  }
}
