// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Planner row on Porch Life: default off, gated on time + objectives + journal.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _PlannerStorage extends FakeStorageService {
  _PlannerStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_PlannerStorage> pumpTab(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _PlannerStorage();
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
    await tester.pump();
    return storage;
  }

  Finder rowFor(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Row)).first;

  testWidgets('Planner row exists, default off', (tester) async {
    final storage = await pumpTab(tester);
    final scrollable = find.byType(Scrollable).first;
    final label = find.text('Planner');
    await tester.scrollUntilVisible(label, 300, scrollable: scrollable);
    expect(label, findsOneWidget);
    expect(storage.realismSettings.plannerEnabled, isFalse);

    final sw = tester.widget<Switch>(
      find
          .descendant(of: rowFor('Planner'), matching: find.byType(Switch))
          .first,
    );
    expect(sw.value, isFalse);
  });

  testWidgets('Planner is unsatisfied if time, objectives, or journal is off', (
    tester,
  ) async {
    final storage = await pumpTab(tester);
    final scrollable = find.byType(Scrollable).first;

    await storage.memorySettings.setJournalEnabled(false);
    await tester.pump();

    final label = find.text('Planner');
    await tester.scrollUntilVisible(label, 300, scrollable: scrollable);
    expect(
      find.textContaining('needs Passage of Time, Objectives, and the Journal'),
      findsWidgets,
    );
    final gated = tester.widget<Switch>(
      find
          .descendant(of: rowFor('Planner'), matching: find.byType(Switch))
          .first,
    );
    expect(gated.onChanged, isNull, reason: 'unsatisfied row must be gated');
  });
}
