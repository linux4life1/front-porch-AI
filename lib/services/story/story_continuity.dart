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

import 'package:front_porch_ai/models/models.dart';

/// The continuity ledger and the relationship ledger: what is true, and how
/// people feel about each other, as of a given scene.
///
/// Both are anchored to scene ids, so "true from scene 3.3" keeps meaning the
/// same scene when the Director inserts or removes scenes around it. A fact
/// whose scene no longer exists is treated as always known.
abstract final class StoryContinuity {
  static const categories = [
    'Body',
    'Object',
    'Promise',
    'Place',
    'Opinion',
    'Knowledge',
  ];

  static String _norm(String s) => s.trim().toLowerCase();

  /// Models write categories loosely; fold them onto the fixed set.
  static String category(String raw) {
    final c = _norm(raw);
    if (c.contains('appear') || c.contains('body') || c.contains('injur')) {
      return 'Body';
    }
    if (c.contains('object') || c.contains('item') || c.contains('invent')) {
      return 'Object';
    }
    if (c.contains('promise') ||
        c.contains('agree') ||
        c.contains('deadline')) {
      return 'Promise';
    }
    if (c.contains('place') || c.contains('locat') || c.contains('setting')) {
      return 'Place';
    }
    if (c.contains('opinion') || c.contains('suspic') || c.contains('belief')) {
      return 'Opinion';
    }
    return 'Knowledge';
  }

  /// Add [fact]. An active fact about the same subject is retired as of the
  /// new fact's scene (kept, so the ledger shows what used to be true)
  /// unless it already says the same thing.
  static void record(StoryProject project, ContinuityFact fact) {
    if (fact.key.trim().isEmpty || fact.value.trim().isEmpty) return;
    fact.category = category(fact.category);
    for (final old in project.continuity) {
      if (old.isRetired) continue;
      if (_norm(old.key) != _norm(fact.key)) continue;
      if (_norm(old.entity) != _norm(fact.entity)) continue;
      if (_norm(old.value) == _norm(fact.value)) return;
      if (old.sceneId == fact.sceneId) {
        old.value = fact.value;
        old.category = fact.category;
        return;
      }
      old.retiredSceneId = fact.sceneId;
    }
    project.continuity.add(fact);
  }

  /// Facts a writer may rely on while writing scene ([act], [scene]):
  /// established in an earlier scene (or scene-less) and not yet retired.
  static List<ContinuityFact> knownAt(
    StoryProject project,
    int act,
    int scene,
  ) {
    final order = <String, int>{};
    var n = 0;
    var here = -1;
    for (final ref in project.orderedScenes) {
      order[ref.scene.id] = n;
      if (ref.act == act && ref.index == scene) here = n;
      n++;
    }
    if (here == -1) here = n;
    return project.continuity.where((f) {
      final from = order[f.sceneId];
      if (from != null && from >= here) return false;
      final until = order[f.retiredSceneId];
      if (f.isRetired && (until == null || until < here)) return false;
      return true;
    }).toList();
  }

  /// The ledger as a prompt block. Facts about [cast] (the people in the
  /// scene) come first; the rest follow until [limit].
  static String forPrompt(
    StoryProject project,
    int act,
    int scene, {
    Iterable<String> cast = const [],
    int limit = 40,
  }) {
    final present = cast.map(_norm).toSet();
    final facts = knownAt(project, act, scene);
    if (facts.isEmpty) return 'No hard facts recorded yet.';
    bool about(ContinuityFact f) =>
        present.any((c) => _norm(f.entity).contains(c.split(' ').first));
    final ordered = [
      ...facts.where(about),
      ...facts.where((f) => !about(f)),
    ].take(limit);
    return ordered
        .map((f) {
          final who = f.entity.isEmpty ? '' : ' (${f.entity})';
          return '- [${f.category}] ${f.key}$who: ${f.value}';
        })
        .join('\n');
  }

  /// Forget everything scene [sceneId] established: its facts go, facts it
  /// retired come back, and relationship moves it caused are undone. Called
  /// when a scene is deleted or its prose is thrown away for a rewrite.
  static void forgetScene(StoryProject project, String sceneId) {
    if (sceneId.isEmpty) return;
    project.continuity.removeWhere((f) => f.sceneId == sceneId);
    for (final f in project.continuity) {
      if (f.retiredSceneId == sceneId) f.retiredSceneId = '';
    }
    for (final r in project.relationships) {
      final undone = r.history.where((h) => h.sceneId == sceneId).toList();
      if (undone.isEmpty) continue;
      r.history.removeWhere((h) => h.sceneId == sceneId);
      r.feeling = r.history.isNotEmpty ? r.history.last.to : undone.first.from;
    }
  }

  // ── Relationships ──────────────────────────────────────────────────────

  /// Record that [from] now feels [feeling] about [to]. Creates the row when
  /// it is new; appends a history step when the feeling actually changed.
  static void shift(
    StoryProject project, {
    required String from,
    required String to,
    required String feeling,
    String note = '',
    String subtext = '',
    int? trust,
    String sceneId = '',
    String reason = '',
  }) {
    final a = project.castByName(from)?.name;
    final b = project.castByName(to)?.name;
    if (a == null || b == null || a == b || feeling.trim().isEmpty) return;
    var rel = project.relationship(a, b);
    if (rel == null) {
      rel = StoryRelationship(from: a, to: b);
      project.relationships.add(rel);
    }
    final previous = rel.feeling;
    if (_norm(previous) != _norm(feeling)) {
      rel.history.add(
        RelationshipShift(
          sceneId: sceneId,
          from: previous.isEmpty ? '—' : previous,
          to: feeling.trim(),
          reason: reason.trim(),
        ),
      );
      rel.feeling = feeling.trim();
    }
    if (note.trim().isNotEmpty) rel.note = note.trim();
    if (subtext.trim().isNotEmpty) rel.subtext = subtext.trim();
    if (trust != null) rel.trust = trust.clamp(0, 10);
  }

  /// 'warm' / 'mid' / 'hot' — how the matrix colours a cell.
  static String tone(int trust) =>
      trust >= 7 ? 'warm' : (trust <= 3 ? 'hot' : 'mid');

  /// How the people in [cast] feel about each other, for a prompt.
  static String relationshipsForPrompt(
    StoryProject project,
    Iterable<String> cast,
  ) {
    final present = {
      for (final c in cast)
        if (project.castByName(c) != null) project.castByName(c)!.name,
    };
    if (present.length < 2) {
      return 'One character present; the conflict is internal.';
    }
    final lines = [
      for (final r in project.relationships)
        if (present.contains(r.from) && present.contains(r.to))
          '- ${r.from} → ${r.to}: ${r.feeling}'
              '${r.note.isEmpty ? '' : ' (${r.note})'}, trust ${r.trust}/10'
              '${r.subtext.isEmpty ? '' : '. Unspoken: ${r.subtext}'}',
    ];
    return lines.isEmpty
        ? 'No history between these characters yet.'
        : lines.join('\n');
  }
}
