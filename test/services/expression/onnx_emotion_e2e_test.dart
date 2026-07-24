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

// Full-pipeline verification of the in-process emotion classifier against
// the REAL Cohee/distilbert-base-uncased-go-emotions-onnx model: text →
// WordPiece → ONNX → softmax → label. Expected values were produced by the
// Python sidecar stack (transformers + onnxruntime + numpy) on 2026-07-16.
//
// SKIPS unless FP_EMOTION_TEST_MODEL points at a local model.onnx (268MB —
// never committed) AND the onnxruntime native library is loadable (e.g.
// LD_LIBRARY_PATH containing a libonnxruntime.so on Linux). CI stays green
// without either; run locally to re-verify the full stack.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/expression/onnx_emotion_engine.dart';

void main() {
  final modelPath = Platform.environment['FP_EMOTION_TEST_MODEL'];
  final available = modelPath != null && File(modelPath).existsSync();

  test(
    'real-model classification matches the Python sidecar stack',
    () async {
      Future<List<(String, double)>> run(String text) =>
          OnnxEmotionEngine.classify(
            modelPath: modelPath!,
            vocabPath: 'test/fixtures/emotion_classifier/vocab.txt',
            text: text,
          );

      const cases = <String, (String, double)>{
        "I'm so happy right now!": ('excitement', 0.2153),
        'This is absolutely disgusting and I hate it.': ('disgust', 0.5247),
        'Thank you so much, that means the world to me.': ('gratitude', 0.3434),
        'wait... what just happened?': ('confusion', 0.3426),
        "NO!!! Don't touch that!!": ('disapproval', 0.2407),
        "*sighs softly* It's been a long day on the porch, hasn't it?": (
          'sadness',
          0.4345,
        ),
      };

      for (final entry in cases.entries) {
        final scored = await run(entry.key);
        expect(scored.first.$1, entry.value.$1, reason: entry.key);
        // fp32 inference vs the Python reference can differ in the last
        // decimal; 1e-3 pins the distribution without flaking.
        expect(
          scored.first.$2,
          closeTo(entry.value.$2, 0.001),
          reason: entry.key,
        );
      }
    },
    skip: available ? false : 'FP_EMOTION_TEST_MODEL not set — skipping',
  );
}
