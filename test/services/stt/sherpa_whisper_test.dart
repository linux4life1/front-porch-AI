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

// Phase-3 verification (docs/design/sidecar-retirement.md): pure unit tests
// for the silence trim always run; the full WAV→text pipeline runs against
// the real sherpa-onnx whisper export ONLY when FP_STT_TEST_MODEL_DIR
// points at a directory laid out like SherpaWhisperEngine.modelDir (plus a
// test 0.wav) and the sherpa native library is loadable (FP_SHERPA_LIB).
// The expected transcript is the reference trans.txt shipped with the
// upstream sherpa-onnx model export. Verified in-sandbox 2026-07-16.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/stt/sherpa_whisper_engine.dart';

void main() {
  group('trimSilence', () {
    Float32List tone({
      required double seconds,
      double amp = 0.5,
      int rate = 16000,
    }) {
      final n = (seconds * rate).round();
      return Float32List.fromList([
        for (var i = 0; i < n; i++)
          amp * math.sin(2 * math.pi * 440 * i / rate),
      ]);
    }

    test('all-silent audio trims to empty (→ "No speech detected")', () {
      expect(SherpaWhisperEngine.trimSilence(Float32List(16000)), isEmpty);
      expect(
        SherpaWhisperEngine.trimSilence(tone(seconds: 1.0, amp: 0.001)),
        isEmpty,
      );
    });

    test('too-short input trims to empty', () {
      expect(SherpaWhisperEngine.trimSilence(Float32List(100)), isEmpty);
    });

    test('leading/trailing silence is dropped, speech + padding kept', () {
      final samples = Float32List(16000 * 5);
      samples.setRange(32000, 48000, tone(seconds: 1.0));
      final out = SherpaWhisperEngine.trimSilence(samples);
      // 1s of speech + at most 0.3s padding each side.
      expect(out.length, greaterThanOrEqualTo(16000));
      expect(out.length, lessThanOrEqualTo(16000 + 2 * 4800 + 640));
    });

    test('speech-only input is preserved whole', () {
      final samples = tone(seconds: 2.0);
      final out = SherpaWhisperEngine.trimSilence(samples);
      expect(out.length, samples.length);
    });
  });

  group('decodeWav', () {
    // Builds a WAV around int16 PCM frames. extensible=true reproduces the
    // macOS recorder's WAVE_FORMAT_EXTENSIBLE 40-byte fmt chunk — the shape
    // sherpa's own reader rejects ("Expected subchunk1_size 16. Given: 40"),
    // which made every desktop dictation silently ride the Python sidecar.
    Uint8List buildWav(
      List<int> frames, {
      int channels = 1,
      int rate = 16000,
      bool extensible = false,
    }) {
      final fmtSize = extensible ? 40 : 16;
      final dataLen = frames.length * 2;
      final b = BytesBuilder();
      void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
      void u32(int v) =>
          b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
      b.add('RIFF'.codeUnits);
      u32(4 + 8 + fmtSize + 8 + dataLen);
      b.add('WAVE'.codeUnits);
      b.add('fmt '.codeUnits);
      u32(fmtSize);
      u16(extensible ? 0xFFFE : 1);
      u16(channels);
      u32(rate);
      u32(rate * channels * 2);
      u16(channels * 2);
      u16(16);
      if (extensible) {
        u16(22); // cbSize
        u16(16); // valid bits
        u32(0); // channel mask
        u16(1); // SubFormat: PCM
        b.add(List.filled(14, 0)); // rest of the GUID
      }
      b.add('data'.codeUnits);
      u32(dataLen);
      for (final f in frames) {
        u16(f & 0xFFFF);
      }
      return b.toBytes();
    }

    test('classic PCM16 mono decodes with correct rate and values', () async {
      final dir = await Directory.systemTemp.createTemp('stt_wav');
      try {
        final f = File('${dir.path}/classic.wav')
          ..writeAsBytesSync(buildWav([0, 16384, -16384, 32767]));
        final wave = SherpaWhisperEngine.decodeWav(f.path);
        expect(wave.sampleRate, 16000);
        expect(wave.samples, hasLength(4));
        expect(wave.samples[1], closeTo(0.5, 0.001));
        expect(wave.samples[2], closeTo(-0.5, 0.001));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('macOS extensible (fmt 40) decodes — the field-reported shape', () async {
      final dir = await Directory.systemTemp.createTemp('stt_wav');
      try {
        final f = File('${dir.path}/ext.wav')
          ..writeAsBytesSync(
            buildWav([8192, 8192, -8192, -8192], extensible: true),
          );
        final wave = SherpaWhisperEngine.decodeWav(f.path);
        expect(wave.sampleRate, 16000);
        expect(wave.samples, hasLength(4));
        expect(wave.samples.first, closeTo(0.25, 0.001));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('stereo downmixes to mono', () async {
      final dir = await Directory.systemTemp.createTemp('stt_wav');
      try {
        final f = File('${dir.path}/stereo.wav')
          ..writeAsBytesSync(
            buildWav([16384, 0, -16384, 0], channels: 2),
          );
        final wave = SherpaWhisperEngine.decodeWav(f.path);
        expect(wave.samples, hasLength(2));
        expect(wave.samples[0], closeTo(0.25, 0.001));
        expect(wave.samples[1], closeTo(-0.25, 0.001));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('garbage and truncated files yield empty samples', () async {
      final dir = await Directory.systemTemp.createTemp('stt_wav');
      try {
        final junk = File('${dir.path}/junk.wav')
          ..writeAsBytesSync(List.filled(64, 0x42));
        expect(SherpaWhisperEngine.decodeWav(junk.path).samples, isEmpty);
        expect(
          SherpaWhisperEngine.decodeWav('${dir.path}/missing.wav').samples,
          isEmpty,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  test('canDecode accepts WAV and rejects other containers', () async {
    final dir = await Directory.systemTemp.createTemp('stt_probe');
    try {
      final wav = File('${dir.path}/a.wav');
      wav.writeAsBytesSync([
        ...'RIFF'.codeUnits,
        4,
        0,
        0,
        0,
        ...'WAVE'.codeUnits,
      ]);
      final webm = File('${dir.path}/a.webm');
      webm.writeAsBytesSync([0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect(SherpaWhisperEngine.canDecode(wav.path), isTrue);
      expect(SherpaWhisperEngine.canDecode(webm.path), isFalse);
      expect(SherpaWhisperEngine.canDecode('${dir.path}/missing.wav'), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  final modelDir = Platform.environment['FP_STT_TEST_MODEL_DIR'];
  final available =
      modelDir != null && File('$modelDir/tiny.en-tokens.txt').existsSync();

  test(
    'real-model WAV→text matches the upstream reference transcript',
    () async {
      // modelDir is <root>/system/whisper_models/sherpa/tiny.en per
      // SherpaWhisperEngine.modelDir — the root is four levels up.
      final root = Directory(modelDir!).parent.parent.parent.parent.path;
      final text = await SherpaWhisperEngine.transcribe(
        root: root,
        size: 'tiny.en',
        audioPath: '$modelDir/0.wav',
      );
      final normalized = text
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z ]'), '')
          .trim();
      expect(
        normalized,
        'AFTER EARLY NIGHTFALL THE YELLOW LAMPS WOULD LIGHT UP HERE '
        'AND THERE THE SQUALID QUARTER OF THE BROTHELS',
      );
    },
    skip: available ? false : 'FP_STT_TEST_MODEL_DIR not set — skipping',
  );
}
