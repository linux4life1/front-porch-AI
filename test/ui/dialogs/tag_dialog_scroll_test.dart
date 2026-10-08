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

// A card imported with dozens of tags used to push the tag dialog's input
// and buttons off the bottom of the screen. The chips now scroll inside a
// dialog capped at most of the screen, so Save stays reachable.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/ui/dialogs/tag_dialog.dart';

void main() {
  testWidgets('eighty tags: Save stays on screen and nothing overflows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final character = CharacterCard(
      name: 'Finna',
      description: 'A goblin with far too many tags.',
      tags: List.generate(80, (i) => 'tag number $i'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TagDialog(character: character)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Save Tags').hitTestable(), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsOneWidget);

    // The first chip is on screen, the last one is reachable by scrolling.
    expect(find.text('tag number 0').hitTestable(), findsOneWidget);
    expect(find.text('tag number 79').hitTestable(), findsNothing);
    await tester.scrollUntilVisible(
      find.text('tag number 79'),
      200,
      scrollable: find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('tag number 79').hitTestable(), findsOneWidget);
    expect(find.text('Save Tags').hitTestable(), findsOneWidget);
  });

  testWidgets('a 420 px tall window still shows the input and Save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final character = CharacterCard(
      name: 'Finna',
      description: 'A goblin with far too many tags.',
      tags: List.generate(80, (i) => 'tag number $i'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TagDialog(character: character)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    expect(find.text('Save Tags').hitTestable(), findsOneWidget);
  });
}
