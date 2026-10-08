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
import 'package:front_porch_ai/services/story/story_continuity.dart';

/// Structural edits that keep the index-keyed maps honest.
///
/// `beats` is keyed "act-scene" and `prose` "act-scene-beat", so inserting,
/// removing or moving a scene or beat has to re-key everything after it.
/// Every edit here does that in one place; nothing else should splice
/// `project.scenes[...]` or `project.beats[...]` directly.
abstract final class StoryStructure {
  static String _sKey(int act, int scene) => '$act-$scene';

  /// A scene's beats and prose lifted out of the maps, so it can be put back
  /// under a different index.
  static ({List<StoryBeat>? beats, Map<int, BeatProse> prose}) _lift(
    StoryProject p,
    int act,
    int scene,
  ) {
    final key = _sKey(act, scene);
    final beats = p.beats.remove(key);
    final prose = <int, BeatProse>{};
    final prefix = '$key-';
    for (final k in p.prose.keys.where((k) => k.startsWith(prefix)).toList()) {
      final beat = int.tryParse(k.substring(prefix.length));
      final value = p.prose.remove(k);
      if (beat != null && value != null) prose[beat] = value;
    }
    return (beats: beats, prose: prose);
  }

  static void _drop(
    StoryProject p,
    int act,
    int scene,
    ({List<StoryBeat>? beats, Map<int, BeatProse> prose}) lifted,
  ) {
    final key = _sKey(act, scene);
    if (lifted.beats != null) p.beats[key] = lifted.beats!;
    lifted.prose.forEach((beat, value) => p.prose['$key-$beat'] = value);
  }

  /// Re-key every scene of [act] so the maps follow [order], where
  /// `order[newIndex] = oldIndex` (or -1 for a brand-new, empty scene).
  static void _rekeyAct(StoryProject p, int act, List<int> order, int oldLen) {
    final lifted = [for (var i = 0; i < oldLen; i++) _lift(p, act, i)];
    for (var i = 0; i < order.length; i++) {
      if (order[i] >= 0) _drop(p, act, i, lifted[order[i]]);
    }
  }

  static void _renumberScenes(StoryProject p, int act) {
    final list = p.scenes[act] ?? const <StoryScene>[];
    for (var i = 0; i < list.length; i++) {
      list[i].number = i + 1;
    }
  }

  static void _renumberBeats(StoryProject p, int act, int scene) {
    final list = p.beats[_sKey(act, scene)] ?? const <StoryBeat>[];
    for (var i = 0; i < list.length; i++) {
      list[i].number = i + 1;
    }
  }

  /// Insert [scene] at [index] of [act] (clamped), shifting later scenes.
  static void insertScene(
    StoryProject p,
    int act,
    int index,
    StoryScene scene,
  ) {
    final list = p.scenes.putIfAbsent(act, () => []);
    final at = index.clamp(0, list.length);
    final oldLen = list.length;
    if (scene.id.isEmpty) scene.id = newStoryId();
    list.insert(at, scene);
    _rekeyAct(p, act, [
      for (var i = 0; i < list.length; i++) i < at ? i : (i == at ? -1 : i - 1),
    ], oldLen);
    _renumberScenes(p, act);
  }

  /// Remove the scene with its beats, prose, facts and relationship moves.
  static void removeScene(StoryProject p, int act, int index) {
    final list = p.scenes[act];
    if (list == null || index < 0 || index >= list.length) return;
    final oldLen = list.length;
    final removed = list.removeAt(index);
    _rekeyAct(p, act, [
      for (var i = 0; i < list.length; i++) i < index ? i : i + 1,
    ], oldLen);
    StoryContinuity.forgetScene(p, removed.id);
    _renumberScenes(p, act);
  }

  /// Move a scene inside its act, carrying beats and prose with it. The
  /// scene keeps its sequence; a caller moving it across sequences sets it.
  static void moveScene(StoryProject p, int act, int from, int to) {
    final list = p.scenes[act];
    if (list == null || from < 0 || from >= list.length) return;
    final target = to.clamp(0, list.length - 1);
    if (target == from) return;
    final order = [for (var i = 0; i < list.length; i++) i];
    order.insert(target, order.removeAt(from));
    final scene = list.removeAt(from);
    list.insert(target, scene);
    _rekeyAct(p, act, order, list.length);
    _renumberScenes(p, act);
  }

  /// Insert a beat (no prose yet) at [index], shifting later beats' prose.
  static void insertBeat(
    StoryProject p,
    int act,
    int scene,
    int index,
    StoryBeat beat,
  ) {
    final key = _sKey(act, scene);
    final list = p.beats.putIfAbsent(key, () => []);
    final at = index.clamp(0, list.length);
    for (var b = list.length - 1; b >= at; b--) {
      final moved = p.prose.remove('$key-$b');
      if (moved != null) p.prose['$key-${b + 1}'] = moved;
    }
    list.insert(at, beat);
    _renumberBeats(p, act, scene);
  }

  static void removeBeat(StoryProject p, int act, int scene, int index) {
    final key = _sKey(act, scene);
    final list = p.beats[key];
    if (list == null || index < 0 || index >= list.length) return;
    list.removeAt(index);
    p.prose.remove('$key-$index');
    for (var b = index; b < list.length; b++) {
      final moved = p.prose.remove('$key-${b + 1}');
      if (moved != null) p.prose['$key-$b'] = moved;
    }
    _renumberBeats(p, act, scene);
  }

  /// Throw away a scene's prose (for a rewrite) along with everything the
  /// archivist learned from it.
  static void clearSceneProse(StoryProject p, int act, int scene) {
    final key = _sKey(act, scene);
    p.prose.removeWhere((k, _) => k.startsWith('$key-'));
    final list = p.scenes[act];
    if (list == null || scene < 0 || scene >= list.length) return;
    list[scene].summary = '';
    StoryContinuity.forgetScene(p, list[scene].id);
  }

  /// Replace the scenes of sequence [number] with [fresh], dropping the old
  /// ones (and everything hanging off them) first.
  static void replaceSequenceScenes(
    StoryProject p,
    int number,
    List<StoryScene> fresh,
  ) {
    final act = p.actIndexForSequence(number);
    if (act < 0) return;
    final old = p.sceneIndexesInSequence(number);
    for (final i in old.reversed) {
      removeScene(p, act, i);
    }
    final list = p.scenes.putIfAbsent(act, () => []);
    var at = list.indexWhere((s) => s.sequence > number);
    if (at == -1) at = list.length;
    for (final scene in fresh) {
      scene.sequence = number;
      insertScene(p, act, at++, scene);
    }
  }
}
