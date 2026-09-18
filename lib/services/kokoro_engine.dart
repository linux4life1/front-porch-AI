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
    if (!_storageService.ttsSettings.ttsEnabled) {
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
  List<TtsVoiceInfo> get availableVoices => catalog;

  /// The Kokoro voice catalog, derived from the model's own speaker table
  /// ([SherpaKokoroEngine.speakerIds]) so the picker can never again offer a
  /// voice the shipped model does not actually have.
  ///
  /// This used to be ~380 lines of hand-written entries, and it had drifted:
  /// it offered `jm_beta`, `em_santa` and `zm_yibo` — all labelled Male —
  /// which the model never contained, so choosing one silently synthesised
  /// `af_heart`, a female voice. It also hid `jf_nezumi`, `jf_tebukuro` and
  /// `zm_yunjian`, which the model does contain. Voice ids are
  /// self-describing (`<language><gender>_<name>`, so `am_adam` is American
  /// English, male), so the catalog falls out of the id list rather than
  /// restating it by hand.
  static final List<TtsVoiceInfo> catalog = _buildCatalog();

  static const Map<String, String> _languageByPrefix = {
    'a': 'American English',
    'b': 'British English',
    'e': 'Spanish',
    'f': 'French',
    'h': 'Hindi',
    'i': 'Italian',
    'j': 'Japanese',
    'p': 'Brazilian Portuguese',
    'z': 'Mandarin Chinese',
  };

  static List<TtsVoiceInfo> _buildCatalog() {
    final ids = SherpaKokoroEngine.speakerIds.keys.toList();
    // The model lists voices alphabetically; hoist the default so it stays the
    // first entry in the picker, the way the old hand-written list had it.
    if (ids.remove(SherpaKokoroEngine.defaultVoice)) {
      ids.insert(0, SherpaKokoroEngine.defaultVoice);
    }
    return List.unmodifiable(
      ids.map((id) {
        final shortName = id.substring(3);
        return TtsVoiceInfo(
          id: id,
          name: shortName[0].toUpperCase() + shortName.substring(1),
          gender: id[1] == 'm' ? 'Male' : 'Female',
          language: _languageByPrefix[id[0]] ?? 'Other',
          engine: 'kokoro',
        );
      }),
    );
  }
}
