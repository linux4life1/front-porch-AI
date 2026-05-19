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

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:front_porch_ai/services/tts_engine.dart';
import 'package:front_porch_ai/services/tts_voice_info.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/kokoro_debug.dart';
import 'package:front_porch_ai/services/kokoro_worker_pool.dart';

/// Kokoro TTS engine — high-quality local TTS using kokoro-onnx.
///
/// Uses a Python subprocess with kokoro-onnx to generate audio.
/// Model files (~300MB) are downloaded on first use.
class KokoroEngine implements TtsEngine {
  final StorageService _storageService;
  KokoroEngine(this._storageService);
  static const _modelUrl =
      'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx';
  static const _voicesUrl =
      'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin';
  static int _fileCounter = 0;

  /// Pool of 1–4 resident Python workers (model loaded once, stays warm).
  KokoroWorkerPool? _pool;

  @override
  String get engineName => 'Kokoro';

  @override
  String get engineId => 'kokoro';

  /// Get the directory where Kokoro model files are stored.
  Future<String> get _modelDir async {
    final root = _storageService.rootPath ?? (await getApplicationDocumentsDirectory()).path;
    return p.join(root, 'system', 'kokoro_models');
  }

  /// Get the directory containing bundled TTS binaries.
  String get _piperDir {
    final execDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isMacOS) {
      final contentsDir = File(Platform.resolvedExecutable).parent.parent.path;
      return p.join(contentsDir, 'Resources', 'piper');
    }
    return p.join(execDir, 'piper');
  }

  /// Path to the kokoro_tts standalone binary (PyInstaller --onedir bundle).
  String get _wrapperScriptPath {
    if (Platform.isWindows) {
      return p.join(_piperDir, 'kokoro_tts', 'kokoro_tts.exe');
    }
    return p.join(_piperDir, 'kokoro_tts', 'kokoro_tts');
  }

  /// Whether the bundled wrapper script exists (release mode).
  bool get _hasWrapper {
    try { return File(_wrapperScriptPath).existsSync(); } catch (_) { return false; }
  }

  /// Find kokoro_tts.py — checks bundled piper/ dir first, then project root.
  String? get _helperScriptPath {
    // Bundled location (release)
    final bundled = p.join(_piperDir, 'kokoro_tts.py');
    if (File(bundled).existsSync()) return bundled;
    // Dev mode: look relative to executable up to project root
    final execDir = File(Platform.resolvedExecutable).parent.path;
    // Walk up from the build dir to find the project root kokoro_tts.py
    // macOS apps are deeply nested under build/macos/Build/Products/Debug/App.app/Contents/MacOS...
    var dir = Directory(execDir);
    for (int i = 0; i < 15; i++) {
      final candidate = File(p.join(dir.path, 'kokoro_tts.py'));
      if (candidate.existsSync()) return candidate.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    
    // Final fallback: the current working directory (usually root when running flutter run)
    final rootCandidate = File(p.join(Directory.current.path, 'kokoro_tts.py'));
    if (rootCandidate.existsSync()) return rootCandidate.path;
    
    return null;
  }

  /// Whether Kokoro is usable (either wrapper or python3 + helper script).
  bool get isEngineUsable => _hasWrapper || _helperScriptPath != null;

  @override
  Future<bool> get isAvailable async {
    try {
      if (!isEngineUsable) return false;
      final dir = await _modelDir;
      final modelFile = File(p.join(dir, 'kokoro-v1.0.onnx'));
      final voicesFile = File(p.join(dir, 'voices-v1.0.bin'));
      return modelFile.existsSync() && voicesFile.existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> ensureModelReady({void Function(double)? onProgress}) async {
    final dir = await _modelDir;
    await Directory(dir).create(recursive: true);

    final modelFile = File(p.join(dir, 'kokoro-v1.0.onnx'));
    final voicesFile = File(p.join(dir, 'voices-v1.0.bin'));

    if (modelFile.existsSync() && voicesFile.existsSync()) return true;

    try {
      // Download model (large ~300MB)
      if (!modelFile.existsSync()) {
        print('Kokoro: downloading model...');
        await _downloadFile(_modelUrl, modelFile, (p) {
          onProgress?.call(p * 0.95); // 95% for model
        });
      }

      // Download voices (small ~3MB)
      if (!voicesFile.existsSync()) {
        print('Kokoro: downloading voices...');
        await _downloadFile(_voicesUrl, voicesFile, (p) {
          onProgress?.call(0.95 + p * 0.05); // Last 5%
        });
      }

      onProgress?.call(1.0);
      return modelFile.existsSync() && voicesFile.existsSync();
    } catch (e) {
      print('Kokoro model download error: $e');
      return false;
    }
  }

  Future<void> _downloadFile(
      String url, File dest, void Function(double) onProgress) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = dest.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress(receivedBytes / totalBytes);
        }
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// Spawns one persistent kokoro_tts worker process (either the PyInstaller
  /// bundle or python3 + script in dev). Used by the worker pool.
  Future<Process> _spawnWorkerProcess() async {
    if (_hasWrapper) {
      return Process.start(_wrapperScriptPath, []);
    }

    final helperPath = _helperScriptPath;
    if (helperPath == null) {
      throw Exception('No kokoro_tts wrapper or helper script found');
    }

    final sep = Platform.isWindows ? ';' : ':';
    final paths = <String>[_piperDir];
    final homeDir = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (homeDir.isNotEmpty) {
      paths.add(p.join(homeDir, '.local', 'share', 'kokoro-tts-deps'));
    }
    final pythonPath = paths.join(sep);
    final pythonCmd = Platform.isWindows ? 'python' : 'python3';

    return Process.start(
      pythonCmd,
      [helperPath],
      environment: {'PYTHONPATH': pythonPath},
      includeParentEnvironment: true,
    );
  }

  @override
  Future<File?> generateAudio(
    String text,
    String voice,
    double speed, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir = await _modelDir;
      final modelPath = p.join(dir, 'kokoro-v1.0.onnx');
      final voicesPath = p.join(dir, 'voices-v1.0.bin');

      if (!File(modelPath).existsSync() || !File(voicesPath).existsSync()) {
        print('Kokoro: model files not found');
        return null;
      }

      final lang = _voiceLang(voice);

      final tempDir = Directory.systemTemp;
      _fileCounter++;
      final outputFile = File(p.join(tempDir.path,
          'kokoro_tts_${DateTime.now().millisecondsSinceEpoch}_$_fileCounter.wav'));

      // Lazily create the resident worker pool (1–4 processes, model stays loaded).
      _pool ??= KokoroWorkerPool(_storageService, _spawnWorkerProcess);

      kDebugPrint('[KokoroEngine] Calling pool.generateAudio for voice=$voice');
      final wav = await _pool!.generateAudio(
        text: text,
        voice: voice,
        speed: speed,
        lang: lang,
        outputPath: outputFile.path,
        modelPath: modelPath,
        voicesPath: voicesPath,
        onProgress: onProgress,
      );

      return wav;
    } catch (e) {
      print('Kokoro error: $e');
      return null;
    }
  }

  /// Shut down any resident workers. Safe to call multiple times.
  Future<void> shutdown() async {
    await _pool?.shutdown();
    _pool = null;
  }

  /// Eagerly start the configured number of workers in the background.
  /// This makes the first audio start much faster (avoids lazy model loading on first speak).
  ///
  /// This method is a no-op if TTS is globally disabled, to avoid unnecessarily
  /// loading the large Kokoro model into memory when the user has turned TTS off.
  Future<void> ensureWorkersWarm() async {
    if (!_storageService.ttsEnabled) {
      kDebugPrint('[KokoroEngine] ensureWorkersWarm skipped (TTS disabled)');
      return;
    }

    kDebugPrint('[KokoroEngine] ensureWorkersWarm called (ttsConcurrency=${_storageService.ttsConcurrency})');
    _pool ??= KokoroWorkerPool(_storageService, _spawnWorkerProcess);
    await _pool!.warmUp();
  }

  /// Map voice name prefix to language code for kokoro-onnx.
  String _voiceLang(String voice) {
    if (voice.startsWith('a')) return 'en-us';
    if (voice.startsWith('b')) return 'en-gb';
    if (voice.startsWith('e')) return 'es';
    if (voice.startsWith('f')) return 'fr-fr';
    if (voice.startsWith('h')) return 'hi';
    if (voice.startsWith('i')) return 'it';
    if (voice.startsWith('j')) return 'ja';
    if (voice.startsWith('p')) return 'pt-br';
    if (voice.startsWith('z')) return 'cmn';
    return 'en-us';
  }

  @override
  List<TtsVoiceInfo> get availableVoices => _voices;

  /// Built-in Kokoro voice catalog.
  static const _voices = [
    // American English — Female
    TtsVoiceInfo(id: 'af_heart', name: 'Heart', gender: 'Female', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'af_alloy', name: 'Alloy', gender: 'Female', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'af_aoede', name: 'Aoede', gender: 'Female', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'af_bella', name: 'Bella', gender: 'Female', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'af_jessica', name: 'Jessica', gender: 'Female', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'af_kore', name: 'Kore', gender: 'Female', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'af_nicole', name: 'Nicole', gender: 'Female', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'af_nova', name: 'Nova', gender: 'Female', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'af_river', name: 'River', gender: 'Female', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'af_sarah', name: 'Sarah', gender: 'Female', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'af_sky', name: 'Sky', gender: 'Female', language: 'American English', engine: 'kokoro'),
    // American English — Male
    TtsVoiceInfo(id: 'am_adam', name: 'Adam', gender: 'Male', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'am_echo', name: 'Echo', gender: 'Male', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'am_eric', name: 'Eric', gender: 'Male', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'am_fenrir', name: 'Fenrir', gender: 'Male', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'am_liam', name: 'Liam', gender: 'Male', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'am_michael', name: 'Michael', gender: 'Male', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'am_onyx', name: 'Onyx', gender: 'Male', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'am_puck', name: 'Puck', gender: 'Male', language: 'American English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'am_santa', name: 'Santa', gender: 'Male', language: 'American English', engine: 'kokoro'),
    // British English — Female
    TtsVoiceInfo(id: 'bf_alice', name: 'Alice', gender: 'Female', language: 'British English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'bf_emma', name: 'Emma', gender: 'Female', language: 'British English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'bf_isabella', name: 'Isabella', gender: 'Female', language: 'British English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'bf_lily', name: 'Lily', gender: 'Female', language: 'British English', engine: 'kokoro'),
    // British English — Male
    TtsVoiceInfo(id: 'bm_daniel', name: 'Daniel', gender: 'Male', language: 'British English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'bm_fable', name: 'Fable', gender: 'Male', language: 'British English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'bm_george', name: 'George', gender: 'Male', language: 'British English', engine: 'kokoro'),
    TtsVoiceInfo(id: 'bm_lewis', name: 'Lewis', gender: 'Male', language: 'British English', engine: 'kokoro'),
    // Japanese
    TtsVoiceInfo(id: 'jf_alpha', name: 'Alpha', gender: 'Female', language: 'Japanese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'jf_gongitsune', name: 'Gongitsune', gender: 'Female', language: 'Japanese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'jm_beta', name: 'Beta', gender: 'Male', language: 'Japanese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'jm_kumo', name: 'Kumo', gender: 'Male', language: 'Japanese', engine: 'kokoro'),
    // Spanish
    TtsVoiceInfo(id: 'ef_dora', name: 'Dora', gender: 'Female', language: 'Spanish', engine: 'kokoro'),
    TtsVoiceInfo(id: 'em_alex', name: 'Alex', gender: 'Male', language: 'Spanish', engine: 'kokoro'),
    TtsVoiceInfo(id: 'em_santa', name: 'Santa', gender: 'Male', language: 'Spanish', engine: 'kokoro'),
    // French
    TtsVoiceInfo(id: 'ff_siwis', name: 'Siwis', gender: 'Female', language: 'French', engine: 'kokoro'),
    // Hindi
    TtsVoiceInfo(id: 'hf_alpha', name: 'Alpha', gender: 'Female', language: 'Hindi', engine: 'kokoro'),
    TtsVoiceInfo(id: 'hf_beta', name: 'Beta', gender: 'Female', language: 'Hindi', engine: 'kokoro'),
    TtsVoiceInfo(id: 'hm_omega', name: 'Omega', gender: 'Male', language: 'Hindi', engine: 'kokoro'),
    TtsVoiceInfo(id: 'hm_psi', name: 'Psi', gender: 'Male', language: 'Hindi', engine: 'kokoro'),
    // Italian
    TtsVoiceInfo(id: 'if_sara', name: 'Sara', gender: 'Female', language: 'Italian', engine: 'kokoro'),
    TtsVoiceInfo(id: 'im_nicola', name: 'Nicola', gender: 'Male', language: 'Italian', engine: 'kokoro'),
    // Brazilian Portuguese
    TtsVoiceInfo(id: 'pf_dora', name: 'Dora', gender: 'Female', language: 'Brazilian Portuguese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'pm_alex', name: 'Alex', gender: 'Male', language: 'Brazilian Portuguese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'pm_santa', name: 'Santa', gender: 'Male', language: 'Brazilian Portuguese', engine: 'kokoro'),
    // Mandarin Chinese
    TtsVoiceInfo(id: 'zf_xiaobei', name: 'Xiaobei', gender: 'Female', language: 'Mandarin Chinese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'zf_xiaoni', name: 'Xiaoni', gender: 'Female', language: 'Mandarin Chinese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'zf_xiaoxiao', name: 'Xiaoxiao', gender: 'Female', language: 'Mandarin Chinese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'zf_xiaoyi', name: 'Xiaoyi', gender: 'Female', language: 'Mandarin Chinese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'zm_yibo', name: 'Yibo', gender: 'Male', language: 'Mandarin Chinese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'zm_yunxi', name: 'Yunxi', gender: 'Male', language: 'Mandarin Chinese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'zm_yunxia', name: 'Yunxia', gender: 'Male', language: 'Mandarin Chinese', engine: 'kokoro'),
    TtsVoiceInfo(id: 'zm_yunyang', name: 'Yunyang', gender: 'Male', language: 'Mandarin Chinese', engine: 'kokoro'),
  ];
}
