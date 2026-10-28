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

// Stories set in Worlds, slice 5 (docs/design/stories-in-worlds.md §3.4):
// "Write a story here" is a menu item on the world card and the place row
// only when the page wires it, and it fires that callback alone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/pages/worlds/worlds.dart';

World place(String name, {String? parent}) => World(
  id: name,
  name: name,
  description: '$name prose.',
  lorebook: Lorebook(entries: []),
  parentWorldId: parent,
);

Widget framed(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, height: 300, child: child)),
  ),
);

void main() {
  testWidgets('the world card\'s menu offers Write a story here when wired', (
    tester,
  ) async {
    var stories = 0;
    var edits = 0;
    await tester.pumpWidget(
      framed(
        WorldPlaceCard(
          world: place('Bletchfield'),
          onEdit: () => edits++,
          onExport: () {},
          onDelete: () {},
          onWriteStory: () => stories++,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('world-write-story-Bletchfield')));
    await tester.pumpAndSettle();
    expect(stories, 1);
    expect(edits, 0);
  });

  testWidgets('without the callback the card\'s menu has no story item', (
    tester,
  ) async {
    await tester.pumpWidget(
      framed(
        WorldPlaceCard(
          world: place('Bletchfield'),
          onEdit: () {},
          onExport: () {},
          onDelete: () {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Write a story here'), findsNothing);
    expect(find.text('Export .fpworld'), findsOneWidget);
  });

  testWidgets('the place row\'s menu offers Write a story here when wired', (
    tester,
  ) async {
    var stories = 0;
    var moves = 0;
    await tester.pumpWidget(
      framed(
        WorldPlaceRow(
          place: place('Tea Rooms', parent: 'Bletchfield'),
          depth: 1,
          hasWeatherToInherit: true,
          onEdit: () {},
          onMove: () => moves++,
          onDelete: () {},
          onWriteStory: () => stories++,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Place actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('place-write-story-Tea Rooms')));
    await tester.pumpAndSettle();
    expect(stories, 1);
    expect(moves, 0);
  });
}
