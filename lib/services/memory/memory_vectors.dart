// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure vector / text helpers shared by RAG embed and retrieve.

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Maximum characters per embedding window. Embedding models have limited
/// context, and large texts are very slow on CPU ONNX. 2000 chars ≈ 500 tokens.
const int kMaxEmbedChars = 2000;

/// Strip reasoning and truncate for embedding.
///
/// A closed-block-only strip left an unclosed `<think>` tail in the text,
/// which then became a stored memory: the character could later "remember"
/// the model's deliberation as something that happened.
String cleanForEmbedding(String text) {
  final cleaned = stripThinkTags(text);
  if (cleaned.length <= kMaxEmbedChars) return cleaned;
  return cleaned.substring(0, kMaxEmbedChars);
}

/// Re-check only while the engine is down so a retrieve/embed during
/// download cannot latch "dead" after files land (audit P1.8). Once
/// live, skip — [EmbeddingService.isAvailable] is the live flag.
Future<void> ensureEmbeddingsReady(EmbeddingService embeddings) async {
  if (!embeddings.isAvailable) {
    debugPrint('[RAG:Memory] Checking embedding availability...');
    await embeddings.checkAvailability();
  }
}

/// Convert stored bytes back to a vector of doubles.
List<double>? bytesToVector(Uint8List bytes, int dimensions) {
  try {
    final floats = Float32List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      dimensions,
    );
    return floats.map((f) => f.toDouble()).toList();
  } catch (e) {
    debugPrint('[MemoryService] Failed to deserialize embedding: $e');
    return null;
  }
}

/// Cosine similarity between two vectors.
/// Returns a value between -1.0 and 1.0 (1.0 = identical direction).
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) return 0.0;

  double dotProduct = 0.0;
  double normA = 0.0;
  double normB = 0.0;

  for (int i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  final denominator = sqrt(normA) * sqrt(normB);
  if (denominator == 0.0) return 0.0;

  return dotProduct / denominator;
}
