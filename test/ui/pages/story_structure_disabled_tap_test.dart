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

// A second press on the greyed-out "Generate act" (the act is already
// generating) used to fall through the disabled button to the act header and
// collapse the act, hiding the scenes as they arrived. The Windows E2E run of
// story_pipeline_test.dart timed out on exactly that.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/pages/story_structure/structure_board.dart';
import 'package:front_porch_ai/ui/pages/story_structure/structure_board_actions.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';

void main() {
  Future<List<String>> pumpAct(WidgetTester tester, {required bool running}) async {
    final calls = <String>[];
    void scene(int a, int s) {}
    final project = StoryProject(title: 'Porch Light')
      ..acts.add(
        StoryAct(number: 1, title: 'The Message', description: 'It begins.'),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: StudioTheme(
          child: Scaffold(
            body: StructureAct(
              project: project,
              act: 0,
              open: true,
              running: running,
              actions: StructureBoardActions(
                onToggleAct: (a, open) => calls.add('toggle'),
                onEditAct: (_) {},
                onGenerateAct: (_) => calls.add('generate'),
                onPlanSequence: (_) {},
                onOpenScene: scene,
                onWriteScene: scene,
                onPlanBeats: scene,
                onEditScene: scene,
                onInsertAfter: scene,
                onRewriteScene: scene,
                onDeleteScene: scene,
              ),
            ),
          ),
        ),
      ),
    );
    return calls;
  }

  testWidgets('a press on the greyed Generate act leaves the act open', (
    tester,
  ) async {
    final calls = await pumpAct(tester, running: true);
    await tester.tap(find.text('Generate act'));
    await tester.pump();
    expect(calls, isEmpty, reason: 'the disabled button must eat the tap');
  });

  testWidgets('an enabled Generate act generates and does not toggle', (
    tester,
  ) async {
    final calls = await pumpAct(tester, running: false);
    await tester.tap(find.text('Generate act'));
    await tester.pump();
    expect(calls, ['generate']);
  });

  testWidgets('the header itself still toggles the act', (tester) async {
    final calls = await pumpAct(tester, running: true);
    await tester.tap(find.text('The Message'));
    await tester.pump();
    expect(calls, ['toggle']);
  });
}
