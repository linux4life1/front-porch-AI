// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/story_project.dart';

void main() {
  group('StoryBeat.fromJson', () {
    test('parses integer fields from int values', () {
      final beat = StoryBeat.fromJson({
        'number': 1,
        'type': 'Action',
        'description': 'A test beat',
        'emotional_shift': 'calm',
        'valence': -2,
        'pacing': 2,
      });
      expect(beat.number, 1);
      expect(beat.valence, -2);
      expect(beat.pacing, 2);
    });

    test('parses integer fields from double values (LLM output)', () {
      final beat = StoryBeat.fromJson({
        'number': 1.0,
        'type': 'Action',
        'description': 'A test beat',
        'emotional_shift': 'calm',
        'valence': -2.0,
        'pacing': 2.0,
      });
      expect(beat.number, 1);
      expect(beat.valence, -2);
      expect(beat.pacing, 2);
    });

    test('applies defaults when fields are missing', () {
      final beat = StoryBeat.fromJson({});
      expect(beat.number, 1);
      expect(beat.valence, 0);
      expect(beat.pacing, 1);
    });
  });

  group('StoryScene.fromJson', () {
    test('parses integer fields from int values', () {
      final scene = StoryScene.fromJson({
        'number': 3,
        'valence': 5,
      });
      expect(scene.number, 3);
      expect(scene.valence, 5);
    });

    test('parses integer fields from double values (LLM output)', () {
      final scene = StoryScene.fromJson({
        'number': 3.0,
        'valence': 5.0,
      });
      expect(scene.number, 3);
      expect(scene.valence, 5);
    });

    test('applies defaults when fields are missing', () {
      final scene = StoryScene.fromJson({});
      expect(scene.number, 1);
      expect(scene.valence, 0);
    });
  });

  group('StoryAct.fromJson', () {
    test('parses number from int value', () {
      final act = StoryAct.fromJson({'number': 2});
      expect(act.number, 2);
    });

    test('parses number from double value (LLM output)', () {
      final act = StoryAct.fromJson({'number': 2.0});
      expect(act.number, 2);
    });

    test('applies default when number is missing', () {
      final act = StoryAct.fromJson({});
      expect(act.number, 1);
    });
  });

  group('StoryLoreEntry.fromJson', () {
    test('parses integer fields from int values', () {
      final entry = StoryLoreEntry.fromJson({
        'topic': 'Magic',
        'detail': 'It exists',
        'valid_from_act': 2,
        'valid_from_scene': 3,
      });
      expect(entry.validFromAct, 2);
      expect(entry.validFromScene, 3);
    });

    test('parses integer fields from double values (LLM output)', () {
      final entry = StoryLoreEntry.fromJson({
        'topic': 'Magic',
        'detail': 'It exists',
        'valid_from_act': 2.0,
        'valid_from_scene': 3.0,
      });
      expect(entry.validFromAct, 2);
      expect(entry.validFromScene, 3);
    });

    test('applies defaults when fields are missing', () {
      final entry = StoryLoreEntry.fromJson({'topic': '', 'detail': ''});
      expect(entry.validFromAct, 1);
      expect(entry.validFromScene, 1);
    });
  });

  group('StoryProject.fromJson', () {
    test('parses actCount from int value', () {
      final project = StoryProject.fromJson({'act_count': 5});
      expect(project.actCount, 5);
    });

    test('parses actCount from double value (LLM output)', () {
      final project = StoryProject.fromJson({'act_count': 5.0});
      expect(project.actCount, 5);
    });

    test('parses lastReadPageIndex from double value (LLM output)', () {
      final project = StoryProject.fromJson({'last_read_page_index': 4.0});
      expect(project.lastReadPageIndex, 4);
    });

    test('applies defaults when integer fields are missing', () {
      final project = StoryProject.fromJson({});
      expect(project.actCount, 3);
      expect(project.lastReadPageIndex, 0);
    });
  });
}
