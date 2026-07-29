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

/// In-process Piper TTS via sherpa-onnx (phase 4b of
/// docs/design/sidecar-retirement.md). Replaces the one-shot-per-chunk
/// PyInstaller `piper` binary with a persistent worker isolate holding the
/// loaded vits voice — strictly faster than a process spawn per chunk.
///
/// Models: sherpa cannot load raw piper `.onnx` voices (it needs its own
/// vits-piper re-exports with embedded metadata), but the re-export naming
/// is 1:1 with the rhasspy catalog the in-app voice manager uses:
/// voiceKey `en_US-lessac-medium` → bundle `vits-piper-en_US-lessac-medium`
/// on sherpa's GitHub releases. The matching bundle downloads on first
/// native use (~60–100MB incl. its own espeak-ng-data); voices with no
/// re-export (404) — e.g. hand-made user voices — cannot be played (the
/// legacy piper binary is gone) and surface a clear error instead.
class SherpaPiperEngine {
  static const _bundleBase =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

  static String modelDir(String root, String voiceKey) =>
      p.join(root, 'system', 'piper_models', 'sherpa', voiceKey);

  static bool isModelPresent(String root, String voiceKey) {
    final dir = modelDir(root, voiceKey);
    return File(p.join(dir, '$voiceKey.onnx')).existsSync() &&
        File(p.join(dir, 'tokens.txt')).existsSync() &&
        Directory(p.join(dir, 'espeak-ng-data')).existsSync();
  }

  /// Downloads the sherpa re-export for [voiceKey] if absent. Returns true
  /// when the voice is (now) present; false when no re-export EXISTS (404 —
  /// hand-made voices, the documented legacy-binary path). A failed
  /// download of an export that does exist THROWS, so callers can tell the
  /// expected degradation from a real failure (soak-signal purity).
  static Future<bool> ensureVoice(
    String root,
    String voiceKey, {
    void Function(double fraction)? onProgress,
  }) async {
    if (isModelPresent(root, voiceKey)) return true;
    try {
      await ModelFetch.fetchAndExtractTarBz2(
        '$_bundleBase/vits-piper-$voiceKey.tar.bz2',
        modelDir(root, voiceKey),
        onProgress: onProgress,
      );
      return isModelPresent(root, voiceKey);
    } on HttpException catch (e) {
      if (e.message.startsWith('HTTP 404')) {
        // ignore: avoid_print
        print('[TTS-Native] no sherpa export for piper voice $voiceKey');
        return false;
      }
      rethrow;
    }
  }

  // ---- Persistent worker isolate (one loaded voice at a time) ----

  SendPort? _worker;
  String? _loadedVoice;
  Future<void> _jobChain = Future.value();

  /// Generates [text] into a WAV at [outputPath] with the vits voice
  /// [voiceKey] (worker respawns when the voice changes) at [speed]
  /// (sherpa speaking-rate multiplier, 1.0 = normal — maps to the VITS
  /// length_scale internally). Throws on failure — the caller owns error
  /// reporting.
  Future<File> generate({
    required String root,
    required String voiceKey,
    required String text,
    required double speed,
    required String outputPath,
  }) {
    final result = _jobChain.then((_) async {
      if (_worker == null || _loadedVoice != voiceKey) {
        shutdown();
        _worker = await _spawn(modelDir(root, voiceKey), voiceKey);
        _loadedVoice = voiceKey;
      }
      final reply = ReceivePort();
      _worker!.send([reply.sendPort, text, outputPath, speed]);
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
    _loadedVoice = null;
  }

  static Future<SendPort> _spawn(String dir, String voiceKey) async {
    final ready = ReceivePort();
    await Isolate.spawn(_workerMain, [
      ready.sendPort,
      dir,
      voiceKey,
      sherpaNativeLibDir(),
    ]);
    final first = await ready.first;
    ready.close();
    if (first is String) throw StateError(first);
    return first as SendPort;
  }

  static void _workerMain(List<Object?> args) {
    final replyTo = args[0] as SendPort;
    final dir = args[1] as String;
    final voiceKey = args[2] as String;
    sherpa.OfflineTts tts;
    try {
      sherpa.initBindings(args[3] as String?);
      tts = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            vits: sherpa.OfflineTtsVitsModelConfig(
              model: p.join(dir, '$voiceKey.onnx'),
              tokens: p.join(dir, 'tokens.txt'),
              dataDir: p.join(dir, 'espeak-ng-data'),
            ),
            numThreads: math.max(1, Platform.numberOfProcessors ~/ 2),
            // sherpa defaults debug to TRUE, which dumps every sentence's
            // full text + token ids to the terminal on each generation.
            debug: false,
          ),
        ),
      );
    } catch (e) {
      replyTo.send('piper voice load failed: $e');
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
        // Speed was hardcoded to 1.0 here for the feature's whole life —
        // the settings slider was a silent no-op for every Piper voice.
        final audio = tts.generate(
          text: job[1] as String,
          sid: 0,
          speed: job[3] as double,
        );
        if (audio.samples.isEmpty) throw StateError('empty audio');
        final ok = sherpa.writeWave(
          filename: job[2] as String,
          samples: audio.samples,
          sampleRate: audio.sampleRate,
        );
        if (!ok) throw StateError('failed to write wav');
        reply.send(true);
      } catch (e) {
        reply.send('piper generate failed: $e');
      }
    });
  }

}
