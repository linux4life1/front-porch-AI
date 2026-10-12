// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_wizard_sit_down_step.dart';

/// Wizard flow: one tap picks the folder, Back works everywhere, Start
/// shows it is busy, and the copy uses plain words.
void main() {
  final mira = CharacterCard(name: 'Mira');

  Widget wizard({bool reduceMotion = false}) {
    final page = WaifuWizardPage(
      characters: [mira],
      backendLabel: 'test-model',
      initialFolder: '/tmp/waifu-ux',
      onSatDown: (_) {},
      listDirectory: (path) async => WaifuFolderListing(
        path: path,
        parentPath: null,
        directories: const [],
        projectHints: const [],
      ),
    );
    return MaterialApp(
      home: reduceMotion
          ? Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: page,
              ),
            )
          : page,
    );
  }

  testWidgets('Use this folder moves on in one tap; Back works on every '
      'later step', (tester) async {
    await tester.pumpWidget(wizard());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waifu-wizard-back')), findsNothing);

    await tester.tap(find.byKey(const Key('waifu-use-folder')));
    await tester.pumpAndSettle();
    expect(find.text('Mira'), findsWidgets, reason: 'on the Coworker step');

    await tester.tap(find.text('Mira'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waifu-wizard-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waifu-sit-down-confirm')), findsOneWidget);
    expect(find.text('Start'), findsWidgets);

    await tester.tap(find.byKey(const Key('waifu-wizard-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waifu-sit-down-confirm')), findsNothing);
    expect(find.byKey(const Key('waifu-wizard-next')), findsOneWidget);

    await tester.tap(find.byKey(const Key('waifu-wizard-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waifu-use-folder')), findsOneWidget);
  });

  testWidgets('reduce motion swaps steps without a cross-fade', (tester) async {
    await tester.pumpWidget(wizard(reduceMotion: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waifu-use-folder')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Project folder'), findsNothing);
  });

  Widget startStep({bool starting = false, String? error}) => MaterialApp(
    home: Scaffold(
      body: WaifuWizardSitDownStep(
        folderPath: '/tmp/waifu-ux',
        coworker: mira,
        backendLabel: 'remote',
        isLocalBackend: false,
        toolsSupported: true,
        mode: WaifuMode.build,
        pathMode: WaifuPathMode.folderJail,
        honestyAccepted: true,
        onModeChanged: (_) {},
        onPathModeChanged: (_) {},
        onHonestyChanged: (_) {},
        onConfirm: () {},
        starting: starting,
        startError: error,
      ),
    ),
  );

  testWidgets('Start says it is working and shows why it failed', (
    tester,
  ) async {
    await tester.pumpWidget(startStep(starting: true));
    final button = find.byKey(const Key('waifu-sit-down-confirm'));
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    expect(find.byKey(const Key('waifu-starting')), findsOneWidget);
    expect(find.text('Starting…'), findsOneWidget);

    await tester.pumpWidget(startStep(error: 'Could not start: disk full'));
    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
    expect(find.text('Could not start: disk full'), findsOneWidget);
  });

  testWidgets('honesty is three bullets and the modes explain themselves', (
    tester,
  ) async {
    await tester.pumpWidget(startStep());
    for (final point in waifuHonestyPoints(WaifuPathMode.folderJail)) {
      expect(find.textContaining(waifuEmphasisPlain(point)), findsOneWidget);
    }
    expect(waifuHonestyPoints(WaifuPathMode.wholeDisk), hasLength(3));
    expect(
      find.descendant(
        of: find.byKey(const Key('waifu-honesty-body')),
        matching: find.text('•  '),
      ),
      findsNWidgets(3),
    );
    for (final m in WaifuMode.values) {
      expect(find.byTooltip(waifuModeTooltip(m)), findsOneWidget);
    }
    expect(find.text(waifuModeTooltip(WaifuMode.build)), findsOneWidget);
  });

  test('scope labels are plain words, not jail or porch', () {
    for (final scope in WaifuPathMode.values) {
      final copy = [
        waifuPathModeTitle(scope),
        waifuPathModeBlurb(scope),
        waifuScopeBadgeLabel(scope),
        waifuPathModeSessionLine(scope),
        waifuEmptyPrompt(scope, 'Mira'),
        waifuHonestyBody(scope),
        waifuHonestyCheckbox(scope),
        waifuYoloWarning(scope),
      ].join(' ').toLowerCase();
      expect(copy, isNot(contains('jail')));
      expect(copy, isNot(contains('porch')));
    }
    expect(waifuPathModeTitle(WaifuPathMode.folderJail), contains('folder'));
    expect(waifuPathModeTitle(WaifuPathMode.wholeDisk), 'Whole disk');
    expect(kWaifuHonestySkipped.toLowerCase(), isNot(contains('jail')));
  });
}
