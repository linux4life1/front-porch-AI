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

// The Objectives switch and the Ambitions dependency it now carries
// (docs/design/feature-independence.md; maintainer ruling 2026-08-07:
// "Ambitions should only require objectives. And objectives depends on
// nothing other than its eval cost.").
//
// Two things worth pinning here. First, Objectives had NO switch at all
// before this — it fired a completion check on a recurring cadence forever
// with no way to stop it — so the row existing and being live is the feature.
// Second, Ambitions must now be chipped as needing Objectives rather than
// standing alone, because finishing a quest is the only thing that moves
// ambition progress; a chip that says "works alone" there would be a lie.
//
// Note (as in the sibling nets): rows whose onChanged calls a ChatService
// extension method cannot be tapped against a fake — those are statically
// resolved against the real class's privates. Objectives is such a row, so
// this file asserts its presence, chip and live switch, and drives the
// dependency through storage instead of through a tap on that row.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// Real [RealismSettings] behind a [StorageService] fake, so every flag keeps
/// its production default and `notify()` bridges into `context.watch`.
class _ObjStorage extends FakeStorageService {
  _ObjStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_ObjStorage> pumpTab(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _ObjStorage();
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
    return storage;
  }

  Finder rowFor(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Row)).first;

  testWidgets('Objectives has a switch at last, and it is live', (
    tester,
  ) async {
    final storage = await pumpTab(tester);
    final scrollable = find.byType(Scrollable).first;

    // Before this change there was NO objectives switch anywhere in the app,
    // while the completion check fired on a recurring cadence forever.
    final label = find.text('Objectives');
    await tester.scrollUntilVisible(label, 300, scrollable: scrollable);
    expect(label, findsOneWidget);

    expect(
      storage.realismSettings.objectivesEnabled,
      isTrue,
      reason:
          'objectives ran unconditionally before the switch existed, so '
          'the default must be ON or the update would quietly stop quests '
          'for everyone',
    );

    // "works alone" is the ruling: objectives depend on nothing but their own
    // eval cost — not the engine, not the Journal.
    expect(
      find.descendant(
        of: rowFor('Objectives'),
        matching: find.text('works alone'),
      ),
      findsOneWidget,
      reason: 'Objectives depends on nothing else, and the chip must say so',
    );

    // The copy has to admit the recurring cost — that is the reason to have
    // the switch at all.
    expect(
      find.textContaining('check in with the AI'),
      findsOneWidget,
      reason: 'the row must state plainly that it spends model calls',
    );

    final sw = tester.widget<Switch>(
      find
          .descendant(of: rowFor('Objectives'), matching: find.byType(Switch))
          .first,
    );
    expect(
      sw.onChanged,
      isNotNull,
      reason:
          'nothing gates Objectives, so its switch is always live — '
          'including with the Realism Engine off, which is the default',
    );
    expect(
      storage.realismSettings.realismDefault,
      isFalse,
    ); // engine off, and it did not matter
  });

  testWidgets('Ambitions now hangs off Objectives, not the engine', (
    tester,
  ) async {
    final storage = await pumpTab(tester);
    final scrollable = find.byType(Scrollable).first;

    final amb = find.text('Ambitions');
    await tester.scrollUntilVisible(amb, 300, scrollable: scrollable);

    // The chip states the real dependency. It said "works alone" before, which
    // was wrong in one direction (progress needs quests) while the sidebar hid
    // the feature behind the engine, which was wrong in the other.
    expect(
      find.descendant(
        of: rowFor('Ambitions'),
        matching: find.text('needs Objectives'),
      ),
      findsOneWidget,
      reason:
          'finishing a quest is the ONLY thing that moves ambition '
          'progress, so Objectives is the honest dependency',
    );

    // Satisfied while Objectives is on: the switch is live.
    expect(
      tester
          .widget<Switch>(
            find
                .descendant(
                  of: rowFor('Ambitions'),
                  matching: find.byType(Switch),
                )
                .first,
          )
          .onChanged,
      isNotNull,
    );

    // Turn Objectives off and the dependant gates, exactly as the tab's
    // design language promises for an unmet requirement.
    await storage.realismSettings.setObjectivesEnabled(false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.scrollUntilVisible(amb, 300, scrollable: scrollable);
    expect(
      tester
          .widget<Switch>(
            find
                .descendant(
                  of: rowFor('Ambitions'),
                  matching: find.byType(Switch),
                )
                .first,
          )
          .onChanged,
      isNull,
      reason:
          'with Objectives off nothing can move ambition progress, so the '
          'row must gate rather than pretend to work',
    );
  });
}
