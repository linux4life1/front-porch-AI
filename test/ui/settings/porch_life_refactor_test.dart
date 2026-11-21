// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';
import 'package:front_porch_ai/ui/settings/widgets/feature_row.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _RefactorStorage extends FakeStorageService {
  _RefactorStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<_RefactorStorage> pumpTab(
    WidgetTester tester, {
    Size size = const Size(1200, 1400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _RefactorStorage();
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
    await tester.pumpAndSettle();
    return storage;
  }

  testWidgets(
    'renders two columns at 1200px and one column at 400px with zero overflow',
    (tester) async {
      await pumpTab(tester, size: const Size(1200, 1400));
      final engineX = tester.getTopLeft(find.text('The Engine')).dx;
      final memoryX = tester.getTopLeft(find.text('Memory & Heart')).dx;
      expect(
        memoryX,
        greaterThan(engineX + 200),
        reason: 'Memory & Heart sits in the right column on wide screens',
      );
      expect(tester.takeException(), isNull);

      await pumpTab(tester, size: const Size(400, 1400));
      final engineNarrowPos = tester.getTopLeft(find.text('The Engine'));
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Memory & Heart'),
        300,
        scrollable: scrollable,
      );
      final memoryNarrowPos = tester.getTopLeft(find.text('Memory & Heart'));
      expect(
        (memoryNarrowPos.dx - engineNarrowPos.dx).abs(),
        lessThan(24),
        reason: 'Cards stack in a single column on 400px screens',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'starts expanded, toggles details by clicking title/subtitle or batch button, omits badges except cross-subgroup needs',
    (tester) async {
      await pumpTab(tester, size: const Size(1200, 2200));

      // Starts expanded: subtitles, body details, and groups are all visible.
      expect(
        find.text(
          'Tracks bond, trust, physical state, and lingering moods across turns.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Slow character evolution'), findsOneWidget);
      expect(find.text('How often'), findsOneWidget);

      // No group batch collapse, no per-row Hide details, and no clutter badges.
      expect(find.text('Collapse all groups'), findsNothing);
      expect(find.text('Hide details'), findsNothing);
      expect(find.text('works alone'), findsNothing);
      expect(find.text('CORE'), findsNothing);
      expect(find.text('Extra AI call'), findsNothing);
      expect(find.text('Per-chat'), findsNothing);
      expect(find.text('Live global'), findsNothing);

      // Clicking a row's title or subtitle toggles that row's details.
      await tester.tap(find.text('Growth Rings'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Slow character evolution'), findsNothing);
      await tester.tap(
        find.text(
          'Adds lived experience as slow layers without rewriting who they are.',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Slow character evolution'), findsOneWidget);

      // Batch collapse all details hides body prose while keeping subtitles & sub-controls.
      await tester.tap(find.text('Collapse all details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Slow character evolution'), findsNothing);
      expect(
        find.text(
          'Adds lived experience as slow layers without rewriting who they are.',
        ),
        findsOneWidget,
      );
      expect(find.text('How often'), findsOneWidget);
      expect(find.text('Expand all details'), findsOneWidget);

      // Batch expand restores body prose.
      await tester.tap(find.text('Expand all details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Slow character evolution'), findsOneWidget);
    },
  );

  testWidgets(
    'Memory & Heart holds Growth Rings, Objectives, Ambitions, and Planner; cross-subgroup badge auto-expands target group',
    (tester) async {
      await pumpTab(tester, size: const Size(1200, 2400));

      final memoryGroup = find.widgetWithText(
        FeatureGroupCard,
        'Memory & Heart',
      );
      expect(
        find.descendant(of: memoryGroup, matching: find.text('Growth Rings')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: memoryGroup, matching: find.text('Objectives')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: memoryGroup, matching: find.text('Ambitions')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: memoryGroup, matching: find.text('Planner')),
        findsOneWidget,
      );

      // Collapse Time & World individually, then tap Dreams' cross-subgroup chip.
      await tester.tap(find.text('Time & World'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FeatureRow, 'Passage of Time'), findsNothing);

      await tester.tap(find.text('needs Passage of Time'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FeatureRow, 'Passage of Time'),
        findsOneWidget,
        reason: 'tapping a dependency chip auto-expands the target group',
      );
    },
  );
}
