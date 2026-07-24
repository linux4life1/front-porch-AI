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
import 'package:front_porch_ai/services/kokoro_debug.dart';
import 'package:front_porch_ai/services/tts/sherpa_kokoro_engine.dart';

/// Kokoro TTS engine — high-quality local TTS, generated in-process by the
/// sherpa-onnx [SherpaKokoroEngine] (docs/design/sidecar-retirement.md
/// phase 4a — the Python worker pool is gone). The model bundle (~380MB
/// extracted) is downloaded on first use.
class KokoroEngine implements TtsEngine {
  final StorageService _storageService;
  KokoroEngine(this._storageService);

  final SherpaKokoroEngine _native = SherpaKokoroEngine();
  static int _fileCounter = 0;

  @override
  String get engineName => 'Kokoro';

  @override
  String get engineId => 'kokoro';

  Future<String> get _rootPath async =>
      _storageService.rootPath ??
      (await getApplicationDocumentsDirectory()).path;

  @override
  Future<bool> get isAvailable async {
    try {
      return SherpaKokoroEngine.isModelPresent(await _rootPath);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> ensureModelReady({void Function(double)? onProgress}) async {
    final root = await _rootPath;
    if (SherpaKokoroEngine.isModelPresent(root)) return true;
    try {
      await SherpaKokoroEngine.downloadModel(root, onProgress: onProgress);
      return SherpaKokoroEngine.isModelPresent(root);
    } catch (e) {
      print('[TTS-Native] kokoro bundle download failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.kokoro,
        'model bundle download failed: $e',
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
  }) async {
    try {
      _fileCounter++;
      final outputPath = p.join(
        Directory.systemTemp.path,
        'kokoro_tts_${DateTime.now().millisecondsSinceEpoch}_$_fileCounter.wav',
      );

      final root = await _rootPath;
      if (!SherpaKokoroEngine.isModelPresent(root)) {
        EngineHealth.instance.reportFailure(
          EngineHealth.kokoro,
          'voice model not downloaded',
          expected: true,
        );
        return null;
      }
      final wav = await _native.generate(
        root: root,
        text: text,
        voice: voice,
        speed: speed,
        outputPath: outputPath,
      );
      onProgress?.call(1.0);
      EngineHealth.instance.reportNative(EngineHealth.kokoro);
      return wav;
    } catch (e) {
      print('[TTS-Native] kokoro generation failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.kokoro,
        'generation failed: $e',
      );
      return null;
    }
  }

  /// Shut down the worker isolate. Safe to call multiple times.
  Future<void> shutdown() async {
    _native.shutdown();
  }

  /// Eagerly load the model into the worker isolate in the background so
  /// the first audio starts fast. No-op if TTS is globally disabled, to
  /// avoid holding the large Kokoro model in memory for nothing.
  Future<void> ensureWorkersWarm() async {
    if (!_storageService.ttsEnabled) {
      kDebugPrint('[KokoroEngine] ensureWorkersWarm skipped (TTS disabled)');
      return;
    }
    final root = await _rootPath;
    if (!SherpaKokoroEngine.isModelPresent(root)) return;
    try {
      await _native.warmUp(root);
    } catch (e) {
      print('[TTS-Native] kokoro warm-up failed: $e');
    }
  }

  @override
  List<TtsVoiceInfo> get availableVoices => _voices;

  /// Built-in Kokoro voice catalog.
  static const _voices = [
    // American English — Female
    TtsVoiceInfo(
      id: 'af_heart',
      name: 'Heart',
      gender: 'Female',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'af_alloy',
      name: 'Alloy',
      gender: 'Female',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'af_aoede',
      name: 'Aoede',
      gender: 'Female',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'af_bella',
      name: 'Bella',
      gender: 'Female',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'af_jessica',
      name: 'Jessica',
      gender: 'Female',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'af_kore',
      name: 'Kore',
      gender: 'Female',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'af_nicole',
      name: 'Nicole',
      gender: 'Female',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'af_nova',
      name: 'Nova',
      gender: 'Female',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'af_river',
      name: 'River',
      gender: 'Female',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'af_sarah',
      name: 'Sarah',
      gender: 'Female',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'af_sky',
      name: 'Sky',
      gender: 'Female',
      language: 'American English',
      engine: 'kokoro',
    ),
    // American English — Male
    TtsVoiceInfo(
      id: 'am_adam',
      name: 'Adam',
      gender: 'Male',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'am_echo',
      name: 'Echo',
      gender: 'Male',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'am_eric',
      name: 'Eric',
      gender: 'Male',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'am_fenrir',
      name: 'Fenrir',
      gender: 'Male',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'am_liam',
      name: 'Liam',
      gender: 'Male',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'am_michael',
      name: 'Michael',
      gender: 'Male',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'am_onyx',
      name: 'Onyx',
      gender: 'Male',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'am_puck',
      name: 'Puck',
      gender: 'Male',
      language: 'American English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'am_santa',
      name: 'Santa',
      gender: 'Male',
      language: 'American English',
      engine: 'kokoro',
    ),
    // British English — Female
    TtsVoiceInfo(
      id: 'bf_alice',
      name: 'Alice',
      gender: 'Female',
      language: 'British English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'bf_emma',
      name: 'Emma',
      gender: 'Female',
      language: 'British English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'bf_isabella',
      name: 'Isabella',
      gender: 'Female',
      language: 'British English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'bf_lily',
      name: 'Lily',
      gender: 'Female',
      language: 'British English',
      engine: 'kokoro',
    ),
    // British English — Male
    TtsVoiceInfo(
      id: 'bm_daniel',
      name: 'Daniel',
      gender: 'Male',
      language: 'British English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'bm_fable',
      name: 'Fable',
      gender: 'Male',
      language: 'British English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'bm_george',
      name: 'George',
      gender: 'Male',
      language: 'British English',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'bm_lewis',
      name: 'Lewis',
      gender: 'Male',
      language: 'British English',
      engine: 'kokoro',
    ),
    // Japanese
    TtsVoiceInfo(
      id: 'jf_alpha',
      name: 'Alpha',
      gender: 'Female',
      language: 'Japanese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'jf_gongitsune',
      name: 'Gongitsune',
      gender: 'Female',
      language: 'Japanese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'jm_beta',
      name: 'Beta',
      gender: 'Male',
      language: 'Japanese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'jm_kumo',
      name: 'Kumo',
      gender: 'Male',
      language: 'Japanese',
      engine: 'kokoro',
    ),
    // Spanish
    TtsVoiceInfo(
      id: 'ef_dora',
      name: 'Dora',
      gender: 'Female',
      language: 'Spanish',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'em_alex',
      name: 'Alex',
      gender: 'Male',
      language: 'Spanish',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'em_santa',
      name: 'Santa',
      gender: 'Male',
      language: 'Spanish',
      engine: 'kokoro',
    ),
    // French
    TtsVoiceInfo(
      id: 'ff_siwis',
      name: 'Siwis',
      gender: 'Female',
      language: 'French',
      engine: 'kokoro',
    ),
    // Hindi
    TtsVoiceInfo(
      id: 'hf_alpha',
      name: 'Alpha',
      gender: 'Female',
      language: 'Hindi',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'hf_beta',
      name: 'Beta',
      gender: 'Female',
      language: 'Hindi',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'hm_omega',
      name: 'Omega',
      gender: 'Male',
      language: 'Hindi',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'hm_psi',
      name: 'Psi',
      gender: 'Male',
      language: 'Hindi',
      engine: 'kokoro',
    ),
    // Italian
    TtsVoiceInfo(
      id: 'if_sara',
      name: 'Sara',
      gender: 'Female',
      language: 'Italian',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'im_nicola',
      name: 'Nicola',
      gender: 'Male',
      language: 'Italian',
      engine: 'kokoro',
    ),
    // Brazilian Portuguese
    TtsVoiceInfo(
      id: 'pf_dora',
      name: 'Dora',
      gender: 'Female',
      language: 'Brazilian Portuguese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'pm_alex',
      name: 'Alex',
      gender: 'Male',
      language: 'Brazilian Portuguese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'pm_santa',
      name: 'Santa',
      gender: 'Male',
      language: 'Brazilian Portuguese',
      engine: 'kokoro',
    ),
    // Mandarin Chinese
    TtsVoiceInfo(
      id: 'zf_xiaobei',
      name: 'Xiaobei',
      gender: 'Female',
      language: 'Mandarin Chinese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'zf_xiaoni',
      name: 'Xiaoni',
      gender: 'Female',
      language: 'Mandarin Chinese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'zf_xiaoxiao',
      name: 'Xiaoxiao',
      gender: 'Female',
      language: 'Mandarin Chinese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'zf_xiaoyi',
      name: 'Xiaoyi',
      gender: 'Female',
      language: 'Mandarin Chinese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'zm_yibo',
      name: 'Yibo',
      gender: 'Male',
      language: 'Mandarin Chinese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'zm_yunxi',
      name: 'Yunxi',
      gender: 'Male',
      language: 'Mandarin Chinese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'zm_yunxia',
      name: 'Yunxia',
      gender: 'Male',
      language: 'Mandarin Chinese',
      engine: 'kokoro',
    ),
    TtsVoiceInfo(
      id: 'zm_yunyang',
      name: 'Yunyang',
      gender: 'Male',
      language: 'Mandarin Chinese',
      engine: 'kokoro',
    ),
  ];
}
