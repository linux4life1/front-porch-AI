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

part of 'story_project.dart';

/// Word target behind each "Target length" choice. The legacy `prose_length`
/// names stay as the stored key so Quick prompts read the same as before.
const Map<String, int> kStoryTargetWords = {
  'Short': 30000,
  'Standard': 80000,
  'Epic': 120000,
};

int targetWordsForLength(String? proseLength) =>
    kStoryTargetWords[proseLength] ?? 80000;

/// Where a scene sits: act index, index inside that act, and the scene.
typedef SceneRef = ({int act, int index, StoryScene scene});

int countWords(String? text) {
  final t = text?.trim() ?? '';
  return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
}

/// Structure invariants and lookups. Scenes live in `scenes[actIdx]` in story
/// order; a sequence is a contiguous run of them inside one act, so adding the
/// sequence layer never re-keys `beats` / `prose`.
extension StoryProjectShape on StoryProject {
  /// Idempotent repair run on every load and save: every scene has an id and
  /// belongs to a sequence that exists in its own act. Quick stories carry
  /// exactly one sequence per act (that is also how a pre-sequence story is
  /// upgraded the first time it opens).
  void normalize() {
    final taken = <String>{
      for (final list in scenes.values)
        for (final s in list)
          if (s.id.isNotEmpty) s.id,
    };
    scenes.forEach((act, list) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id.isNotEmpty) continue;
        final legacy = 'L$act-$i';
        list[i].id = taken.contains(legacy) ? newStoryId() : legacy;
        taken.add(list[i].id);
      }
    });

    if (engineMode == StoryEngineMode.quick || sequences.isEmpty) {
      final previous = {for (final s in sequences) s.number: s};
      sequences = [
        for (var i = 0; i < acts.length; i++)
          StorySequence(
            number: i + 1,
            act: acts[i].number,
            title: acts[i].title,
            summary: previous[i + 1]?.summary ?? '',
          ),
      ];
      scenes.forEach((act, list) {
        for (final s in list) {
          s.sequence = act + 1;
        }
      });
      return;
    }

    scenes.forEach((act, list) {
      final inAct = sequencesInAct(act);
      if (inAct.isEmpty) return;
      final valid = {for (final s in inAct) s.number};
      var last = inAct.first.number;
      for (final s in list) {
        if (!valid.contains(s.sequence)) s.sequence = last;
        last = s.sequence;
      }
    });
  }

  /// Sequences belonging to the act at [actIndex], in order.
  List<StorySequence> sequencesInAct(int actIndex) {
    if (actIndex < 0 || actIndex >= acts.length) return const [];
    final actNumber = acts[actIndex].number;
    return sequences.where((s) => s.act == actNumber).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
  }

  StorySequence? sequenceByNumber(int number) {
    for (final s in sequences) {
      if (s.number == number) return s;
    }
    return null;
  }

  /// Act index that holds sequence [number], or -1.
  int actIndexForSequence(int number) {
    final seq = sequenceByNumber(number);
    if (seq == null) return -1;
    return acts.indexWhere((a) => a.number == seq.act);
  }

  /// Indexes (inside the act's scene list) of the scenes in sequence [number].
  List<int> sceneIndexesInSequence(int number) {
    final act = actIndexForSequence(number);
    final list = scenes[act] ?? const <StoryScene>[];
    return [
      for (var i = 0; i < list.length; i++)
        if (list[i].sequence == number) i,
    ];
  }

  /// Whether Continue writing still has something to outline before it can
  /// write: a Studio sequence with no scenes, or a Quick act with none. The
  /// engine's `writeNextScene` outlines that first; the UIs say "written"
  /// only when this is false too. Mirrored by `hasUnoutlined` in
  /// storyShape.ts.
  bool get hasUnoutlined => engineMode == StoryEngineMode.studio
      ? sequences.any((s) => sceneIndexesInSequence(s.number).isEmpty)
      : [
          for (var act = 0; act < acts.length; act++) act,
        ].any((act) => scenes[act]?.isEmpty ?? true);

  /// Every scene in story order.
  Iterable<SceneRef> get orderedScenes sync* {
    for (var act = 0; act < acts.length; act++) {
      final list = scenes[act] ?? const <StoryScene>[];
      for (var i = 0; i < list.length; i++) {
        yield (act: act, index: i, scene: list[i]);
      }
    }
  }

  SceneRef? findScene(String id) {
    if (id.isEmpty) return null;
    for (final ref in orderedScenes) {
      if (ref.scene.id == id) return ref;
    }
    return null;
  }

  /// "3.2" — sequence number, then the scene's place inside that sequence.
  String sceneLabel(int act, int index) {
    final list = scenes[act] ?? const <StoryScene>[];
    if (index < 0 || index >= list.length) return '';
    final seq = list[index].sequence;
    var n = 0;
    for (var i = 0; i <= index; i++) {
      if (list[i].sequence == seq) n++;
    }
    return '$seq.$n';
  }

  String sceneLabelById(String id) {
    final ref = findScene(id);
    return ref == null ? '' : sceneLabel(ref.act, ref.index);
  }

  /// Resolve a "3.2" label (what models and users write) back to a scene.
  SceneRef? sceneByLabel(String label) {
    final wanted = label.trim().replaceFirst(RegExp(r'^[Ss]cene\s+'), '');
    for (final ref in orderedScenes) {
      if (sceneLabel(ref.act, ref.index) == wanted) return ref;
    }
    return null;
  }

  static String sceneKey(int act, int scene) => '$act-$scene';

  static String beatKey(int act, int scene, int beat) => '$act-$scene-$beat';

  String? beatText(int act, int scene, int beat) =>
      prose[beatKey(act, scene, beat)]?.final_;

  /// The scene's finished prose, beats joined in order.
  String sceneText(int act, int scene) {
    final count = beats[sceneKey(act, scene)]?.length ?? 0;
    return [
      for (var b = 0; b < count; b++)
        if ((beatText(act, scene, b) ?? '').isNotEmpty) beatText(act, scene, b),
    ].join('\n\n');
  }

  /// How many of the scene's beats have finished prose.
  int beatsWritten(int act, int scene) {
    final count = beats[sceneKey(act, scene)]?.length ?? 0;
    var n = 0;
    for (var b = 0; b < count; b++) {
      if (beatText(act, scene, b) != null) n++;
    }
    return n;
  }

  bool sceneHasProse(int act, int scene) => beatsWritten(act, scene) > 0;

  int get wordCount {
    var n = 0;
    for (final p in prose.values) {
      n += countWords(p.final_);
    }
    return n;
  }

  /// Case-insensitive cast lookup; a bare first name matches too, because
  /// that is how models usually refer to people.
  StoryCastMember? castByName(String name) {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final c in cast) {
      if (c.name.toLowerCase() == wanted) return c;
    }
    for (final c in cast) {
      final full = c.name.toLowerCase();
      if (full.split(' ').first == wanted || wanted.split(' ').first == full) {
        return c;
      }
    }
    return null;
  }

  StoryRelationship? relationship(String from, String to) {
    final a = castByName(from)?.name ?? from;
    final b = castByName(to)?.name ?? to;
    for (final r in relationships) {
      if (r.from == a && r.to == b) return r;
    }
    return null;
  }
}
