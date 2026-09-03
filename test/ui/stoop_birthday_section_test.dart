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

// The Stoop card panel's Birthday section — same contract as
// hub.frontporchai.app views-browse.js identitySections: a calendar
// YYYY-MM-DD on the realism block, age against UTC today (the hub has no
// story clock), omitted when absent/invalid. Current Stoop cards have no
// field, so the section must cost nothing on those.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/repository/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  // Fixed "today" so age is not a moving target across midnight UTC.
  final asOf = DateTime.utc(2026, 8, 31);

  group('stoopBirthdayText', () {
    test('formats month day, year — age against the given day', () {
      expect(
        stoopBirthdayText('1998-03-15', asOf: asOf),
        'March 15, 1998 — age 28',
      );
    });

    test('age has not ticked yet if the date is still ahead this year', () {
      expect(
        stoopBirthdayText('1998-12-01', asOf: asOf),
        'December 1, 1998 — age 27',
      );
    });

    test('today is already that age', () {
      expect(
        stoopBirthdayText('2000-08-31', asOf: asOf),
        'August 31, 2000 — age 26',
      );
    });

    test('Feb 29 is never a birthday', () {
      expect(stoopBirthdayText('2000-02-29', asOf: asOf), isNull);
    });

    test('junk, blank, and a date after today are omitted', () {
      expect(stoopBirthdayText(null, asOf: asOf), isNull);
      expect(stoopBirthdayText('', asOf: asOf), isNull);
      expect(stoopBirthdayText('march 15', asOf: asOf), isNull);
      expect(stoopBirthdayText('1998-13-01', asOf: asOf), isNull);
      expect(stoopBirthdayText('2099-01-01', asOf: asOf), isNull);
    });

    test('a wrong-typed field is omitted, never throws', () {
      expect(stoopBirthdayText(42, asOf: asOf), isNull);
      expect(stoopBirthdayText(['1998-03-15'], asOf: asOf), isNull);
      expect(stoopBirthdayText({'iso': '1998-03-15'}, asOf: asOf), isNull);
    });
  });

  group('stoopBirthdaySection', () {
    testWidgets('opens on a valid birthday so the date is visible', (t) async {
      await t.pumpWidget(
        host(
          Builder(
            builder: (c) => stoopBirthdaySection(c, const {
              'birthday': '1998-03-15',
            }, asOf: asOf),
          ),
        ),
      );
      expect(find.text('Birthday'), findsOneWidget);
      expect(find.text('March 15, 1998 — age 28'), findsOneWidget);
    });

    testWidgets('shown even when the realism engine is off', (t) async {
      await t.pumpWidget(
        host(
          Builder(
            builder: (c) => stoopBirthdaySection(c, const {
              'enabled': false,
              'birthday': '1998-03-15',
            }, asOf: asOf),
          ),
        ),
      );
      expect(find.text('Birthday'), findsOneWidget);
      expect(find.text('March 15, 1998 — age 28'), findsOneWidget);
    });

    testWidgets('absent or invalid renders nothing, never throws', (t) async {
      for (final re in <Map<String, dynamic>>[
        const {},
        const {'birthday': ''},
        const {'birthday': '2000-02-29'},
        {'birthday': 42},
        {
          'birthday': ['1998-03-15'],
        },
      ]) {
        await t.pumpWidget(
          host(
            Builder(builder: (c) => stoopBirthdaySection(c, re, asOf: asOf)),
          ),
        );
        expect(t.takeException(), isNull);
        expect(find.text('Birthday'), findsNothing);
      }
    });
  });

  group('stoopStandardSections wires birthday first', () {
    Map<String, dynamic> card({String? birthday, List<String>? ambitions}) => {
      'name': 'Misty',
      'description': 'A baker.',
      'extensions': {
        'front_porch': {
          'realism_engine': {'birthday': ?birthday, 'ambitions': ?ambitions},
        },
      },
    };

    testWidgets('a dated card shows Birthday above Ambitions', (t) async {
      await t.pumpWidget(
        host(
          Builder(
            builder: (c) => Column(
              children: stoopStandardSections(
                c,
                card(birthday: '1998-03-15', ambitions: ['open a bakery']),
                'Misty',
                asOf: asOf,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Birthday'), findsOneWidget);
      expect(find.text('March 15, 1998 — age 28'), findsOneWidget);
      expect(find.textContaining('Ambitions (1)'), findsOneWidget);

      final bday = t.getTopLeft(find.text('Birthday')).dy;
      final ambitions = t.getTopLeft(find.textContaining('Ambitions (1)')).dy;
      expect(bday, lessThan(ambitions));
    });

    testWidgets('today\'s Stoop cards — no birthday field — look unchanged', (
      t,
    ) async {
      await t.pumpWidget(
        host(
          Builder(
            builder: (c) => Column(
              children: stoopStandardSections(
                c,
                card(ambitions: ['open a bakery']),
                'Misty',
                asOf: asOf,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Birthday'), findsNothing);
      expect(find.textContaining('Ambitions (1)'), findsOneWidget);
    });
  });
}
