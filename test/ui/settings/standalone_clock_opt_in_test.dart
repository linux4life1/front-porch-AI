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

// Interaction net for the standalone-clock opt-in on the Porch Life tab
// (docs/design/feature-independence.md — Passage of Time decoupled from the
// Realism Engine, 2026-08-06).
//
// The property that actually matters here is the DEFAULT, not the plumbing.
// Passage of Time already defaults ON, and for years that meant nothing while
// the engine was off; if the standalone clock rode that flag it would hand a
// new per-turn model call to every existing engine-off user without asking —
// the exact cost the maintainer declined. So this net pins: the opt-in starts
// off, it only appears where it means something (engine off), it is absent
// where it would be a choice about nothing (engine on), and tapping it flips
// the real flag on a real RealismSettings.
//
// Companion coverage: standalone_clock_test.dart proves the engine-off clock
// advances identically to the engine's own. This file proves a user can reach
// the switch that turns it on, and that nobody gets it by accident.
//
// Note (carried from the sibling net): rows whose onChanged calls through
// `extension ChatServiceControls on ChatService` cannot be tapped against a
// fake — those are static extension methods reaching into ChatService's
// privates. Passage of Time is such a row, so this file taps only the
// standalone sub-switch, whose onChanged is pure StorageService.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// Same shape as the sibling net's double: a REAL [RealismSettings] behind a
/// [StorageService] fake, so every flag keeps its true production default and
/// `notify()` bridges back into `context.watch<StorageService>()`.
/// SharedPreferences is left null, making its writes harmless no-ops.
class _ClockStorage extends FakeStorageService {
  _ClockStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const kSubLabel = 'Keep the clock running without the engine';

  Future<(_ClockStorage, FakeChatService)> pumpTab(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _ClockStorage();
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(home: Scaffold(body: PorchLifeTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    return (storage, chat);
  }

  testWidgets(
    'the standalone clock is opt-in, reachable, and off until asked for',
    (tester) async {
      final (storage, _) = await pumpTab(tester);

      // The whole point: nobody inherits this. Passage of Time is ON by
      // default and the engine is OFF by default — the exact pair that would
      // silently start billing a call per turn if this rode that flag.
      expect(
        storage.realismSettings.realismDefault,
        isFalse,
        reason:
            'this net is meaningless unless the engine starts OFF, '
            'which is the production default',
      );
      expect(
        storage.realismSettings.passageOfTimeDefault,
        isTrue,
        reason:
            'Passage of Time defaults ON — that is why the standalone '
            'clock cannot treat it as consent',
      );
      expect(
        storage.realismSettings.standaloneClockEnabled,
        isFalse,
        reason:
            'the standalone clock must default OFF; anything else spends '
            "an existing user's tokens without asking",
      );

      final scrollable = find.byType(Scrollable).first;
      final subFinder = find.text(kSubLabel);
      await tester.scrollUntilVisible(subFinder, 300, scrollable: scrollable);
      expect(
        subFinder,
        findsOneWidget,
        reason:
            'with the engine off the opt-in must be visible — an '
            'unreachable switch is the same as no feature',
      );

      // The copy has to state the cost. This is a token-spending switch, and
      // the rule is that we never spend a user's budget without saying so.
      expect(
        find.textContaining('one short AI call of its own each turn'),
        findsOneWidget,
        reason: 'the opt-in must say plainly that it costs a call per turn',
      );

      // Tap it: a real flip of a real RealismSettings flag.
      final sw = find.descendant(
        of: find.ancestor(of: subFinder, matching: find.byType(Row)).first,
        matching: find.byType(Switch),
      );
      expect(sw, findsOneWidget);
      final live = tester.widget<Switch>(sw);
      expect(
        live.onChanged,
        isNotNull,
        reason:
            'the opt-in must be live with the engine off — that is the '
            'only state in which it means anything',
      );

      await tester.tap(sw);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        storage.realismSettings.standaloneClockEnabled,
        isTrue,
        reason: 'tapping the opt-in must flip the real storage flag',
      );
    },
  );

  testWidgets(
    'with the engine on, the opt-in is absent — it would decide nothing',
    (tester) async {
      final (storage, _) = await pumpTab(tester);

      // Turn the engine on through storage rather than by tapping the Realism
      // Engine row, whose onChanged calls a ChatService extension method no
      // fake can satisfy (see the header note).
      await storage.realismSettings.setRealismDefault(true);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Passage of Time itself must still be there — decoupling the clock did
      // not remove the feature, and this catches an over-eager gate.
      final scrollable = find.byType(Scrollable).first;
      final timeRow = find.text('Passage of Time');
      await tester.scrollUntilVisible(timeRow, 300, scrollable: scrollable);
      expect(timeRow, findsOneWidget);

      expect(
        find.text(kSubLabel),
        findsNothing,
        reason:
            'with the engine on the clock already rides its reading of '
            'the scene for free, so offering a switch would be a choice '
            'about nothing',
      );
    },
  );
}
