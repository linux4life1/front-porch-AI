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

/// Where a story stands, in the shelf's words. One source for the desktop
/// shelf and the relay's story list, so the web shelf says the same thing.
/// Fields: status line, progress fraction, finished, still in setup.
({String status, double fraction, bool done, bool setup}) storyShelfStatus(
  StoryProject p,
) {
  // A draft keeps its step until the wizard finishes (null); a story from
  // before the wizard kept a step is in setup only when it has nothing yet.
  final setup =
      p.setupStep != null || (p.concept.trim().isEmpty && p.acts.isEmpty);
  if (setup) {
    final step = p.setupStep;
    const names = ['Idea', 'Cast', 'Shape', 'Engine'];
    final at = step == null || step >= names.length ? null : names[step];
    return (
      status: at == null
          ? 'Finish setup'
          : 'Stopped at step ${step! + 1} · $at',
      fraction: 0,
      done: false,
      setup: true,
    );
  }
  final words = p.wordCount;
  final target = p.targetWords;
  final fraction = target == 0 ? 0.0 : (words / target).clamp(0.0, 1.0);
  if (p.acts.isEmpty) {
    return (
      status: 'Bible ready · nothing written',
      fraction: 0,
      done: false,
      setup: false,
    );
  }
  final allWritten =
      p.orderedScenes.isNotEmpty &&
      p.orderedScenes.every(
        (s) =>
            (p.beats[StoryProjectShape.sceneKey(s.act, s.index)]?.isNotEmpty ??
                false) &&
            p.beatsWritten(s.act, s.index) ==
                p.beats[StoryProjectShape.sceneKey(s.act, s.index)]!.length,
      );
  if (allWritten) {
    return (
      status: 'Finished · ${thousands(words)} words',
      fraction: 1,
      done: true,
      setup: false,
    );
  }
  if (words == 0) {
    return (
      status: 'Structure ready · nothing written',
      fraction: 0,
      done: false,
      setup: false,
    );
  }
  var act = 0;
  for (final s in p.orderedScenes) {
    if (p.beatsWritten(s.act, s.index) > 0) act = s.act;
  }
  return (
    status:
        'Act ${romanAct(act + 1)} · ${thousands(words)} / ${thousands(target)}',
    fraction: fraction,
    done: false,
    setup: false,
  );
}

String thousands(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String romanAct(int n) =>
    const ['I', 'II', 'III', 'IV', 'V'][(n - 1).clamp(0, 4)];

String storyGenreLine(StoryProject p) {
  final picked = [...p.selectedGenres, ...p.selectedMoods];
  if (p.style.genre.isNotEmpty || p.style.mood.isNotEmpty) {
    return [p.style.genre, p.style.mood].where((s) => s.isNotEmpty).join(' · ');
  }
  if (picked.isNotEmpty) return picked.take(3).join(' · ');
  return p.chatHistorySessionIds.isNotEmpty ? 'From a chat' : 'No genre yet';
}

/// The body of the "Rewrite scene" confirm. Write and Structure both offer
/// it, and the web mirrors this in `confirmCopy.ts`, so the words live once.
/// Clearing a scene's prose also retires the continuity facts it recorded;
/// the sentence says so when there are any.
String storyRewriteSceneBody(StoryProject p, int act, int scene) {
  final sc = p.scenes[act]?[scene];
  final words = countWords(p.sceneText(act, scene));
  final facts = sc == null
      ? 0
      : p.continuity.where((f) => f.sceneId == sc.id).length;
  final retired = facts == 0
      ? ''
      : ' $facts continuity fact${facts == 1 ? '' : 's'} recorded from this '
            'scene ${facts == 1 ? 'is' : 'are'} retired first.';
  return 'Its ${thousands(words)} words will be replaced. The beats stay.'
      '$retired';
}
