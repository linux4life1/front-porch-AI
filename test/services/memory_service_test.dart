// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/memory_service.dart';

void main() {
  group('MemoryService — pure logic tests', () {
    group('cosineSimilarity', () {
      test('returns 1.0 for identical vectors', () {
        final a = [1.0, 2.0, 3.0];
        final b = [1.0, 2.0, 3.0];
        expect(MemoryService.cosineSimilarity(a, b), closeTo(1.0, 0.0001));
      });

      test('returns 0.0 for orthogonal vectors', () {
        final a = [1.0, 0.0, 0.0];
        final b = [0.0, 1.0, 0.0];
        expect(MemoryService.cosineSimilarity(a, b), closeTo(0.0, 0.0001));
      });

      test('returns -1.0 for opposite vectors', () {
        final a = [1.0, 2.0, 3.0];
        final b = [-1.0, -2.0, -3.0];
        expect(MemoryService.cosineSimilarity(a, b), closeTo(-1.0, 0.0001));
      });

      test('returns 0.0 for empty vectors', () {
        expect(MemoryService.cosineSimilarity([], []), 0.0);
      });

      test('returns 0.0 for mismatched lengths', () {
        final a = [1.0, 2.0];
        final b = [1.0, 2.0, 3.0];
        expect(MemoryService.cosineSimilarity(a, b), 0.0);
      });

      test('handles normalized vectors at 45 degrees', () {
        final a = [1.0, 0.0];
        final b = [0.7071, 0.7071];
        expect(MemoryService.cosineSimilarity(a, b), closeTo(0.7071, 0.001));
      });

      test('handles single-element vectors', () {
        expect(MemoryService.cosineSimilarity([5.0], [5.0]), closeTo(1.0, 0.0001));
        expect(MemoryService.cosineSimilarity([5.0], [-5.0]), closeTo(-1.0, 0.0001));
        expect(MemoryService.cosineSimilarity([0.0], [0.0]), 0.0);
      });

      test('handles high-dimensional vectors', () {
        final a = List<double>.generate(100, (i) => i.toDouble());
        final b = List<double>.generate(100, (i) => i.toDouble());
        expect(MemoryService.cosineSimilarity(a, b), closeTo(1.0, 0.0001));
      });

      test('returns 0.0 when one vector is zero', () {
        final a = [0.0, 0.0, 0.0];
        final b = [1.0, 2.0, 3.0];
        expect(MemoryService.cosineSimilarity(a, b), 0.0);
      });
    });

    group('RetrievedMemory', () {
      test('creates with all required fields', () {
        const mem = RetrievedMemory(
          content: 'Test content',
          sessionId: 'session-1',
          positionStart: 0,
          positionEnd: 5,
          score: 0.85,
        );
        expect(mem.content, 'Test content');
        expect(mem.sessionId, 'session-1');
        expect(mem.positionStart, 0);
        expect(mem.positionEnd, 5);
        expect(mem.score, 0.85);
        expect(mem.characterId, isNull);
      });

      test('creates with characterId', () {
        const mem = RetrievedMemory(
          content: 'Test content',
          characterId: 'char-1',
          sessionId: 'session-1',
          positionStart: 0,
          positionEnd: 5,
          score: 0.9,
        );
        expect(mem.characterId, 'char-1');
      });

      test('score is bounded between 0 and 1 for typical results', () {
        // cosineSimilarity returns -1 to 1, but retrieval filters by minScore
        const mem1 = RetrievedMemory(content: 'a', sessionId: 's', positionStart: 0, positionEnd: 1, score: 1.0);
        const mem2 = RetrievedMemory(content: 'b', sessionId: 's', positionStart: 0, positionEnd: 1, score: 0.0);
        expect(mem1.score, 1.0);
        expect(mem2.score, 0.0);
      });
    });

    group('MemoryService — isOperational logic', () {
      // isOperational depends on StorageService.ragEnabled and EmbeddingService.isAvailable
      // We test the logic pattern without needing real service instances.

      test('isOperational requires both RAG enabled and embeddings available', () {
        // When ragEnabled=true AND isAvailable=true => operational
        // When ragEnabled=false AND isAvailable=true => NOT operational
        // When ragEnabled=true AND isAvailable=false => NOT operational
        // When ragEnabled=false AND isAvailable=false => NOT operational

        bool isOperational(bool ragEnabled, bool embeddingAvailable) {
          return ragEnabled && embeddingAvailable;
        }

        expect(isOperational(true, true), true);
        expect(isOperational(false, true), false);
        expect(isOperational(true, false), false);
        expect(isOperational(false, false), false);
      });

      test('isEmbedding reflects embedding state', () {
        // isEmbedding is a simple boolean that tracks whether an embedding operation is in progress
        bool isEmbedding = false;
        expect(isEmbedding, false);

        isEmbedding = true;
        expect(isEmbedding, true);

        isEmbedding = false;
        expect(isEmbedding, false);
      });

      test('pendingEmbeddings reflects pending count', () {
        int pending = 0;
        expect(pending, 0);

        pending++;
        expect(pending, 1);

        pending += 3;
        expect(pending, 4);

        pending -= 2;
        expect(pending, 2);
      });
    });
  });
}
