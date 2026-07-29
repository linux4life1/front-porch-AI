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

// Phase-4b verification (docs/design/sidecar-retirement.md): the layout
// test always runs; the closed-loop test runs ONLY when FP_TTS_TEST_ROOT
// contains the sherpa vits-piper export for en_US-lessac-medium AND
// FP_STT_TEST_MODEL_DIR has the phase-3 whisper model — Piper speaks and
// Whisper transcribes it back. Verified in-sandbox 2026-07-16.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/stt/sherpa_whisper_engine.dart';
import 'package:front_porch_ai/services/tts/sherpa_piper_engine.dart';

void main() {
  const voice = 'en_US-lessac-medium';

  test('model layout probe requires onnx + tokens + espeak data', () async {
    final dir = await Directory.systemTemp.createTemp('piper_probe');
    try {
      expect(SherpaPiperEngine.isModelPresent(dir.path, voice), isFalse);
      final vd = Directory(SherpaPiperEngine.modelDir(dir.path, voice));
      vd.createSync(recursive: true);
      File('${vd.path}/$voice.onnx').writeAsBytesSync([0]);
      File('${vd.path}/tokens.txt').writeAsStringSync('a 1');
      expect(SherpaPiperEngine.isModelPresent(dir.path, voice), isFalse);
      Directory('${vd.path}/espeak-ng-data').createSync();
      expect(SherpaPiperEngine.isModelPresent(dir.path, voice), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  final root = Platform.environment['FP_TTS_TEST_ROOT'];
  final piperReady =
      root != null && SherpaPiperEngine.isModelPresent(root, voice);
  final whisperDir = Platform.environment['FP_STT_TEST_MODEL_DIR'];

  test(
    'closed loop: Piper speaks, Whisper transcribes it back',
    () async {
      final engine = SherpaPiperEngine();
      final out = '${Directory.systemTemp.path}/piper_loop_test.wav';
      try {
        final wav = await engine.generate(
          root: root!,
          voiceKey: voice,
          text:
              'After early nightfall the yellow lamps would light up '
              'here and there.',
          speed: 1.0,
          outputPath: out,
        );
        expect(wav.lengthSync(), greaterThan(50 * 1024));
        final sttRoot = Directory(whisperDir!).parent.parent.parent.parent.path;
        final text = await SherpaWhisperEngine.transcribe(
          root: sttRoot,
          size: 'tiny.en',
          audioPath: out,
        );
        final normalized = text
            .toUpperCase()
            .replaceAll(RegExp(r'[^A-Z ]'), '')
            .trim();
        expect(normalized, contains('YELLOW LAMPS WOULD LIGHT UP'));
      } finally {
        engine.shutdown();
        try {
          File(out).deleteSync();
        } catch (_) {}
      }
    },
    skip: (piperReady && whisperDir != null)
        ? false
        : 'FP_TTS_TEST_ROOT / FP_STT_TEST_MODEL_DIR not set — skipping',
  );

  test(
    'speed actually changes the audio (slider was a hardcoded no-op)',
    () async {
      // Regression for the Discord report: the worker hardcoded speed 1.0,
      // so the Speech Rate slider did nothing for every Piper voice. A
      // faster speaking rate must produce meaningfully shorter audio.
      final engine = SherpaPiperEngine();
      const text =
          'After early nightfall the yellow lamps would light up here and '
          'there the squalid quarter of the brothels.';
      final outNormal = '${Directory.systemTemp.path}/piper_speed_1_0.wav';
      final outFast = '${Directory.systemTemp.path}/piper_speed_1_6.wav';
      try {
        final normal = await engine.generate(
          root: root!,
          voiceKey: voice,
          text: text,
          speed: 1.0,
          outputPath: outNormal,
        );
        final fast = await engine.generate(
          root: root,
          voiceKey: voice,
          text: text,
          speed: 1.6,
          outputPath: outFast,
        );
        expect(
          fast.lengthSync(),
          lessThan((normal.lengthSync() * 0.85).round()),
          reason: '1.6x speech must be substantially shorter than 1.0x',
        );
      } finally {
        engine.shutdown();
        for (final f in [outNormal, outFast]) {
          try {
            File(f).deleteSync();
          } catch (_) {}
        }
      }
    },
    skip: piperReady ? false : 'FP_TTS_TEST_ROOT not set — skipping',
  );
}
