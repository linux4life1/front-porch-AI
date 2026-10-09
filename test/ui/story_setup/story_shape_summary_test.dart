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

// New story → "Your story so far" Shape line. The length label already names
// the form ("Novel · 80k"), so the line must not say "novel" a second time.
// Web twin: web_ui/src/pages/story/setup/SetupRail.test.ts.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/story_setup/setup_rail.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';

void main() {
  late StorySetupDraft draft;
  setUp(() => draft = StorySetupDraft());
  tearDown(() => draft.dispose());

  test('a novel is named once, by its length', () {
    expect(storyShapeSummary(draft), 'Novel · 80k · third person, close');
  });

  test('an audio drama still says so', () {
    draft
      ..proseLength = 'Short'
      ..storyFormat = StoryFormat.audioDrama
      ..pov = 'First Person'
      ..selectedGenres.add('Fantasy')
      ..selectedMoods.add('Dark')
      ..writingStyle = 'Gothic';
    expect(
      storyShapeSummary(draft),
      'Novella · 30k · audio drama · first person · fantasy · dark · gothic',
    );
  });
}
