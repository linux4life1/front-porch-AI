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
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:front_porch_ai/services/model_fetch.dart';
import 'package:front_porch_ai/services/sherpa_runtime.dart';

/// In-process ZipVoice TTS via sherpa-onnx.
///
/// Zero-shot voice cloning: each generation request takes a reference .wav
/// file path and its exact transcript. The model clones the speaker's voice
/// from the reference and reads the target text aloud in that voice.
///
/// Model bundle (downloaded once): zipvoice-distill-int8 + vocos vocoder.
class SherpaZipVoiceEngine {
  static const bundleUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia.tar.bz2';

  static const vocoderUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models/vocos_24khz.onnx';

  static String modelDir(String root) =>
      p.join(root, 'system', 'zipvoice_models', 'sherpa-v1_0');

  static bool isModelPresent(String root) {
    final dir = modelDir(root);
    return File(p.join(dir, 'encoder.int8.onnx')).existsSync() &&
        File(p.join(dir, 'decoder.int8.onnx')).existsSync() &&
        File(p.join(dir, 'vocos_24khz.onnx')).existsSync() &&
        File(p.join(dir, 'tokens.txt')).existsSync() &&
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
      await ModelFetch.fetch(vocoderUrl, vocoderDest, onProgress: (done, total) {
        if (total > 0) {
          onProgress?.call(0.85 + 0.15 * done / total);
        }
      });
    }
    onProgress?.call(1.0);
    if (!isModelPresent(root)) {
      throw const FormatException('zipvoice bundle extraction incomplete');
    }
  }

  // ---- Persistent worker isolate ----

  SendPort? _worker;
  Future<void>? _starting;
  Future<void> _jobChain = Future.value();

  Future<void> warmUp(String root) {
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

  Future<File> generate({
    required String root,
    required String text,
    required double speed,
    required String referenceAudioPath,
    required String referenceTranscript,
    required String outputPath,
  }) {
    final result = _jobChain.then((_) async {
      await warmUp(root);
      final reply = ReceivePort();
      _worker!.send([
        reply.sendPort,
        text,
        speed,
        referenceAudioPath,
        referenceTranscript,
        outputPath,
      ]);
      final res = await reply.first;
      reply.close();
      if (res is String) throw StateError(res);
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

  /// Smooths transitions into silence gaps by applying a short fade-out
  /// at the end of each speech segment. Removes the breath/click artifact
  /// that ZipVoice sometimes inserts at sentence boundaries.
  static void _fadeSentenceBoundaries(List<double> samples, int sampleRate) {
    const silenceThreshold = 0.005;
    const minSilenceMs = 50;
    const fadeMs = 25;
    final minSilenceFrames = (minSilenceMs * sampleRate / 1000).round();
    final fadeFrames = (fadeMs * sampleRate / 1000).round();
    int i = 0;
    while (i < samples.length) {
      if (samples[i].abs() < silenceThreshold) {
        final silenceStart = i;
        while (i < samples.length && samples[i].abs() < silenceThreshold) {
          i++;
        }
        final silenceLength = i - silenceStart;
        if (silenceLength >= minSilenceFrames) {
          final fadeStart = (silenceStart - fadeFrames).clamp(0, silenceStart);
          final fadeLen = silenceStart - fadeStart;
          for (int j = 0; j < fadeLen; j++) {
            final t = j / fadeLen;
            samples[fadeStart + j] *= (1.0 - t * t);
          }
        }
      } else {
        i++;
      }
    }
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

    // Cache the last reference .wav samples in memory so we don't
    // re-read + re-parse the same file from disk on every generation
    // call (the reference never changes mid-conversation).
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
            numSteps: 4,
            extra: <String, Object>{
              'min_char_in_sentence': 10,
              'guidance_scale': 2.0,
            },
          ),
        );
        if (audio.samples.isEmpty) {
          throw StateError('empty audio');
        }
        // Post-process: fade-out speech just before silence gaps to
        // remove ZipVoice's breath/click artifact at sentence boundaries.
        try {
          _fadeSentenceBoundaries(audio.samples.cast<double>(), audio.sampleRate);
        } catch (e) {
          reply.send('zipvoice fade failed: $e');
          return;
        }
        final ok = sherpa.writeWave(
          filename: job[5] as String,
          samples: audio.samples,
          sampleRate: audio.sampleRate,
        );
        if (!ok) throw StateError('failed to write wav');
        reply.send(true);
      } catch (e) {
        reply.send('zipvoice generate failed: $e');
      }
    });
  }
}
