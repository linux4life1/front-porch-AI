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

// The shelf's one status line, shared by the desktop shelf and the relay's
// story list. The wizard's step (null once finished) is what says a story is
// still a draft — the browser journey caught a draft with its idea filled in
// reading "Bible ready".

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story.dart';

void main() {
  test('a draft left on a later step says so, even with the idea written', () {
    final p = StoryProject(title: 'Draft')
      ..concept = 'A courier on a drowned coast.'
      ..setupStep = 3;
    final s = storyShelfStatus(p);
    expect(s.setup, isTrue);
    expect(s.status, 'Stopped at step 4 · Engine');
  });

  test('a finished setup with no bible yet is not a draft', () {
    final p = StoryProject(title: 'Set')..concept = 'A courier.';
    final s = storyShelfStatus(p);
    expect(s.setup, isFalse);
    expect(s.status, 'Bible ready · nothing written');
  });

  test('a story from before the wizard kept a step, with nothing in it, '
      'asks to finish setup', () {
    final s = storyShelfStatus(StoryProject(title: 'Old'));
    expect(s.setup, isTrue);
    expect(s.status, 'Finish setup');
  });

  test('acts with a sequence still to outline are not "written"', () {
    final p = StoryProject(title: 'T')
      ..engineMode = StoryEngineMode.studio
      ..acts = [StoryAct(number: 1, title: 'One', description: '')]
      ..sequences = [
        StorySequence(number: 1, act: 1, title: 'A'),
        StorySequence(number: 2, act: 1, title: 'B'),
      ];
    expect(p.hasUnoutlined, isTrue);
    p.scenes = {
      0: [StoryScene(number: 1, title: 'Porch', id: 's1', sequence: 1)],
    };
    expect(p.hasUnoutlined, isTrue, reason: 'sequence 2 has no scenes');
    p.scenes[0]!.add(
      StoryScene(number: 2, title: 'Road', id: 's2', sequence: 2),
    );
    expect(p.hasUnoutlined, isFalse);
    // Quick: an act with no scenes.
    final q = StoryProject(title: 'Q')
      ..engineMode = StoryEngineMode.quick
      ..acts = [StoryAct(number: 1, title: 'One', description: '')];
    expect(q.hasUnoutlined, isTrue);
    q.scenes = {
      0: [StoryScene(number: 1, title: 'Porch', id: 'q1')],
    };
    expect(q.hasUnoutlined, isFalse);
  });

  test('the rewrite confirm counts the facts a scene recorded', () {
    final p = StoryProject(title: 'T')
      ..acts = [StoryAct(number: 1, title: 'One', description: '')]
      ..scenes = {
        0: [StoryScene(number: 1, title: 'Porch', id: 's1', sequence: 1)],
      };
    expect(
      storyRewriteSceneBody(p, 0, 0),
      'Its 0 words will be replaced. The beats stay.',
    );
    p.continuity.add(
      ContinuityFact(
        category: 'Object',
        key: 'The letters',
        value: 'In his coat.',
        sceneId: 's1',
      ),
    );
    expect(
      storyRewriteSceneBody(p, 0, 0),
      'Its 0 words will be replaced. The beats stay. 1 continuity fact '
      'recorded from this scene is retired first.',
    );
  });
}
