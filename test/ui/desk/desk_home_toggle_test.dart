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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_mode_toggle.dart';

void main() {
  testWidgets('Desk is a sibling of Chats and Porch Stories', (tester) async {
    var deskTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HomeModeToggle(
              showStories: false,
              onShowChats: () {},
              onShowStories: () {},
              showDesk: true,
              onShowDesk: () => deskTapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Porch Stories'), findsOneWidget);
    expect(find.text('Desk'), findsOneWidget);

    await tester.tap(find.text('Desk'));
    await tester.pump();
    expect(deskTapped, isTrue);
  });

  testWidgets(
    'legacy two-callback constructor still builds with a Desk button',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: HomeModeToggle(
                showStories: false,
                onShowChats: _noop,
                onShowStories: _noop,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Desk'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

void _noop() {}
