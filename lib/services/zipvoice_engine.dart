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

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:front_porch_ai/services/engine_health.dart';
import 'package:front_porch_ai/services/tts_engine.dart';
import 'package:front_porch_ai/services/tts_voice_info.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts/sherpa_zipvoice_engine.dart';

/// ZipVoice TTS engine — zero-shot voice cloning via sherpa-onnx.
///
/// Clones a voice from a reference .wav file + transcript provided per
/// character. Requires the ZipVoice model bundle (~165MB) downloaded once.
/// Falls back to Kokoro when no reference audio is configured for a character.
class ZipVoiceEngine implements TtsEngine {
  final StorageService _storageService;
  ZipVoiceEngine(this._storageService);

  final SherpaZipVoiceEngine _native = SherpaZipVoiceEngine();
  static int _fileCounter = 0;
  bool _modelReady = false;

  @override
  String get engineName => 'ZipVoice';

  @override
  String get engineId => 'zipvoice';

  Future<String> get _rootPath async =>
      _storageService.rootPath ??
      (await getApplicationDocumentsDirectory()).path;

  @override
  Future<bool> get isAvailable async {
    try {
      return SherpaZipVoiceEngine.isModelPresent(await _rootPath);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> ensureModelReady({void Function(double)? onProgress}) async {
    if (_modelReady) return true;
    final root = await _rootPath;
    if (SherpaZipVoiceEngine.isModelPresent(root)) {
      _modelReady = true;
      return true;
    }
    try {
      await SherpaZipVoiceEngine.downloadModel(root, onProgress: onProgress);
      _modelReady = SherpaZipVoiceEngine.isModelPresent(root);
      return _modelReady;
    } catch (e) {
      print('[TTS-Native] zipvoice bundle download failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.kokoro,
        'zipvoice bundle download failed: $e',
      );
      return false;
    }
  }

  @override
  Future<File?> generateAudio(
    String text,
    String voice,
    double speed, {
    void Function(double progress)? onProgress,
    String? referenceAudioPath,
    String? referenceTranscript,
  }) async {
    if (referenceAudioPath == null || referenceAudioPath.isEmpty) {
      print('[ZipVoiceEngine] no reference audio configured');
      return null;
    }
    if (!File(referenceAudioPath).existsSync()) {
      print('[ZipVoiceEngine] reference audio file not found: $referenceAudioPath');
      return null;
    }
    if (referenceTranscript == null || referenceTranscript.isEmpty) {
      print('[ZipVoiceEngine] no reference transcript configured');
      return null;
    }

    try {
      _fileCounter++;
      final outputPath = p.join(
        Directory.systemTemp.path,
        'zipvoice_tts_${DateTime.now().millisecondsSinceEpoch}_$_fileCounter.wav',
      );

      final root = await _rootPath;
      if (!_modelReady && !SherpaZipVoiceEngine.isModelPresent(root)) {
        EngineHealth.instance.reportFailure(
          EngineHealth.kokoro,
          'zipvoice model not downloaded',
          expected: true,
        );
        return null;
      }
      // ZipVoice over-emphasises exclamation marks — replace with
      // full stops for smoother prosody.
      // ZipVoice uses pinyin-style phonemization where "mye" is read
      // as /miɛ/ (me-yeh). Convert back from the TTS service's espeak-ng
      // friendly spelling to the pinyin-friendly "mai" (/maɪ/).
      var sanitized = text.replaceAll('!', '.').replaceAll('！', '.');
      sanitized = sanitized.replaceAll(RegExp(r'\bmye\b', caseSensitive: false), 'mai');
      sanitized = sanitized.replaceAll(RegExp(r'\bmy\b', caseSensitive: false), 'mai');
      final wav = await _native.generate(
        root: root,
        text: sanitized,
        speed: speed,
        referenceAudioPath: referenceAudioPath,
        referenceTranscript: referenceTranscript,
        outputPath: outputPath,
      );
      onProgress?.call(1.0);
      EngineHealth.instance.reportNative(EngineHealth.kokoro);
      return wav;
    } catch (e) {
      print('[TTS-Native] zipvoice generation failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.kokoro,
        'zipvoice generation failed: $e',
      );
      return null;
    }
  }

  /// Shut down the worker isolate.
  Future<void> shutdown() async {
    _native.shutdown();
  }

  Future<void> ensureWorkersWarm() async {
    if (!_storageService.ttsEnabled) return;
    final root = await _rootPath;
    if (!_modelReady && !SherpaZipVoiceEngine.isModelPresent(root)) return;
    try {
      await _native.warmUp(root);
    } catch (e) {
      print('[TTS-Native] zipvoice warm-up failed: $e');
    }
  }

  @override
  List<TtsVoiceInfo> get availableVoices => _voices;

  static const _voices = [
    TtsVoiceInfo(
      id: 'zipvoice',
      name: 'Cloned Voice (ZipVoice)',
      gender: 'Any',
      language: 'Any',
      engine: 'zipvoice',
    ),
  ];
}
