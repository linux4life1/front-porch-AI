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

import 'package:front_porch_ai/services/model_fetch.dart';
import 'package:front_porch_ai/services/sherpa_runtime.dart';

/// In-process Whisper STT via sherpa-onnx (phase 3 of
/// docs/design/sidecar-retirement.md). Replaces the faster-whisper Python
/// sidecar, which was single-shot — it reloaded the CTranslate2 model on
/// EVERY transcription — so the isolate-run load-decode-free pattern here
/// (smolvlm/emotion precedent) is at worst behavior parity and in practice
/// faster (no interpreter startup).
///
/// Models: the sidecar's CTranslate2 files are NOT reusable — sherpa uses
/// its own ONNX export (`csukuangfj/sherpa-onnx-whisper-<size>` int8:
/// encoder + decoder + tokens). Same user-facing size names ('tiny.en',
/// 'base.en', 'small.en') so the settings value carries over; a one-time
/// re-download happens per the retirement playbook, surfaced in Rawhide.md.
///
/// Known divergence from the retired sidecar, documented + accepted: it ran
/// faster-whisper's VAD filter. Here a simple RMS energy trim drops
/// leading/trailing silence (and returns '' for all-silent clips, matching
/// VAD-drops-everything → "No speech detected"); mid-clip silence is left
/// to Whisper.
class SherpaWhisperEngine {
  static const _hfBase = 'https://huggingface.co/csukuangfj';

  static const _fileSuffixes = [
    'encoder.int8.onnx',
    'decoder.int8.onnx',
    'tokens.txt',
  ];

  /// Where the sherpa export for [size] lives — a `sherpa/` sibling of the
  /// sidecar's CT2 cache so the old files stay untouched until the
  /// post-soak cleanup UI offers to reclaim them.
  static String modelDir(String root, String size) =>
      p.join(root, 'system', 'whisper_models', 'sherpa', size);

  static bool isModelPresent(String root, String size) =>
      _fileSuffixes.every((s) {
        final f = File(p.join(modelDir(root, size), '$size-$s'));
        if (!f.existsSync()) return false;
        // The ONNX graphs are tens of MB; a few-KB file is a saved CDN
        // error page, not a model.
        final minBytes = s.endsWith('.onnx') ? 1024 * 1024 : 1;
        return f.lengthSync() >= minBytes;
      });

  /// True when the native path can decode [audioPath] — a RIFF/WAVE file
  /// (the desktop recorder always produces one). Browser-uploaded webm/ogg
  /// from the web UI stays on the sidecar until phase-3 completion.
  static bool canDecode(String audioPath) {
    try {
      final raf = File(audioPath).openSync();
      try {
        final h = raf.readSync(12);
        return h.length == 12 &&
            String.fromCharCodes(h.sublist(0, 4)) == 'RIFF' &&
            String.fromCharCodes(h.sublist(8, 12)) == 'WAVE';
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  /// Downloads the three-file sherpa export for [size] with one aggregate
  /// progress fraction across the set (encoder dominates the bytes).
  static Future<void> downloadModel(
    String root,
    String size, {
    void Function(double fraction)? onProgress,
  }) async {
    final dir = modelDir(root, size);
    final urls = [
      for (final s in _fileSuffixes)
        '$_hfBase/sherpa-onnx-whisper-$size/resolve/main/$size-$s',
    ];
    final sizes = [for (final u in urls) await ModelFetch.contentLength(u)];
    final overall = sizes.every((s) => s > 0)
        ? sizes.reduce((a, b) => a + b)
        : -1;
    var doneBefore = 0;
    for (var i = 0; i < urls.length; i++) {
      final dest = File(p.join(dir, '$size-${_fileSuffixes[i]}'));
      if (dest.existsSync() && dest.lengthSync() > 0) {
        doneBefore += sizes[i] > 0 ? sizes[i] : 0;
        continue;
      }
      final base = doneBefore;
      await ModelFetch.fetch(
        urls[i],
        dest,
        onProgress: (done, total) {
          if (overall > 0) onProgress?.call((base + done) / overall);
        },
      );
      doneBefore += sizes[i] > 0 ? sizes[i] : 0;
    }
    onProgress?.call(1.0);
  }

  /// Transcribes the WAV at [audioPath]; returns the text ('' for silence).
  /// Throws on any failure — the caller owns the sidecar fallback.
  static Future<String> transcribe({
    required String root,
    required String size,
    required String audioPath,
  }) {
    final dir = modelDir(root, size);
    final libDir = sherpaNativeLibDir();
    return Isolate.run(
      () => _transcribeInIsolate(dir, size, audioPath, libDir),
    );
  }

  static String _transcribeInIsolate(
    String dir,
    String size,
    String audioPath,
    String? libDir,
  ) {
    sherpa.initBindings(libDir);
    final wave = decodeWav(audioPath);
    if (wave.samples.isEmpty) {
      throw const FormatException('unreadable or empty WAV');
    }
    final trimmed = trimSilence(wave.samples, sampleRate: wave.sampleRate);
    if (trimmed.isEmpty) return '';

    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: p.join(dir, '$size-encoder.int8.onnx'),
          decoder: p.join(dir, '$size-decoder.int8.onnx'),
        ),
        tokens: p.join(dir, '$size-tokens.txt'),
        modelType: 'whisper',
        numThreads: math.max(1, Platform.numberOfProcessors ~/ 2),
        // sherpa defaults debug to TRUE, which dumps model internals to the
        // terminal on every transcription.
        debug: false,
      ),
    );
    final recognizer = sherpa.OfflineRecognizer(config);
    sherpa.OfflineStream? stream;
    try {
      stream = recognizer.createStream();
      stream.acceptWaveform(samples: trimmed, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream?.free();
      recognizer.free();
    }
  }

  /// Decodes a RIFF/WAVE file into mono float samples in [-1, 1].
  ///
  /// Exists because sherpa's readWave only accepts the classic 16-byte fmt
  /// chunk, but the macOS recorder writes WAVE_FORMAT_EXTENSIBLE (40-byte
  /// fmt) — which made EVERY desktop dictation fail native and ride the
  /// Python sidecar. Walks chunks (fmt sizes 16/18/40, other chunks
  /// skipped), accepts PCM16 and float32 (extensible SubFormat resolved),
  /// and downmixes multi-channel to mono. Returns empty samples on
  /// anything unreadable — callers treat that as "not a WAV".
  static ({Float32List samples, int sampleRate}) decodeWav(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      if (bytes.length < 44 ||
          String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
        return (samples: Float32List(0), sampleRate: 0);
      }
      final bd = ByteData.sublistView(bytes);
      var fmtTag = 0, channels = 0, sampleRate = 0, bits = 0;
      var dataStart = -1, dataLen = 0;
      var off = 12;
      while (off + 8 <= bytes.length) {
        final id = String.fromCharCodes(bytes.sublist(off, off + 4));
        final size = bd.getUint32(off + 4, Endian.little);
        final body = off + 8;
        if (body + size > bytes.length) break;
        if (id == 'fmt ' && size >= 16) {
          fmtTag = bd.getUint16(body, Endian.little);
          channels = bd.getUint16(body + 2, Endian.little);
          sampleRate = bd.getUint32(body + 4, Endian.little);
          bits = bd.getUint16(body + 14, Endian.little);
          if (fmtTag == 0xFFFE && size >= 40) {
            // Extensible: the real format is the SubFormat GUID's first
            // 16 bits (1 = PCM, 3 = IEEE float).
            fmtTag = bd.getUint16(body + 24, Endian.little);
          }
        } else if (id == 'data') {
          dataStart = body;
          dataLen = size;
        }
        off = body + size + (size.isOdd ? 1 : 0); // chunks are word-aligned
      }
      if (channels < 1 || sampleRate <= 0 || dataStart < 0 || dataLen < 1) {
        return (samples: Float32List(0), sampleRate: 0);
      }
      if (fmtTag == 1 && bits == 16) {
        final frames = dataLen ~/ (2 * channels);
        final out = Float32List(frames);
        for (var i = 0; i < frames; i++) {
          var acc = 0.0;
          for (var c = 0; c < channels; c++) {
            acc += bd.getInt16(
              dataStart + 2 * (i * channels + c),
              Endian.little,
            );
          }
          out[i] = (acc / channels) / 32768.0;
        }
        return (samples: out, sampleRate: sampleRate);
      }
      if (fmtTag == 3 && bits == 32) {
        final frames = dataLen ~/ (4 * channels);
        final out = Float32List(frames);
        for (var i = 0; i < frames; i++) {
          var acc = 0.0;
          for (var c = 0; c < channels; c++) {
            acc += bd.getFloat32(
              dataStart + 4 * (i * channels + c),
              Endian.little,
            );
          }
          out[i] = acc / channels;
        }
        return (samples: out, sampleRate: sampleRate);
      }
      return (samples: Float32List(0), sampleRate: 0);
    } catch (_) {
      return (samples: Float32List(0), sampleRate: 0);
    }
  }

  /// RMS-gate leading/trailing silence: 20ms frames, threshold at the
  /// greater of an absolute floor and 5% of the loudest frame, 0.3s of
  /// context kept on each side. Returns an empty list for all-silent audio
  /// so callers surface "No speech detected" instead of a Whisper
  /// hallucination.
  static Float32List trimSilence(
    Float32List samples, {
    int sampleRate = 16000,
  }) {
    final frame = sampleRate ~/ 50; // 20ms
    if (samples.length < frame) return Float32List(0);
    final n = samples.length ~/ frame;
    final rms = List<double>.generate(n, (i) {
      var sum = 0.0;
      for (var j = i * frame; j < (i + 1) * frame; j++) {
        sum += samples[j] * samples[j];
      }
      return math.sqrt(sum / frame);
    });
    final peak = rms.reduce(math.max);
    final threshold = math.max(0.004, peak * 0.05);
    var first = -1, last = -1;
    for (var i = 0; i < n; i++) {
      if (rms[i] >= threshold) {
        if (first < 0) first = i;
        last = i;
      }
    }
    if (first < 0) return Float32List(0);
    final pad = (0.3 * sampleRate) ~/ frame;
    final start = math.max(0, first - pad) * frame;
    final end = math.min(samples.length, (last + 1 + pad) * frame);
    return samples.sublist(start, end);
  }
}
