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

// Per-character Pockets enable lives on the Wearing / Carrying panel —
// not as an orphan under Edit Character → Details / Optional Features.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/widgets/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpLists(
    WidgetTester tester, {
    bool? pocketsEnabled,
    ValueChanged<bool>? onPocketsEnabledChanged,
    List<String> worn = const [],
    List<String> carrying = const [],
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: IdentityChipLists(
            worn: worn,
            carrying: carrying,
            onWornChanged: (_) {},
            onCarryingChanged: (_) {},
            pocketsEnabled: pocketsEnabled,
            onPocketsEnabledChanged: onPocketsEnabledChanged,
          ),
        ),
      ),
    ),
  );

  Widget form({required bool? pocketsEnabled, List<String>? worn}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RealismFormSection(
            enabled: false,
            onEnabledChanged: (_) {},
            timeOfDay: 'morning',
            onTimeOfDayChanged: (_) {},
            dayCount: 1,
            onDayCountChanged: (_) {},
            shortTermBond: 0,
            onShortTermBondChanged: (_) {},
            longTermBond: 0,
            onLongTermBondChanged: (_) {},
            trustLevel: 0,
            onTrustLevelChanged: (_) {},
            emotion: '',
            onEmotionChanged: (_) {},
            emotionIntensity: 'mild',
            onEmotionIntensityChanged: (_) {},
            nsfwCooldownEnabled: false,
            onNsfwCooldownChanged: (_) {},
            chaosModeEnabled: false,
            onChaosModeChanged: (_) {},
            worn: worn,
            onWornChanged: worn == null ? null : (_) {},
            carrying: worn == null ? null : const [],
            onCarryingChanged: worn == null ? null : (_) {},
            pocketsEnabled: pocketsEnabled,
            onPocketsEnabledChanged: pocketsEnabled == null ? null : (_) {},
            realismVerificationEnabled: false,
            onRealismVerificationChanged: (_) {},
          ),
        ),
      ),
    );
  }

  group('toggle sits on the Wearing / Carrying panel', () {
    testWidgets('enable switch is inside the wardrobe card', (t) async {
      await pumpLists(t, pocketsEnabled: true, onPocketsEnabledChanged: (_) {});

      final panel = find.byKey(WardrobeChipSection.panelKey);
      expect(panel, findsOneWidget);
      expect(
        find.descendant(
          of: panel,
          matching: find.byKey(WardrobeChipSection.enableKey),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('WEARING')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('CARRYING')),
        findsOneWidget,
      );
    });

    testWidgets('flipping the switch reports to the caller', (t) async {
      bool? reported;
      await pumpLists(
        t,
        pocketsEnabled: true,
        onPocketsEnabledChanged: (v) => reported = v,
      );

      await t.tap(find.byKey(WardrobeChipSection.enableKey));
      await t.pump();
      expect(reported, isFalse);
    });

    testWidgets('per-character off hides Wearing and Carrying editors', (
      t,
    ) async {
      await pumpLists(
        t,
        pocketsEnabled: false,
        onPocketsEnabledChanged: (_) {},
        worn: const ['white peaked cap'],
        carrying: const ['car keys'],
      );

      expect(find.byKey(WardrobeChipSection.enableKey), findsOneWidget);
      expect(find.text('WEARING'), findsNothing);
      expect(find.text('CARRYING'), findsNothing);
      expect(find.text('+ add'), findsNothing);
      expect(
        find.textContaining('Turn this on to edit the starting kit'),
        findsOneWidget,
      );
    });
  });

  group('Details cannot grow an orphan toggle', () {
    testWidgets(
      'RealismFormSection with only the enable pair shows no Pockets switch',
      (t) async {
        // The old Edit Character → Details wiring: enable pair, no kit.
        await t.pumpWidget(form(pocketsEnabled: true, worn: null));
        await t.pumpAndSettle();

        expect(find.byKey(WardrobeChipSection.enableKey), findsNothing);
        expect(find.byKey(WardrobeChipSection.panelKey), findsNothing);
        expect(find.textContaining('skips inventory tracking'), findsNothing);
        expect(find.text('Pockets & Wardrobe'), findsNothing);
      },
    );

    testWidgets('enable pair plus kit puts the switch on the wardrobe panel', (
      t,
    ) async {
      await t.pumpWidget(form(pocketsEnabled: true, worn: const []));
      await t.pumpAndSettle();

      final panel = find.byKey(WardrobeChipSection.panelKey);
      expect(panel, findsOneWidget);
      expect(
        find.descendant(
          of: panel,
          matching: find.byKey(WardrobeChipSection.enableKey),
        ),
        findsOneWidget,
      );
      expect(find.text('WEARING'), findsOneWidget);
    });
  });
}
