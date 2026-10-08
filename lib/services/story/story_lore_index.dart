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

import 'dart:math';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/embedding_service.dart';

/// One lore entry and how well it matched a search.
typedef LoreHit = ({StoryLoreEntry entry, double score});

/// Finds the lore that matters for the beat being written.
///
/// Uses the in-process embedding model when it is set up; without it the
/// search degrades to word overlap, so lore still reaches the writer on a
/// machine that never downloaded the embedding model. Vectors are cached in
/// memory by text — they are cheap to recompute and would bloat the project
/// blob, which is rewritten after every beat.
class StoryLoreIndex {
  StoryLoreIndex(this._embeddings);

  final EmbeddingService? _embeddings;
  final Map<String, List<double>> _vectors = {};

  /// Long uploads are cut into entries of about this many characters.
  static const chunkChars = 900;

  bool get semantic => _embeddings?.isAvailable ?? false;

  static String _text(StoryLoreEntry e) => '${e.topic}. ${e.detail}';

  /// Lore the story has established by scene ([act], [scene]).
  static Iterable<StoryLoreEntry> knownAt(
    StoryProject project,
    int act,
    int scene,
  ) => project.lore.where(
    (e) =>
        e.validFromAct < act + 1 ||
        (e.validFromAct == act + 1 && e.validFromScene <= scene + 1),
  );

  Future<List<double>?> _embed(String text) async {
    final cached = _vectors[text];
    if (cached != null) return cached;
    final vector = await _embeddings?.embed(text);
    if (vector != null) _vectors[text] = vector;
    return vector;
  }

  static double cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return na == 0 || nb == 0 ? 0 : dot / (sqrt(na) * sqrt(nb));
  }

  static Set<String> _terms(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length > 3)
      .toSet();

  /// Share of the query's words that appear in the entry (0–1).
  static double overlap(String query, String entry) {
    final q = _terms(query);
    if (q.isEmpty) return 0;
    final e = _terms(entry);
    return q.where(e.contains).length / q.length;
  }

  /// The [limit] best entries from [candidates] for [query], best first.
  Future<List<LoreHit>> search(
    String query,
    Iterable<StoryLoreEntry> candidates, {
    int limit = 5,
  }) async {
    final entries = candidates.toList();
    if (entries.isEmpty || query.trim().isEmpty) return const [];
    final queryVector = semantic ? await _embed(query) : null;
    final hits = <LoreHit>[];
    for (final entry in entries) {
      final text = _text(entry);
      var score = overlap(query, text);
      if (queryVector != null) {
        final vector = await _embed(text);
        if (vector != null) score = cosine(queryVector, vector);
      }
      hits.add((entry: entry, score: score));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    final floor = queryVector != null ? 0.3 : 0.15;
    return hits.where((h) => h.score >= floor).take(limit).toList();
  }

  /// Cut an uploaded document into lore entries on paragraph boundaries.
  static List<StoryLoreEntry> chunkDocument(String name, String text) {
    final title = name.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '').trim();
    final paragraphs = text
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);
    final chunks = <String>[];
    final current = StringBuffer();
    void flush() {
      if (current.isNotEmpty) chunks.add(current.toString().trim());
      current.clear();
    }

    for (final paragraph in paragraphs) {
      if (current.length + paragraph.length > chunkChars) flush();
      if (paragraph.length > chunkChars) {
        for (var i = 0; i < paragraph.length; i += chunkChars) {
          chunks.add(
            paragraph.substring(i, min(i + chunkChars, paragraph.length)),
          );
        }
        continue;
      }
      current.writeln(paragraph);
      current.writeln();
    }
    flush();
    return [
      for (var i = 0; i < chunks.length; i++)
        StoryLoreEntry(
          topic: chunks.length == 1 ? title : '$title (${i + 1})',
          detail: chunks[i],
          relatedTo: ['file:$name'],
        ),
    ];
  }
}
