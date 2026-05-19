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
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

/// Result of emotion classification.
class EmotionResult {
  final String emotion;
  final double confidence;
  final List<EmotionCandidate> topCandidates;

  const EmotionResult({
    required this.emotion,
    required this.confidence,
    this.topCandidates = const [],
  });

  factory EmotionResult.fromJson(Map<String, dynamic> json) {
    final candidates = (json['top_3'] as List<dynamic>?)?.map((e) {
      final m = e as Map<String, dynamic>;
      return EmotionCandidate(
        emotion: m['emotion'] as String? ?? 'unknown',
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList() ??
        [];

    return EmotionResult(
      emotion: json['emotion'] as String? ?? 'neutral',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      topCandidates: candidates,
    );
  }
}

/// A candidate emotion with its confidence score.
class EmotionCandidate {
  final String emotion;
  final double confidence;

  const EmotionCandidate({
    required this.emotion,
    required this.confidence,
  });
}

/// Abstract base for expression emotion classifiers.
abstract class ExpressionClassifier {
  /// Classify the emotion of [text].
  Future<EmotionResult> classify(String text);

  /// Returns true if this classifier is available on the current system.
  Future<bool> isAvailable();
}

/// LLM-based classifier that uses the ChatService's existing emotion tracking.
///
/// This is the default classifier when Realism Engine is enabled. It reuses
/// the nuanced emotion word produced by the LLM and maps it to a standard
/// label via [EmotionLabels.nuancedToStandard].
class LLMExpressionClassifier implements ExpressionClassifier {
  final String Function() getCurrentEmotion;
  final Future<String> Function(String unknownEmotion) reclassify;

  LLMExpressionClassifier({
    required this.getCurrentEmotion,
    required this.reclassify,
  });

  @override
  Future<EmotionResult> classify(String text) async {
    final emotion = getCurrentEmotion().toLowerCase();
    if (emotion.isEmpty) {
      return const EmotionResult(emotion: 'neutral', confidence: 1.0);
    }

    // Direct match
    if (EmotionLabels.all.contains(emotion)) {
      return EmotionResult(emotion: emotion, confidence: 1.0);
    }

    // Nuanced mapping
    final mapped = EmotionLabels.nuancedToStandard[emotion];
    if (mapped != null) {
      return EmotionResult(emotion: mapped, confidence: 0.9);
    }

    // Unmapped — trigger LLM re-classification
    try {
      final result = await reclassify(emotion);
      final normalized = result.toLowerCase().trim();
      final label = EmotionLabels.all.contains(normalized) ? normalized : 'neutral';
      return EmotionResult(emotion: label, confidence: 0.8);
    } catch (_) {
      return const EmotionResult(emotion: 'neutral', confidence: 0.5);
    }
  }

  @override
  Future<bool> isAvailable() async => true;
}

/// Download progress state for the ONNX model.
class OnnxDownloadProgress {
  final String file;
  final int downloaded;
  final int total;

  OnnxDownloadProgress({
    required this.file,
    required this.downloaded,
    required this.total,
  });

  double get fraction => total > 0 ? downloaded / total : 0.0;
}

/// ONNX-based classifier that spawns the Python sentiment_classifier.py sidecar.
class ONNXExpressionClassifier implements ExpressionClassifier {
  final StorageService storage;
  final void Function(OnnxDownloadProgress)? onProgress;
  final void Function()? onModelReady;
  bool _modelReady = false;
  
  Process? _process;
  Completer<EmotionResult>? _pendingRequest;
  StreamSubscription<String>? _stdoutSub;
  bool _isStopping = false;

  ONNXExpressionClassifier({
    required this.storage,
    this.onProgress,
    this.onModelReady,
  });

  /// Directory where model files are cached — always inside the user's data root.
  String get _modelCacheDir => '${storage.rootPath}/models/emotion_classifier';

  /// Path to the ONNX classifier debug log file.
  String get _debugLogPath => '${storage.rootPath}/logs/onnx_classifier_debug.txt';

  /// The python command for the current platform.
  String get _pythonCmd => Platform.isWindows ? 'python' : 'python3';

  /// Resolves the executable and arguments for the sentiment classifier.
  ///
  /// Resolution order:
  ///   1. PyInstaller binary inside macOS app bundle (production)
  ///   2. PyInstaller binary alongside the app executable (Linux / Windows production)
  ///   3. sentiment_classifier.py in the user's storage root (manual placement)
  ///   4. sentiment_classifier.py in the working directory (flutter run -d macos dev mode)
  ///
  /// Returns a record of (executable, args).
  (String, List<String>) _resolveCommand(List<String> extraArgs) {
    // 1. User's storage root (manual placement / advanced users / hotfixes)
    // Checking this FIRST allows testers to override a broken bundled binary
    // by placing an updated sentiment_classifier.py in their Documents folder.
    final userScript = File('${storage.rootPath}/sentiment_classifier.py');
    if (userScript.existsSync()) {
      debugPrint('[ExpressionClassifier] Using USER SCRIPT override: ${userScript.path}');
      return (_pythonCmd, [userScript.path, ...extraArgs]);
    }

    // 2. macOS production: binary inside app bundle Resources
    if (Platform.isMacOS) {
      final resourcesDir = File(Platform.resolvedExecutable).parent.parent.path;
      final bundled = File('$resourcesDir/Resources/sentiment_classifier/sentiment_classifier');
      if (bundled.existsSync()) {
        return (bundled.path, extraArgs);
      }
    }

    // 3. Linux / Windows production: binary alongside the app executable
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final ext = Platform.isWindows ? '.exe' : '';
    final bundledBin = File('$exeDir/sentiment_classifier/sentiment_classifier$ext');
    if (bundledBin.existsSync()) {
      debugPrint('[ExpressionClassifier] Using bundled binary: ${bundledBin.path}');
      return (bundledBin.path, extraArgs);
    }

    // 4. Dev mode: project root via Directory.current (flutter run sets CWD to project root)
    final devScript = File('${Directory.current.path}/sentiment_classifier.py');
    debugPrint('[ExpressionClassifier] Checking dev script: ${devScript.path}');
    if (devScript.existsSync()) {
      return (_pythonCmd, [devScript.path, ...extraArgs]);
    }

    // Final fallback — relies on PATH
    debugPrint('[ExpressionClassifier] No script found at known paths, falling back to PATH search for: sentiment_classifier.py');
    return (_pythonCmd, ['sentiment_classifier.py', ...extraArgs]);
  }

  /// Appends a timestamped line to the ONNX debug log file.
  void _logDebug(String message) async {
    final formattedMessage = '>>> [ONNX:DEBUG] $message';
    try {
      final logFile = File(_debugLogPath);
      final logDir = logFile.parent;
      if (!logDir.existsSync()) {
        await logDir.create(recursive: true);
      }
      final timestamp = DateTime.now().toIso8601String();
      final formatted = '[$timestamp] $message';
      
      // Use stdout.writeln for guaranteed visibility in Windows CMD
      stdout.writeln(formattedMessage);
      await logFile.writeAsString('$formatted\n', mode: FileMode.append, flush: true);
    } catch (e) {
      stdout.writeln('>>> [ONNX:ERROR] Failed to write to debug log: $e');
      stdout.writeln(formattedMessage);
    }
  }

  /// Streams stderr lines from [process], firing progress/ready callbacks.
  void _listenStderr(Process process) {
    process.stderr.transform(utf8.decoder).listen(
      (chunk) {
        for (final rawLine in chunk.split('\n')) {
          final line = rawLine.trim();
          if (line.isEmpty) continue;
          debugPrint('[SentimentClassifier] $line');
          _logDebug('[STDERR] $line');
          try {
            final parsed = jsonDecode(line) as Map<String, dynamic>;
            final status = parsed['status'] as String?;
            if (status == 'download_progress') {
              onProgress?.call(OnnxDownloadProgress(
                file: parsed['file'] as String? ?? 'unknown',
                downloaded: (parsed['downloaded'] as num?)?.toInt() ?? 0,
                total: (parsed['total'] as num?)?.toInt() ?? 0,
              ));
            } else if (status == 'model_ready') {
              _modelReady = true;
              onModelReady?.call();
            }
          } catch (_) {
            // Non-JSON debug line — ignore
          }
        }
      },
      onError: (e) {
        final msg = '[SentimentClassifier] stderr error: $e';
        debugPrint(msg);
        _logDebug(msg);
      },
    );
  }

  /// Downloads the ONNX model by running the sidecar with [--download-only].
  ///
  /// Progress is reported via [onProgress] and [onModelReady] callbacks.
  /// The model is cached to [storage.rootPath]/models/emotion_classifier.
  Future<void> downloadModel() async {
    final cacheDir = _modelCacheDir;
    final (exe, args) = _resolveCommand(['--download-only', '--cache-dir', cacheDir]);

    debugPrint('[ONNXExpressionClassifier] Starting download: $exe ${args.join(' ')}');
    _logDebug('Starting download: $exe ${args.join(' ')}');

    try {
      final process = await Process.start(exe, args);
      _listenStderr(process);
      // No stdout output in --download-only mode; drain it to avoid buffer stalls
      unawaited(process.stdout.drain<void>());

      final exitCode = await process.exitCode;
      debugPrint('[ONNXExpressionClassifier] Download process exited: $exitCode');
      _logDebug('Download process exited: $exitCode');

      if (exitCode == 0 && !_modelReady) {
        // Model was already cached — script exited 0 before emitting model_ready
        _modelReady = true;
        onModelReady?.call();
      }
    } catch (e) {
      final msg = '[ONNXExpressionClassifier] downloadModel error: $e';
      debugPrint(msg);
      _logDebug(msg);
    }
  }

  @override
  Future<EmotionResult> classify(String text) async {
    if (_isStopping) return const EmotionResult(emotion: 'neutral', confidence: 0.0);

    // Ensure the sidecar process is running
    final started = await _ensureProcessStarted();
    if (!started || _process == null) {
      return const EmotionResult(emotion: 'neutral', confidence: 0.0);
    }

    // Cancel any previous pending request (though ChatService should already be debouncing)
    if (_pendingRequest != null && !_pendingRequest!.isCompleted) {
      _pendingRequest!.completeError('Superseded by new request');
    }

    _pendingRequest = Completer<EmotionResult>();
    
    try {
      _logDebug('classify() called for text: "${text.length > 50 ? '${text.substring(0, 50)}...' : text}"');
      
      final request = jsonEncode({'text': text});
      final lineEnding = Platform.isWindows ? '\r\n' : '\n';
      _process!.stdin.write('$request$lineEnding');
      await _process!.stdin.flush();

      // Wait for the response from stdout (handled in _listenStdout)
      // With a 10s timeout to prevent hanging if the script crashes
      return await _pendingRequest!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _logDebug('Classification timed out after 10s');
          _pendingRequest = null;
          return const EmotionResult(emotion: 'neutral', confidence: 0.0);
        },
      );
    } catch (e) {
      _logDebug('classify() error: $e');
      return const EmotionResult(emotion: 'neutral', confidence: 0.0);
    }
  }

  /// Starts the sidecar process if it's not already running.
  Future<bool> _ensureProcessStarted() async {
    if (_process != null) return true;

    final cacheDir = _modelCacheDir;
    final (exe, args) = _resolveCommand(['--cache-dir', cacheDir]);

    // In python mode, verify the script exists before spawning
    if (exe == _pythonCmd && args.isNotEmpty && args[0].endsWith('.py')) {
      if (!File(args[0]).existsSync()) {
        final msg = '[ExpressionClassifier] Script not found: ${args[0]}';
        debugPrint(msg);
        _logDebug(msg);
        return false;
      }
    }

    _logDebug('Starting persistent classifier: $exe ${args.join(' ')}');
    try {
      _process = await Process.start(exe, args);
      
      // Listen to stderr for model loading status and progress
      _listenStderr(_process!);
      
      // Listen to stdout for classification results
      _listenStdout(_process!);

      // Handle unexpected process exit
      unawaited(_process!.exitCode.then((code) {
        if (!_isStopping) {
          _logDebug('Classifier process exited unexpectedly with code $code');
          _stopProcess();
        }
      }));

      return true;
    } catch (e) {
      _logDebug('Failed to start classifier: $e');
      return false;
    }
  }

  /// Streams stdout lines from the persistent process.
  void _listenStdout(Process process) {
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;

      _logDebug('stdout: $trimmed');

      try {
        final json = jsonDecode(trimmed) as Map<String, dynamic>;
        
        if (json.containsKey('emotion')) {
          final result = EmotionResult.fromJson(json);
          if (_pendingRequest != null && !_pendingRequest!.isCompleted) {
            _pendingRequest!.complete(result);
            _pendingRequest = null;
          }
        } else if (json.containsKey('error')) {
          _logDebug('Classification error from script: ${json['error']}');
          if (_pendingRequest != null && !_pendingRequest!.isCompleted) {
            _pendingRequest!.complete(const EmotionResult(emotion: 'neutral', confidence: 0.0));
            _pendingRequest = null;
          }
        }
      } catch (e) {
        _logDebug('Failed to decode stdout JSON: $e (Raw: $trimmed)');
      }
    });
  }

  void _stopProcess() {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _process?.kill();
    _process = null;
    if (_pendingRequest != null && !_pendingRequest!.isCompleted) {
      _pendingRequest!.completeError('Process stopped');
      _pendingRequest = null;
    }
  }

  void dispose() {
    _isStopping = true;
    _stopProcess();
  }



  @override
  Future<bool> isAvailable() async {
    if (_modelReady) return true;

    final (exe, args) = _resolveCommand([]);

    if (exe != _pythonCmd) {
      // Bundled binary — just check it exists
      return File(exe).existsSync();
    }

    // python path: verify both script and python binary exist
    if (args.isNotEmpty && args[0].endsWith('.py') && !File(args[0]).existsSync()) {
      return false;
    }
    try {
      final result = await Process.run(_pythonCmd, ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

/// Service that manages expression classification.
///
/// Selects the appropriate classifier based on [StorageService] settings
/// and provides a unified [classify] method.
class ExpressionClassifierService extends ChangeNotifier {
  final StorageService _storage;
  ExpressionClassifier? _activeClassifier;
  String _activeMode = 'llm';

  // Download progress tracking
  bool _isDownloading = false;
  OnnxDownloadProgress? _downloadProgress;
  bool _modelReady = false;

  ExpressionClassifierService(this._storage);

  String get activeMode => _activeMode;
  bool get isDownloading => _isDownloading;
  OnnxDownloadProgress? get downloadProgress => _downloadProgress;
  bool get modelReady => _modelReady;

  /// Returns true when the model cache directory has content.
  bool get isModelCached {
    final dir = Directory('${_storage.rootPath}/models/emotion_classifier');
    try {
      return dir.existsSync() && dir.listSync().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Initialize or re-initialize the classifier based on current settings.
  Future<void> ensureInitialized({
    required String Function() getCurrentEmotion,
    required Future<String> Function(String unknownEmotion) reclassify,
  }) async {
    final mode = _storage.expressionClassificationMode;
    if (mode == _activeMode && _activeClassifier != null) return;

    debugPrint('[ExpressionClassifierService] Switching from $_activeMode to $mode');
    
    // Clean up old classifier if it was persistent
    if (_activeClassifier is ONNXExpressionClassifier) {
      (_activeClassifier as ONNXExpressionClassifier).dispose();
    }
    
    _activeMode = mode;

    switch (mode) {
      case 'llm':
        _activeClassifier = LLMExpressionClassifier(
          getCurrentEmotion: getCurrentEmotion,
          reclassify: reclassify,
        );
        break;
      case 'onnx':
        final classifier = ONNXExpressionClassifier(
          storage: _storage,
          onProgress: (progress) {
            _isDownloading = true;
            _downloadProgress = progress;
            notifyListeners();
          },
          onModelReady: () {
            _isDownloading = false;
            _modelReady = true;
            notifyListeners();
          },
        );
        final isAvailable = await classifier.isAvailable();
        if (isAvailable) {
          _activeClassifier = classifier;
        } else {
          debugPrint('[ExpressionClassifierService] ONNX not available, falling back to LLM');
          _activeClassifier = LLMExpressionClassifier(
            getCurrentEmotion: getCurrentEmotion,
            reclassify: reclassify,
          );
          _activeMode = 'llm';
        }
        break;
      case 'manual':
        _activeClassifier = null;
        break;
      default:
        _activeClassifier = null;
    }

    notifyListeners();
  }

  /// Classify the emotion of [text] using the active classifier.
  ///
  /// Returns null if classification is disabled or in manual mode.
  Future<EmotionResult?> classify(String text) async {
    if (_activeClassifier == null) return null;
    return _activeClassifier!.classify(text);
  }

  /// Triggers a background download of the ONNX model.
  ///
  /// Creates a dedicated [ONNXExpressionClassifier] that runs the Python sidecar
  /// with [--download-only] so the model is cached to [storage.rootPath]/models/emotion_classifier.
  /// Progress is broadcast via [isDownloading] and [downloadProgress].
  /// Returns false immediately if a download is already in progress.
  Future<bool> triggerOnnxDownload() async {
    if (_isDownloading) return false;

    debugPrint('[ExpressionClassifierService] triggerOnnxDownload called');

    _isDownloading = true;
    _downloadProgress = null;
    notifyListeners();

    final classifier = ONNXExpressionClassifier(
      storage: _storage,
      onProgress: (progress) {
        _downloadProgress = progress;
        notifyListeners();
      },
      onModelReady: () {
        _isDownloading = false;
        _modelReady = true;
        notifyListeners();
      },
    );

    if (!await classifier.isAvailable()) {
      debugPrint('[ExpressionClassifierService] Classifier not available (python3 or script missing)');
      _isDownloading = false;
      notifyListeners();
      return false;
    }

    // Fire-and-forget — callbacks handle all state transitions
    classifier.downloadModel().then((_) {
      // Guard: if onModelReady was never fired (already cached), finalize here
      if (_isDownloading) {
        _isDownloading = false;
        _modelReady = true;
        notifyListeners();
      }
    }).catchError((Object e) {
      debugPrint('[ExpressionClassifierService] Download error: $e');
      _isDownloading = false;
      notifyListeners();
    });

    return true;
  }

  @override
  void dispose() {
    if (_activeClassifier is ONNXExpressionClassifier) {
      (_activeClassifier as ONNXExpressionClassifier).dispose();
    }
    super.dispose();
  }
}
