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

// The "After Dark" group and the Growth Rings row — both restored to match the
// approved Porch Life sketch (artifact 3bee9e58).
//
// The sketch is explicit that the adult group is "shown only when 18+ themes
// are enabled". We had shipped that row inside "The Engine", visible to
// everyone, so a user who had never asked for adult content still saw an 18+
// switch. Absent is the requirement here, not dimmed — the tab's gating idiom
// (dead switch + dim) is for an unmet DEPENDENCY, which is a different thing
// from content someone has not opted into.
//
// The seed is the subtle part and is tested below: adultThemesEnabled has no
// stored value until someone chooses one, and until then it tracks
// nsfwCooldownDefault. Without that, shipping this group would have hidden the
// Afterglow switch from every existing user who was already running it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// Real [RealismSettings] behind the storage fake so the seed logic under test
/// is the production one. SharedPreferences null ⇒ writes are no-ops and
/// nothing is ever "explicitly chosen" unless this test chooses it.
class _AdultStorage extends FakeStorageService {
  _AdultStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_AdultStorage> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _AdultStorage();
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('with 18+ off, the adult group is absent — not merely dimmed', (
    tester,
  ) async {
    final storage = await pump(tester);
    expect(
      storage.realismSettings.adultThemesEnabled,
      isFalse,
      reason: 'nothing has opted in, and Afterglow is off, so the seed is off',
    );

    expect(
      find.text('After Dark'),
      findsNothing,
      reason:
          'the sketch says this group is shown ONLY when 18+ themes are '
          'enabled — a user who never asked for adult content should not be '
          'shown an adult switch at all',
    );
    expect(find.text('Afterglow'), findsNothing);
  });

  testWidgets('turning 18+ on reveals the group and its row', (tester) async {
    final storage = await pump(tester);
    await storage.realismSettings.setAdultThemesEnabled(true);
    await settle(tester);

    final scrollable = find.byType(Scrollable).first;
    final group = find.text('After Dark');
    await tester.scrollUntilVisible(group, 300, scrollable: scrollable);
    expect(group, findsOneWidget);

    expect(
      find.text('shown only when 18+ themes are on'),
      findsOneWidget,
      reason: 'the group subtitle should say why it is conditional',
    );
    expect(find.text('Afterglow'), findsOneWidget);
  });

  testWidgets(
    'an existing Afterglow user keeps their switch without opting in again',
    (tester) async {
      // The regression this guards: shipping the group with a plain `false`
      // default would have hidden Afterglow from everyone already running it,
      // stripping a setting they had deliberately turned on.
      final storage = await pump(tester);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      await settle(tester);

      expect(
        storage.realismSettings.adultThemesEnabled,
        isTrue,
        reason:
            'with no explicit choice stored, 18+ visibility tracks whether '
            'an adult feature is actually in use',
      );
      final scrollable = find.byType(Scrollable).first;
      final row = find.text('Afterglow');
      await tester.scrollUntilVisible(row, 300, scrollable: scrollable);
      expect(row, findsOneWidget);
    },
  );

  testWidgets('an explicit choice overrides the seed', (tester) async {
    final storage = await pump(tester);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await storage.realismSettings.setAdultThemesEnabled(false);
    await settle(tester);

    expect(
      storage.realismSettings.adultThemesEnabled,
      isFalse,
      reason: 'once the user has chosen, the seed must stop speaking for them',
    );
    expect(find.text('After Dark'), findsNothing);
  });

  testWidgets('Growth Rings is a row on the tab, per the sketch', (
    tester,
  ) async {
    await pump(tester);
    final scrollable = find.byType(Scrollable).first;
    final row = find.text('Growth Rings');
    await tester.scrollUntilVisible(row, 300, scrollable: scrollable);
    expect(
      row,
      findsOneWidget,
      reason:
          'the sketch lists Growth Rings under Memory & Heart; it was '
          'missing because its global (characterEvolutionEnabled) already '
          'existed but had never been surfaced here',
    );
    expect(
      find.textContaining('rings, not rewrites'),
      findsOneWidget,
      reason: "the sketch's own copy for this row",
    );
  });
}
