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

// The soft gate has no length (docs/design/afterglow-recovery-overhaul.md,
// decision 4): its tenderness window is fixed at ~15 story minutes. But the
// block's "always shown" slider parked at a neutral 90 MINUTES under
// "None / multiorgasmic" — a number the mode never uses — and dragging it
// called withMinutes(), which silently flips recoveryMode to a hard lock,
// yanking the card out of multiorgasmic by accident. Maintainer ruling
// 2026-10-18: the slider hides for that preset; a plain-English line takes
// its place. Auto and the locked presets keep it — there a length genuinely
// exists (the judge's) and the slider is the honest Custom shortcut.
// Mirrored in web_ui (RealismFormSection.tsx RecoveryBlock).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_optional_features_card.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/recovery_block.dart';

import '../../golden/support/fakes_storage.dart';

void main() {
  testWidgets('None / multiorgasmic hides the minutes slider and the '
      'judge-length hint, and says why instead', (tester) async {
    await tester.pumpWidget(
      _wrap(const RecoveryProfile(recoveryMode: kRecoveryModeSoft)),
    );

    expect(
      find.byKey(const Key('recovery-minutes-slider')),
      findsNothing,
      reason:
          'a slider parked at 90 min under a mode that has no length '
          'is a lie the author can drag into a hard lock',
    );
    expect(find.text('Recovery minutes'), findsNothing);
    expect(
      find.textContaining("judge's length"),
      findsNothing,
      reason: 'the judge decides no length on the soft gate',
    );
    final hint = tester.widget<Text>(
      find.byKey(const Key('recovery-clock-off-hint')),
    );
    expect(hint.data, contains('no length to set'));
    expect(hint.data, contains('~15 min tenderness window is fixed'));
  });

  testWidgets('hard presets keep the slider where it always was', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const RecoveryProfile(
          recoveryMode: kRecoveryModeHard,
          recoveryMinutes: 90,
        ),
      ),
    );

    expect(find.byKey(const Key('recovery-minutes-slider')), findsOneWidget);
    expect(find.text('Recovery minutes'), findsOneWidget);
    expect(find.byKey(const Key('recovery-clock-off-hint')), findsOneWidget);
  });

  testWidgets('auto keeps the slider and the judge-length hint', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(RecoveryProfile.auto));

    expect(find.byKey(const Key('recovery-minutes-slider')), findsOneWidget);
    expect(
      find.textContaining('judge\'s length becomes'),
      findsOneWidget,
      reason: 'the old null-minutes hint still belongs to the judge presets',
    );
  });

  // 2026-10-24: the per-card Afterglow switch is gone; the editor shows the
  // Recovery block under Porch Life Afterglow, which counts only with 18+ on.
  testWidgets('the editor shows Recovery under Porch Life Afterglow, '
      'never a per-card switch', (tester) async {
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    await storage.realismSettings.setNsfwCooldownDefault(false);
    await storage.realismSettings.setAdultThemesEnabled(true);

    Future<void> pumpForm() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RealismOptionalFeaturesCard(
                  chaosModeEnabled: false,
                  onChaosModeChanged: (_) {},
                  realismVerificationEnabled: false,
                  onRealismVerificationChanged: (_) {},
                  realismVerificationMaxReprocesses: 1,
                  onRealismVerificationMaxReprocessesChanged: null,
                  realismVerificationStrictness: 3,
                  onRealismVerificationStrictnessChanged: null,
                  showChaosToggle: true,
                  showVerificationToggle: false,
                  recovery: RecoveryProfile.auto,
                  onRecoveryChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pumpForm();
    expect(find.byType(RecoveryBlock), findsNothing, reason: 'Afterglow off');
    expect(find.textContaining('Afterglow'), findsNothing);

    await storage.realismSettings.setNsfwCooldownDefault(true);
    await pumpForm();
    expect(find.byType(RecoveryBlock), findsOneWidget);
    expect(find.text('Afterglow (intimacy pacing)'), findsNothing);

    await storage.realismSettings.setAdultThemesEnabled(false);
    await pumpForm();
    expect(find.byType(RecoveryBlock), findsNothing, reason: 'needs 18+');
  });

  testWidgets("the character editors' Afterglow switch: how new chats start "
      'it, with Recovery only while it is on', (tester) async {
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    final asked = <bool>[];

    Future<void> pumpCard({required bool on}) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RealismOptionalFeaturesCard(
                  chaosModeEnabled: false,
                  onChaosModeChanged: (_) {},
                  realismVerificationEnabled: false,
                  onRealismVerificationChanged: (_) {},
                  realismVerificationMaxReprocesses: 1,
                  onRealismVerificationMaxReprocessesChanged: null,
                  realismVerificationStrictness: 3,
                  onRealismVerificationStrictnessChanged: null,
                  showChaosToggle: true,
                  showVerificationToggle: false,
                  recovery: RecoveryProfile.auto,
                  onRecoveryChanged: (_) {},
                  afterglowEnabled: on,
                  onAfterglowChanged: asked.add,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Finder afterglowSwitch() => find.descendant(
      of: find
          .ancestor(of: find.text('Afterglow'), matching: find.byType(Row))
          .first,
      matching: find.byType(Switch),
    );

    await pumpCard(on: true);
    expect(tester.widget<Switch>(afterglowSwitch()).value, isTrue);
    expect(find.byType(RecoveryBlock), findsOneWidget);
    await tester.tap(afterglowSwitch());
    expect(asked, [false]);

    await pumpCard(on: false);
    expect(tester.widget<Switch>(afterglowSwitch()).value, isFalse);
    expect(find.byType(RecoveryBlock), findsNothing);

    await storage.realismSettings.setNsfwCooldownDefault(false);
    await pumpCard(on: true);
    expect(find.text('Afterglow'), findsNothing, reason: 'absent, not greyed');
  });
}

Widget _wrap(RecoveryProfile recovery) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: RecoveryBlock(
        recovery: recovery,
        sex: 'female',
        intimateInto: const [],
        intimateNotInto: const [],
        onChanged: (_) {},
      ),
    ),
  ),
);
