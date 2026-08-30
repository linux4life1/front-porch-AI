// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/time_strip.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/porch_accordion.dart';
import 'package:front_porch_ai/ui/pages/home/open_section_env.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../../golden/support/fakes.dart';

void main() {
  testWidgets('journal collapses Character State and expands Journal header', (
    tester,
  ) async {
    final keys = await _pumpAccordions(tester);
    expect(keys.cs.currentState!.isExpanded, isTrue);
    expect(keys.journal.currentState!.isExpanded, isFalse);

    OpenSectionEnv.apply(
      section: OpenSectionEnv.journal,
      isGroup: false,
      isLite: false,
      collapseCharacterState: () => keys.cs.currentState?.collapse(),
      expandJournal: () => keys.journal.currentState?.expand(),
      journalKey: keys.journal,
    );
    await tester.pump();
    await tester.pump();

    expect(keys.cs.currentState!.isExpanded, isFalse);
    expect(keys.journal.currentState!.isExpanded, isTrue);
    expect(keys.journal.currentContext, isNotNull);
  });

  testWidgets(
    'objectives collapses Character State and Journal; stays collapsed',
    (tester) async {
      final keys = await _pumpAccordions(tester);
      var expanded = 0;

      OpenSectionEnv.apply(
        section: OpenSectionEnv.objectives,
        isGroup: false,
        isLite: false,
        collapseCharacterState: () => keys.cs.currentState?.collapse(),
        collapseJournal: () => keys.journal.currentState?.collapse(),
        expandObjectives: () => expanded++,
        objectivesKey: keys.objectivesHeader,
      );
      await tester.pump();
      await tester.pump();

      expect(keys.cs.currentState!.isExpanded, isFalse);
      expect(keys.journal.currentState!.isExpanded, isFalse);
      expect(keys.objectives.currentState!.isExpanded, isFalse);
      expect(expanded, 0);
      expect(keys.objectivesHeader.currentContext, isNotNull);
    },
  );

  testWidgets('objectives still scrolls when the feature flag is off', (
    tester,
  ) async {
    final keys = await _pumpAccordions(tester);
    var expanded = 0;

    OpenSectionEnv.apply(
      section: OpenSectionEnv.objectives,
      isGroup: false,
      isLite: false,
      collapseCharacterState: () => keys.cs.currentState?.collapse(),
      collapseJournal: () => keys.journal.currentState?.collapse(),
      expandObjectives: () => expanded++,
      objectivesKey: keys.objectivesHeader,
    );
    await tester.pump();
    await tester.pump();

    expect(keys.cs.currentState!.isExpanded, isFalse);
    expect(keys.objectives.currentState!.isExpanded, isFalse);
    expect(expanded, 0);
    expect(keys.objectivesHeader.currentContext, isNotNull);
  });

  testWidgets(
    'objectives skips group and lite where the accordion cannot exist',
    (tester) async {
      final keys = await _pumpAccordions(tester);
      var expanded = 0;

      OpenSectionEnv.apply(
        section: OpenSectionEnv.objectives,
        isGroup: true,
        isLite: false,
        collapseCharacterState: () => keys.cs.currentState?.collapse(),
        expandObjectives: () => expanded++,
      );
      OpenSectionEnv.apply(
        section: OpenSectionEnv.objectives,
        isGroup: false,
        isLite: true,
        collapseCharacterState: () => keys.cs.currentState?.collapse(),
        expandObjectives: () => expanded++,
      );
      await tester.pump();
      await tester.pump();
      expect(expanded, 0);
      expect(keys.cs.currentState!.isExpanded, isTrue);
      expect(keys.objectives.currentState!.isExpanded, isFalse);

      OpenSectionEnv.apply(
        section: OpenSectionEnv.objectives,
        isGroup: false,
        isLite: false,
        collapseCharacterState: () => keys.cs.currentState?.collapse(),
        collapseJournal: () => keys.journal.currentState?.collapse(),
        expandObjectives: () => expanded++,
        objectivesKey: keys.objectivesHeader,
      );
      await tester.pump();
      await tester.pump();
      expect(expanded, 0);
      expect(keys.cs.currentState!.isExpanded, isFalse);
      expect(keys.journal.currentState!.isExpanded, isFalse);
      expect(keys.objectives.currentState!.isExpanded, isFalse);
    },
  );

  testWidgets(
    'objectives collapses Journal so the title is on a short surface',
    (tester) async {
      const surface = Size(230, 400);
      final keys = await _pumpAccordions(
        tester,
        startJournalExpanded: true,
        journalChildHeight: 400,
        surfaceSize: surface,
      );
      expect(keys.journal.currentState!.isExpanded, isTrue);
      expect(keys.cs.currentState!.isExpanded, isTrue);
      expect(keys.objectives.currentState!.isExpanded, isFalse);

      var expanded = 0;
      OpenSectionEnv.apply(
        section: OpenSectionEnv.objectives,
        isGroup: false,
        isLite: false,
        collapseCharacterState: () => keys.cs.currentState?.collapse(),
        collapseJournal: () => keys.journal.currentState?.collapse(),
        expandObjectives: () => expanded++,
        objectivesKey: keys.objectivesHeader,
      );
      await tester.pump();
      await tester.pump();
      // afterExpanded's ensureVisible runs in the second post-frame;
      // one more zero-duration pump flushes the scroll before AnimatedSize
      // shrinks Journal and would leave a stale offset.
      await tester.pump();

      expect(expanded, 0);
      expect(keys.journal.currentState!.isExpanded, isFalse);
      expect(keys.cs.currentState!.isExpanded, isFalse);
      expect(keys.objectives.currentState!.isExpanded, isFalse);

      final rect = tester.getRect(find.text('Objectives'));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(surface.height));

      // Story Tools (Places) sits after Objectives. A tall next sibling
      // would park at the viewport top if ensureVisible targeted the
      // accordion+child instead of the header row.
      final placesRect = tester.getRect(find.text('Places'));
      expect(placesRect.top, greaterThan(rect.top));
      expect(placesRect.top, greaterThan(16));
    },
  );

  testWidgets('timestrip expands Character State and finds TimeStrip', (
    tester,
  ) async {
    final keys = await _pumpAccordions(tester, startCsExpanded: false);
    expect(find.byType(TimeStrip), findsNothing);

    OpenSectionEnv.apply(
      section: OpenSectionEnv.timestrip,
      isGroup: false,
      isLite: false,
      expandCharacterState: () => keys.cs.currentState?.expand(),
      timeStripKey: keys.timeStrip,
    );
    await tester.pump();
    await tester.pump();

    expect(keys.cs.currentState!.isExpanded, isTrue);
    expect(find.byType(TimeStrip), findsOneWidget);
    expect(keys.timeStrip.currentContext, isNotNull);
  });

  testWidgets('timestrip skips lite chats where Character State is absent', (
    tester,
  ) async {
    var expanded = 0;
    OpenSectionEnv.apply(
      section: OpenSectionEnv.timestrip,
      isGroup: false,
      isLite: true,
      expandCharacterState: () => expanded++,
    );
    expect(expanded, 0);
  });
}

class _Keys {
  _Keys({
    required this.cs,
    required this.journal,
    required this.objectives,
    required this.objectivesHeader,
    required this.timeStrip,
  });

  final GlobalKey<PorchAccordionState> cs;
  final GlobalKey<PorchAccordionState> journal;
  final GlobalKey<PorchAccordionState> objectives;
  final GlobalKey objectivesHeader;
  final GlobalKey timeStrip;
}

Future<_Keys> _pumpAccordions(
  WidgetTester tester, {
  bool startCsExpanded = true,
  bool startJournalExpanded = false,
  double journalChildHeight = 80,
  Size surfaceSize = const Size(400, 700),
}) async {
  final chat = FakeChatService(timeOfDay: 'morning', dayCount: 3);
  addTearDown(chat.dispose);

  final keys = _Keys(
    cs: GlobalKey<PorchAccordionState>(),
    journal: GlobalKey<PorchAccordionState>(),
    objectives: GlobalKey<PorchAccordionState>(),
    objectivesHeader: GlobalKey(),
    timeStrip: GlobalKey(),
  );

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
      home: Scaffold(
        body: SizedBox(
          width: 230,
          child: ListView(
            padding: const EdgeInsets.all(12),
            cacheExtent: 2000,
            children: [
              Builder(
                builder: (context) => PorchAccordion(
                  key: keys.cs,
                  id: 'character_state',
                  emoji: '🎭',
                  title: 'Character State',
                  accent: AppColors.porchTerracottaOf(context),
                  initiallyExpanded: startCsExpanded,
                  child: TimeStrip(key: keys.timeStrip, chat: chat),
                ),
              ),
              Builder(
                builder: (context) => PorchAccordion(
                  key: keys.journal,
                  id: 'journal_memory',
                  emoji: '📖',
                  title: 'Journal & Memory',
                  accent: AppColors.porchHoneyOf(context),
                  initiallyExpanded: startJournalExpanded,
                  child: SizedBox(height: journalChildHeight),
                ),
              ),
              Builder(
                builder: (context) => PorchAccordion(
                  key: keys.objectives,
                  headerKey: keys.objectivesHeader,
                  id: 'objectives',
                  emoji: '🎯',
                  title: 'Objectives',
                  accent: AppColors.porchHoneyOf(context),
                  initiallyExpanded: false,
                  child: const SizedBox(height: 500),
                ),
              ),
              Builder(
                builder: (context) => PorchAccordion(
                  id: 'places',
                  emoji: '📍',
                  title: 'Places',
                  accent: AppColors.porchHoneyOf(context),
                  initiallyExpanded: true,
                  child: const SizedBox(height: 500),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return keys;
}
