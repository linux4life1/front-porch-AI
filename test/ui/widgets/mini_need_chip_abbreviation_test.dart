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

// MiniNeedChip used to abbreviate a need to its first letter, so hunger and
// hygiene both rendered "H##" — a pre-existing collision found while adding
// the "bowels" need, which would have collided with "bladder" the same way
// ("B##" for both). The fix takes the first TWO letters instead, which
// disambiguates the whole 8-need set with no hand-maintained exception map.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/widgets/group_member_chips.dart';

void main() {
  testWidgets('hunger and hygiene no longer collide on "H##"', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MiniNeedChip(name: 'hunger', value: 40),
              MiniNeedChip(name: 'hygiene', value: 40),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Hu40'), findsOneWidget);
    expect(find.text('Hy40'), findsOneWidget);
    expect(find.text('H40'), findsNothing);
  });

  testWidgets('bladder and bowels no longer collide on "B##"', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MiniNeedChip(name: 'bladder', value: 15),
              MiniNeedChip(name: 'bowels', value: 15),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Bl15'), findsOneWidget);
    expect(find.text('Bo15'), findsOneWidget);
    expect(find.text('B15'), findsNothing);
  });

  testWidgets('every canonical need key gets a distinct two-letter prefix', (
    tester,
  ) async {
    const needs = [
      'hunger',
      'bladder',
      'bowels',
      'energy',
      'social',
      'fun',
      'hygiene',
      'comfort',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [for (final n in needs) MiniNeedChip(name: n, value: 50)],
          ),
        ),
      ),
    );
    final rendered = needs.map((n) => '${n[0].toUpperCase()}${n[1]}50').toSet();
    expect(
      rendered.length,
      needs.length,
      reason:
          'the two-letter prefixes themselves must be unique, or the '
          'widget-level fix would still collide',
    );
    for (final label in rendered) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
