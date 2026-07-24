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

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:front_porch_ai/services/model_fetch.dart';
import 'package:front_porch_ai/services/sherpa_runtime.dart';

/// In-process Kokoro TTS via sherpa-onnx (phase 4 of
/// docs/design/sidecar-retirement.md). Replaces the kokoro_tts Python
/// worker pool with ONE persistent worker isolate holding the loaded
/// OfflineTts — same stays-warm behavior as the sidecar (ONNX intra-op
/// threading covers the parallelism the 1–4 process pool provided).
///
/// Models: the existing kokoro-v1.0.onnx + voices-v1.0.bin are NOT
/// loadable by sherpa (its export embeds required metadata and voices.bin
/// is its own binary format, not the kokoro-onnx npz) — a one-time
/// re-download of the sherpa kokoro-multi-lang-v1_0 bundle happens per the
/// retirement playbook, surfaced in Rawhide.md. Old files stay on disk
/// until the cleanup UI reclaims them. Voice NAMES are unchanged
/// (af_heart, bm_fable, …) — they map to sherpa speaker ids via
/// [speakerIds], so every character's saved voice keeps working (playbook
/// rule 5).
class SherpaKokoroEngine {
  /// Single-file bundle on sherpa's GitHub releases (same host the legacy
  /// engine already downloads its model from).
  static const bundleUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2';

  /// Voice name → sherpa speaker id for kokoro-multi-lang-v1_0, from the
  /// export's generate_voices_bin.py (scripts/kokoro/v1.0 in sherpa-onnx).
  static const Map<String, int> speakerIds = {
    'af_alloy': 0,
    'af_aoede': 1,
    'af_bella': 2,
    'af_heart': 3,
    'af_jessica': 4,
    'af_kore': 5,
    'af_nicole': 6,
    'af_nova': 7,
    'af_river': 8,
    'af_sarah': 9,
    'af_sky': 10,
    'am_adam': 11,
    'am_echo': 12,
    'am_eric': 13,
    'am_fenrir': 14,
    'am_liam': 15,
    'am_michael': 16,
    'am_onyx': 17,
    'am_puck': 18,
    'am_santa': 19,
    'bf_alice': 20,
    'bf_emma': 21,
    'bf_isabella': 22,
    'bf_lily': 23,
    'bm_daniel': 24,
    'bm_fable': 25,
    'bm_george': 26,
    'bm_lewis': 27,
    'ef_dora': 28,
    'em_alex': 29,
    'ff_siwis': 30,
    'hf_alpha': 31,
    'hf_beta': 32,
    'hm_omega': 33,
    'hm_psi': 34,
    'if_sara': 35,
    'im_nicola': 36,
    'jf_alpha': 37,
    'jf_gongitsune': 38,
    'jf_nezumi': 39,
    'jf_tebukuro': 40,
    'jm_kumo': 41,
    'pf_dora': 42,
    'pm_alex': 43,
    'pm_santa': 44,
    'zf_xiaobei': 45,
    'zf_xiaoni': 46,
    'zf_xiaoxiao': 47,
    'zf_xiaoyi': 48,
    'zm_yunjian': 49,
    'zm_yunxi': 50,
    'zm_yunxia': 51,
    'zm_yunyang': 52,
  };

  /// A `sherpa-v1_0/` sibling of the legacy kokoro_models files so the old
  /// model stays untouched until the post-soak cleanup UI.
  static String modelDir(String root) =>
      p.join(root, 'system', 'kokoro_models', 'sherpa-v1_0');

  static bool isModelPresent(String root) {
    final dir = modelDir(root);
    return File(p.join(dir, 'model.onnx')).existsSync() &&
        File(p.join(dir, 'voices.bin')).existsSync() &&
        File(p.join(dir, 'tokens.txt')).existsSync() &&
        Directory(p.join(dir, 'espeak-ng-data')).existsSync();
  }

  /// Downloads + extracts the tar.bz2 bundle via the shared
  /// [ModelFetch.fetchAndExtractTarBz2] (also used by the Piper engine).
  static Future<void> downloadModel(
    String root, {
    void Function(double fraction)? onProgress,
  }) async {
    await ModelFetch.fetchAndExtractTarBz2(
      bundleUrl,
      modelDir(root),
      onProgress: onProgress,
    );
    if (!isModelPresent(root)) {
      throw const FormatException('kokoro bundle extraction incomplete');
    }
  }

  // ---- Persistent worker isolate ----

  SendPort? _worker;
  Future<void>? _starting;
  Future<void> _jobChain = Future.value();

  /// Loads the model in the worker isolate ahead of the first generation
  /// (the "workers warm" equivalent). Safe to call repeatedly.
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
    if (first is String) throw StateError(first); // load error
    return first as SendPort;
  }

  /// Generates speech for [text] as a WAV at [outputPath]. Jobs are
  /// serialized (one model, one graph). Throws on failure — the caller
  /// owns the sidecar fallback.
  Future<File> generate({
    required String root,
    required String text,
    required String voice,
    required double speed,
    required String outputPath,
  }) {
    final result = _jobChain.then((_) async {
      await warmUp(root);
      final reply = ReceivePort();
      _worker!.send([
        reply.sendPort,
        text,
        speakerIds[voice] ?? speakerIds['af_heart']!,
        speed,
        outputPath,
      ]);
      final res = await reply.first;
      reply.close();
      if (res is String) throw StateError(res);
      return File(outputPath);
    });
    // Keep the chain alive even when a job fails.
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
            kokoro: sherpa.OfflineTtsKokoroModelConfig(
              model: p.join(dir, 'model.onnx'),
              voices: p.join(dir, 'voices.bin'),
              tokens: p.join(dir, 'tokens.txt'),
              dataDir: p.join(dir, 'espeak-ng-data'),
              dictDir: p.join(dir, 'dict'),
              lexicon:
                  '${p.join(dir, 'lexicon-us-en.txt')},'
                  '${p.join(dir, 'lexicon-zh.txt')}',
            ),
            numThreads: math.max(1, Platform.numberOfProcessors ~/ 2),
            // sherpa defaults debug to TRUE, which dumps every sentence's
            // full text + token ids to the terminal on each generation.
            debug: false,
          ),
        ),
      );
    } catch (e) {
      replyTo.send('kokoro model load failed: $e');
      return;
    }
    final jobs = ReceivePort();
    replyTo.send(jobs.sendPort);
    jobs.listen((msg) {
      if (msg == null) {
        tts.free();
        jobs.close();
        return;
      }
      final job = msg as List<Object?>;
      final reply = job[0] as SendPort;
      try {
        final audio = tts.generate(
          text: job[1] as String,
          sid: job[2] as int,
          speed: job[3] as double,
        );
        if (audio.samples.isEmpty) {
          throw StateError('empty audio');
        }
        final ok = sherpa.writeWave(
          filename: job[4] as String,
          samples: audio.samples,
          sampleRate: audio.sampleRate,
        );
        if (!ok) throw StateError('failed to write wav');
        reply.send(true);
      } catch (e) {
        reply.send('kokoro generate failed: $e');
      }
    });
  }
}
