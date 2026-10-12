// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// A retrieved memory from the vector store.
class RetrievedMemory {
  final String content;
  final String? characterId;
  final String sessionId;
  final int positionStart;
  final int positionEnd;
  final double score; // cosine similarity 0.0–1.0

  const RetrievedMemory({
    required this.content,
    this.characterId,
    required this.sessionId,
    required this.positionStart,
    required this.positionEnd,
    required this.score,
  });

  /// Two-tier memory dedupe (living-time-features.md §8): drop retrievals
  /// whose span overlaps positions the Journal already expanded verbatim
  /// this turn — the exact lines are in the prompt once; twice is budget
  /// spent teaching the model to repeat itself. Pure; current-session only
  /// (cross-session sources use a different position space).
  static List<RetrievedMemory> excludingPositions(
    List<RetrievedMemory> memories,
    Set<int> positions, {
    required String currentSessionId,
  }) {
    if (positions.isEmpty) return memories;
    return [
      for (final m in memories)
        if (m.sessionId != currentSessionId ||
            !positions.any((p) => p >= m.positionStart && p <= m.positionEnd))
          m,
    ];
  }
}
