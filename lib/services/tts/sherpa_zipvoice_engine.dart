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
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:front_porch_ai/services/engine_health.dart';
import 'package:front_porch_ai/services/model_fetch.dart';
import 'package:front_porch_ai/services/sherpa_runtime.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_engine.dart';
import 'package:front_porch_ai/services/tts_voice_info.dart';

/// Zero-shot voice cloning via sherpa-onnx ZipVoice.
///
/// Each generation request reads a reference .wav plus its exact transcript
/// (a sibling `<ref>.txt` file) and reads the target text aloud in that
/// voice — no pre-trained speaker is needed.
///
/// Model bundle (downloaded once): zipvoice-distill-int8 + vocos vocoder.
class SherpaZipVoiceEngine implements TtsEngine {
  final StorageService _storageService;
  SherpaZipVoiceEngine(this._storageService);

  static const bundleUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia.tar.bz2';

  static const vocoderUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models/vocos_24khz.onnx';

  /// Generation quality (ear-test default: fast, ~2.3s per short clone).
  static const int numSteps = 4;

  static const _modelFiles = [
    'tokens.txt',
    'encoder.int8.onnx',
    'decoder.int8.onnx',
    'vocos_24khz.onnx',
    'lexicon.txt',
  ];

  static String modelDir(String root) =>
      p.join(root, 'system', 'zipvoice_models', 'sherpa-v1_0');

  static bool isModelPresent(String root) {
    final dir = modelDir(root);
    return _modelFiles.every((f) => File(p.join(dir, f)).existsSync()) &&
        Directory(p.join(dir, 'espeak-ng-data')).existsSync();
  }

  static Future<void> downloadModel(
    String root, {
    void Function(double fraction)? onProgress,
  }) async {
    await ModelFetch.fetchAndExtractTarBz2(
      bundleUrl,
      modelDir(root),
      onProgress: (fraction) {
        onProgress?.call(fraction * 0.85);
      },
    );
    onProgress?.call(0.85);
    // Download vocoder separately
    final vocoderDest = File(p.join(modelDir(root), 'vocos_24khz.onnx'));
    if (!vocoderDest.existsSync()) {
      await ModelFetch.fetch(
        vocoderUrl,
        vocoderDest,
        onProgress: (done, total) {
          if (total > 0) {
            onProgress?.call(0.85 + 0.15 * done / total);
          }
        },
      );
    }
    onProgress?.call(1.0);
    if (!isModelPresent(root)) {
      throw const FormatException('zipvoice bundle extraction incomplete');
    }
  }

  /// Sibling-transcript rule: the reference transcript lives in a .txt file
  /// with the same name as the reference WAV (reference.wav → reference.txt).
  static String? transcriptPathFor(String refPath) {
    final txt = p.setExtension(refPath, '.txt');
    return File(txt).existsSync() ? txt : null;
  }

  // ---- Persistent worker isolate ----

  SendPort? _worker;
  Future<void>? _starting;
  Future<void> _jobChain = Future.value();

  String? referenceAudioPath;

  @override
  String get engineName => 'ZipVoice TTS';

  @override
  String get engineId => 'zipvoice';

  @override
  Future<bool> get isAvailable async {
    final root = _storageService.rootPath;
    if (root == null) return false;
    try {
      return isModelPresent(root);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> ensureModelReady({void Function(double)? onProgress}) async {
    final root = _storageService.rootPath;
    if (root == null) return false;
    if (isModelPresent(root)) return true;
    try {
      await downloadModel(root, onProgress: onProgress);
      return isModelPresent(root);
    } catch (e) {
      print('[ZipVoice] model download failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.zipvoice,
        'model download failed: $e',
      );
      return false;
    }
  }

  @override
  List<TtsVoiceInfo> get availableVoices => [
    TtsVoiceInfo(
      id: 'zipvoice-default',
      name: 'Zero-shot (from reference audio)',
      gender: 'Unknown',
      language: 'en',
      engine: 'zipvoice',
    ),
  ];

  Future<void> _warmUp(String root) {
    if (_worker != null) return Future.value();
    return _starting ??= _spawn(root).then((port) {
      _worker = port;
      _starting = null;
    });
  }

  static Future<SendPort> _spawn(String root) async {
    final dir = modelDir(root);
    final libDir = sherpaNativeLibDir();
    final ready = ReceivePort();
    await Isolate.spawn(_workerMain, [ready.sendPort, dir, libDir]);
    final first = await ready.first;
    ready.close();
    if (first is String) throw StateError(first);
    return first as SendPort;
  }

  @override
  Future<File?> generateAudio(
    String text,
    String voice,
    double speed, {
    void Function(double progress)? onProgress,
  }) async {
    final root = _storageService.rootPath;
    if (root == null) return null;
    if (!isModelPresent(root)) {
      EngineHealth.instance.reportFailure(
        EngineHealth.zipvoice,
        'model not downloaded',
        expected: true,
      );
      return null;
    }

    final refPath = referenceAudioPath;
    if (refPath == null || refPath.isEmpty) {
      EngineHealth.instance.reportFailure(
        EngineHealth.zipvoice,
        'no reference audio configured',
        expected: true,
      );
      return null;
    }

    if (!File(refPath).existsSync()) {
      EngineHealth.instance.reportFailure(
        EngineHealth.zipvoice,
        'reference audio not found',
        expected: true,
      );
      return null;
    }

    // ZipVoice requires the exact transcript of the reference audio, loaded
    // from a sibling .txt file. Fail loudly so the UI can tell the user.
    final transcriptPath = transcriptPathFor(refPath);
    if (transcriptPath == null) {
      final required = '${p.basenameWithoutExtension(refPath)}.txt';
      EngineHealth.instance.reportFailure(
        EngineHealth.zipvoice,
        'transcript missing: create "$required" next to the reference WAV',
        expected: true,
      );
      throw StateError(
        'ZipVoice needs a transcript: create "$required" next to the '
        'reference WAV (e.g. reference.wav + reference.txt).',
      );
    }
    final referenceTranscript =
        (await File(transcriptPath).readAsString()).trim();

    final result = _jobChain.then((_) async {
      await _warmUp(root);
      final reply = ReceivePort();
      _worker!.send([
        reply.sendPort,
        text,
        speed,
        refPath,
        referenceTranscript,
      ]);
      final res = await reply.first;
      reply.close();
      if (res is String) {
        throw StateError(res);
      }
      final outputPath = (res as List).first as String;
      EngineHealth.instance.reportNative(EngineHealth.zipvoice);
      return File(outputPath);
    });
    _jobChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  void shutdown() {
    _worker?.send(null);
    _worker = null;
    _starting = null;
  }

  static void _workerMain(List<Object?> args) {
    final replyTo = args[0] as SendPort;
    final dir = args[1] as String;
    final libDir = args[2] as String?;
    sherpa.OfflineTts tts;
    try {
      sherpa.initBindings(libDir);
      tts = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            zipvoice: sherpa.OfflineTtsZipVoiceModelConfig(
              tokens: p.join(dir, 'tokens.txt'),
              encoder: p.join(dir, 'encoder.int8.onnx'),
              decoder: p.join(dir, 'decoder.int8.onnx'),
              vocoder: p.join(dir, 'vocos_24khz.onnx'),
              dataDir: p.join(dir, 'espeak-ng-data'),
              lexicon: p.join(dir, 'lexicon.txt'),
            ),
            numThreads: math.max(1, Platform.numberOfProcessors ~/ 2),
            debug: false,
          ),
        ),
      );
    } catch (e) {
      replyTo.send('zipvoice model load failed: $e');
      return;
    }

    final jobs = ReceivePort();
    replyTo.send(jobs.sendPort);

    // Cache the last reference .wav samples so we don't re-read + re-parse
    // the same file on every generation call (the reference never changes
    // mid-conversation).
    String? _cachedRefPath;
    Float32List? _cachedRefSamples;
    int _cachedRefSampleRate = 0;

    jobs.listen((msg) {
      if (msg == null) {
        tts.free();
        jobs.close();
        return;
      }
      final job = msg as List<Object?>;
      final reply = job[0] as SendPort;
      try {
        final refPath = job[3] as String;
        Float32List refSamples;
        int refSampleRate;
        if (refPath == _cachedRefPath) {
          refSamples = _cachedRefSamples!;
          refSampleRate = _cachedRefSampleRate;
        } else {
          final refWav = sherpa.readWave(refPath);
          if (refWav.samples.isEmpty) {
            throw StateError('empty reference audio');
          }
          _cachedRefPath = refPath;
          _cachedRefSamples = refWav.samples;
          _cachedRefSampleRate = refWav.sampleRate;
          refSamples = refWav.samples;
          refSampleRate = refWav.sampleRate;
        }
        final audio = tts.generateWithConfig(
          text: job[1] as String,
          config: sherpa.OfflineTtsGenerationConfig(
            referenceAudio: refSamples,
            referenceSampleRate: refSampleRate,
            referenceText: job[4] as String,
            sid: 0,
            speed: job[2] as double,
            numSteps: SherpaZipVoiceEngine.numSteps,
            extra: <String, Object>{
              'min_char_in_sentence': 10,
              'guidance_scale': 2.0,
            },
          ),
        );
        if (audio.samples.isEmpty) {
          throw StateError('empty audio generated');
        }
        final outputPath = p.join(
          Directory.systemTemp.path,
          'zipvoice_tts_${DateTime.now().millisecondsSinceEpoch}.wav',
        );
        final ok = sherpa.writeWave(
          filename: outputPath,
          samples: audio.samples,
          sampleRate: audio.sampleRate,
        );
        if (!ok) throw StateError('failed to write wav');

        reply.send([outputPath]);
      } catch (e) {
        reply.send('zipvoice generate failed: $e');
      }
    });
  }
}
