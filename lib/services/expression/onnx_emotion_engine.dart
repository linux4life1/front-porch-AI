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

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime_v2/onnxruntime_v2.dart';

import '../onnx_runtime.dart';
import 'wordpiece_tokenizer.dart';

/// In-process go-emotions inference for the expression classifier:
/// WordPiece tokenize → DistilBERT ONNX → softmax → top-3 labels.
///
/// Replaces the Python `sentiment_classifier` sidecar (phase 2 of
/// docs/design/sidecar-retirement.md). Like the photo captioner
/// (smolvlm_engine.dart), the whole pipeline runs inside one spawned
/// isolate with synchronous native calls, and the session is released
/// before returning so the ~270MB of weights never linger between turns —
/// a better memory profile than the persistent sidecar process had.
///
/// NOTE: the sidecar's EMOTION_LABELS list had 26 entries for a 28-class
/// model (it was missing 'disapproval' and 'relief'), so every label after
/// 'disappointment' was reported shifted by one-then-two. [labels] below is
/// the model's true id2label order from its config.json — this path fixes
/// that bug rather than reproducing it.
class OnnxEmotionEngine {
  /// Canonical go-emotions label order of
  /// Cohee/distilbert-base-uncased-go-emotions-onnx (config.json id2label).
  static const List<String> labels = [
    'admiration',
    'amusement',
    'anger',
    'annoyance',
    'approval',
    'caring',
    'confusion',
    'curiosity',
    'desire',
    'disappointment',
    'disapproval',
    'disgust',
    'embarrassment',
    'excitement',
    'fear',
    'gratitude',
    'grief',
    'joy',
    'love',
    'nervousness',
    'optimism',
    'pride',
    'realization',
    'relief',
    'remorse',
    'sadness',
    'surprise',
    'neutral',
  ];

  /// Classifies [text]; returns `(label, confidence, top3)` sorted by score,
  /// with confidences rounded to 4 decimals like the sidecar's output.
  /// Throws on any failure — the caller owns the sidecar fallback.
  static Future<List<(String, double)>> classify({
    required String modelPath,
    required String vocabPath,
    required String text,
  }) {
    return Isolate.run(() => _classifyInIsolate(modelPath, vocabPath, text));
  }

  static List<(String, double)> _classifyInIsolate(
    String modelPath,
    String vocabPath,
    String text,
  ) {
    final tokenizer = WordPieceTokenizer(loadVocab(File(vocabPath)));
    final ids = tokenizer.encode(text);

    OrtEnv.instance.init();
    final opts = OrtSessionOptions()
      ..setIntraOpNumThreads(math.max(1, Platform.numberOfProcessors ~/ 2));
    OrtSession? session;
    OrtValueTensor? idsT, maskT;
    final ro = OrtRunOptions();
    List<OrtValue?>? outs;
    try {
      session = ortSessionFromFile(File(modelPath), opts);
      idsT = OrtValueTensor.createTensorWithDataList(Int64List.fromList(ids), [
        1,
        ids.length,
      ]);
      maskT = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(List.filled(ids.length, 1)),
        [1, ids.length],
      );
      outs = session.run(ro, {'input_ids': idsT, 'attention_mask': maskT});
      final nested = outs[0]!.value as List;
      final logits = [for (final v in nested[0] as List) (v as num).toDouble()];
      return topScores(logits);
    } finally {
      if (outs != null) {
        for (final v in outs) {
          v?.release();
        }
      }
      idsT?.release();
      maskT?.release();
      ro.release();
      session?.release();
      opts.release();
    }
  }

  /// Softmax over [logits] → all labels sorted by descending score,
  /// 4-decimal confidences (parity with the sidecar's `round(_, 4)`).
  static List<(String, double)> topScores(List<double> logits) {
    final maxL = logits.reduce(math.max);
    final exps = [for (final v in logits) math.exp(v - maxL)];
    final sum = exps.reduce((a, b) => a + b);
    final scored = <(String, double)>[
      for (var i = 0; i < logits.length; i++)
        (
          i < labels.length ? labels[i] : 'neutral',
          ((exps[i] / sum) * 10000).roundToDouble() / 10000,
        ),
    ];
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored;
  }

  /// Loads a WordPiece vocab from either a one-token-per-line `vocab.txt`
  /// or a HuggingFace `tokenizer.json` (its model.vocab map) — the sidecar's
  /// hub cache may contain only the latter, and reusing it avoids a
  /// re-download (sidecar-retirement playbook rule 3).
  static Map<String, int> loadVocab(File file) {
    final content = file.readAsStringSync();
    if (file.path.endsWith('.json')) {
      final root = jsonDecode(content) as Map<String, dynamic>;
      final vocab =
          (root['model'] as Map<String, dynamic>)['vocab']
              as Map<String, dynamic>;
      return vocab.map((k, v) => MapEntry(k, (v as num).toInt()));
    }
    final map = <String, int>{};
    final lines = const LineSplitter().convert(content);
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trimRight();
      if (t.isNotEmpty) map[t] = i;
    }
    return map;
  }
}
