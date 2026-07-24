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

// Cross-language goldens for the in-process RAG embedding engine (phase 5
// of docs/design/sidecar-retirement.md).
//
// The fixture vectors were captured LIVE from the Rust embed_server
// (fastembed 4, nomic-embed-text-v1.5) on 2026-07-18 — the exact stack that
// produced every embedding already sitting in users' memory databases. The
// native engine must reproduce them near-exactly: stored vectors and
// future query vectors have to keep speaking the same language, or RAG
// retrieval silently degrades with no visible error.
//
// Model-gated: runs only when the fastembed hub cache (or the app-managed
// native download) is present on this machine — skips in CI, verified on
// the dev Mac where the real 550MB model lives.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/embedding/native_embedding_engine.dart';

void main() {
  final files = NativeEmbeddingEngine.resolveModelFiles(null);
  // Outside a built app bundle the ORT dylib needs an explicit path
  // (FP_ORT_LIB, e.g. the onnxruntime_v2 pub-cache package's macos/ copy) —
  // without it the engine can't load and the test would error, not skip.
  final ortLib = Platform.environment['FP_ORT_LIB'] ?? '';
  final runnable = files != null && ortLib.isNotEmpty;

  test(
    'native engine reproduces the Rust server golden vectors',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'test/services/embedding/goldens/nomic_v15_rust_goldens.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
      expect(cases, isNotEmpty);

      final engine = NativeEmbeddingEngine();
      try {
        for (final c in cases) {
          final text = c['text'] as String;
          final golden = (c['embedding'] as List)
              .map((e) => (e as num).toDouble())
              .toList();
          final got = await engine.embed(
            modelPath: files!.model,
            vocabPath: files.vocab,
            text: text,
          );
          expect(got, hasLength(golden.length), reason: 'dims for "$text"');

          var dot = 0.0, maxAbs = 0.0;
          for (var i = 0; i < golden.length; i++) {
            dot += got[i] * golden[i];
            maxAbs = math.max(maxAbs, (got[i] - golden[i]).abs());
          }
          // Both vectors are L2-normalized, so the dot product IS the
          // cosine similarity. f32 inference vs the Rust server's f32,
          // accumulated in f64 here — agreement should be near-perfect.
          final label = text.length > 40 ? '${text.substring(0, 40)}…' : text;
          expect(
            dot,
            greaterThan(0.9999),
            reason: 'cosine drift for "$label" (maxAbsDiff=$maxAbs)',
          );
          expect(
            maxAbs,
            lessThan(5e-3),
            reason: 'component drift for "$label" (cosine=$dot)',
          );
        }
      } finally {
        engine.shutdown();
      }
    },
    skip: runnable
        ? false
        : 'needs the nomic model on disk AND FP_ORT_LIB pointing at '
              'libonnxruntime — skipping',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
