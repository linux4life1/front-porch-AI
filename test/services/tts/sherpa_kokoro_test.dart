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

// Phase-4 verification (docs/design/sidecar-retirement.md): the speaker-id
// map test always runs; the real-model tests run ONLY when
// FP_TTS_TEST_ROOT points at a root containing the sherpa kokoro bundle at
// SherpaKokoroEngine.modelDir. The closed-loop test additionally needs the
// phase-3 whisper model (FP_STT_TEST_MODEL_DIR): Kokoro SPEAKS a sentence
// and Whisper TRANSCRIBES it back — two retired sidecars verifying each
// other with no reference audio needed. Verified in-sandbox 2026-07-16.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/stt/sherpa_whisper_engine.dart';
import 'package:front_porch_ai/services/tts/sherpa_kokoro_engine.dart';

void main() {
  test('speaker-id map covers kokoro v1.0 and keeps legacy voice names', () {
    expect(SherpaKokoroEngine.speakerIds.length, 53);
    // Spot-check against sherpa's generate_voices_bin.py ordering.
    expect(SherpaKokoroEngine.speakerIds['af_heart'], 3);
    expect(SherpaKokoroEngine.speakerIds['am_adam'], 11);
    expect(SherpaKokoroEngine.speakerIds['bm_fable'], 25);
    expect(SherpaKokoroEngine.speakerIds['zm_yunyang'], 52);
    // ids are unique and dense 0..52
    final ids = SherpaKokoroEngine.speakerIds.values.toSet();
    expect(ids.length, 53);
    expect(ids.reduce((a, b) => a < b ? a : b), 0);
    expect(ids.reduce((a, b) => a > b ? a : b), 52);
  });

  final root = Platform.environment['FP_TTS_TEST_ROOT'];
  final kokoroReady = root != null && SherpaKokoroEngine.isModelPresent(root);
  final whisperDir = Platform.environment['FP_STT_TEST_MODEL_DIR'];

  test(
    'real-model generation produces plausible speech audio',
    () async {
      final engine = SherpaKokoroEngine();
      final out = '${Directory.systemTemp.path}/kokoro_native_test.wav';
      try {
        final wav = await engine.generate(
          root: root!,
          text: 'The porch light flickers over the quiet street.',
          voice: 'af_heart',
          speed: 1.0,
          outputPath: out,
        );
        expect(wav.existsSync(), isTrue);
        // ~3s of 24kHz 16-bit mono ≈ 150KB; anything above 50KB is real audio.
        expect(wav.lengthSync(), greaterThan(50 * 1024));
      } finally {
        engine.shutdown();
        try {
          File(out).deleteSync();
        } catch (_) {}
      }
    },
    skip: kokoroReady ? false : 'FP_TTS_TEST_ROOT not set — skipping',
  );

  test(
    'closed loop: Kokoro speaks, Whisper transcribes it back',
    () async {
      final engine = SherpaKokoroEngine();
      final out = '${Directory.systemTemp.path}/kokoro_loop_test.wav';
      try {
        await engine.generate(
          root: root!,
          text:
              'After early nightfall the yellow lamps would light up '
              'here and there.',
          voice: 'af_heart',
          speed: 1.0,
          outputPath: out,
        );
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
    skip: (kokoroReady && whisperDir != null)
        ? false
        : 'FP_TTS_TEST_ROOT / FP_STT_TEST_MODEL_DIR not set — skipping',
  );
}
