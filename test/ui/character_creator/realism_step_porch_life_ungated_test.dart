// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Feature Design lock: engine OFF on the AI creator RealismStep must still
// show Porch Life (Time, Chaos, wardrobe / ambitions / likes) and hide
// engine-only seeds (Needs, bond/trust, starting emotion, Afterglow,
// Director). Intimate lists appear only when 18+ is on.
//
// Sibling of test/ui/widgets/realism_form_porch_life_ungated_test.dart, which
// pumps RealismFormSection alone — no RealismStep, no needsFormSection, no
// calendar callbacks, no 18+ path. This file pumps the public step so a
// wiring regression (forgetting StoryBeginsRow callbacks, dropping Needs,
// wrapping Time/Chaos behind the switch on the step) fails here even when
// the form-level test stays green.
//
// Finder/widget test only — not a pixel golden. ChipListEditor uppercases
// labels (`WEARING`), so assertions match that surface.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/steps/realism_step.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes_storage.dart';

CreatorState _seedState({required bool engineOn}) {
  final state = CreatorState();
  state.realismStepEnabled = engineOn;
  // A card is required or RealismStep renders ValueKey('realism-error').
  state.generatedCard = CharacterCard(name: 'Aria Vale');
  return state;
}

Widget _app(CreatorState state, {StorageService? storage}) {
  Widget home = Scaffold(body: RealismStep(state: state));
  if (storage != null) {
    home = ChangeNotifierProvider<StorageService>.value(
      value: storage,
      child: home,
    );
  }
  return MaterialApp(home: home);
}

void _expectPorchLifeVisible() {
  expect(find.byKey(const ValueKey('realism')), findsOneWidget);
  expect(find.byKey(const ValueKey('realism-error')), findsNothing);
  expect(find.byType(RealismFormSection), findsOneWidget);
  expect(find.byType(IdentityChipLists), findsOneWidget);
  expect(find.byType(StoryBeginsRow), findsOneWidget);
  expect(find.text('Porch Life'), findsOneWidget);
  expect(find.text('Enable Realism Engine'), findsOneWidget);
  expect(find.text('Time & Day'), findsOneWidget);
  expect(find.text('Time of Day'), findsOneWidget);
  expect(find.text('Day Number'), findsOneWidget);
  expect(find.text('Story begins: the day the chat starts'), findsOneWidget);
  expect(find.text('Chaos Mode (Chance Time)'), findsOneWidget);
  expect(find.text('Pockets & Wardrobe'), findsOneWidget);
  expect(find.text('WEARING'), findsOneWidget);
  expect(find.text('CARRYING'), findsOneWidget);
  expect(find.text('Ambitions'), findsOneWidget);
  expect(find.text('LONG-TERM GOALS'), findsOneWidget);
  expect(find.text('Likes & Dislikes'), findsOneWidget);
  expect(find.text('DRAWN TO'), findsOneWidget);
  expect(find.text('PUT OFF BY'), findsOneWidget);
}

void _expectEngineOnlyHidden() {
  expect(find.byType(NeedsFormSection), findsNothing);
  expect(find.text('Needs Simulation'), findsNothing);
  expect(find.text('Short-Term Bond'), findsNothing);
  expect(find.text('Long-Term Bond'), findsNothing);
  expect(find.text('Trust Level'), findsNothing);
  expect(find.text('Starting Emotion'), findsNothing);
  expect(find.text('Afterglow (intimacy pacing)'), findsNothing);
  expect(find.text('Realism Verification (Director/Verifier)'), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('engine off keeps Porch Life and hides engine-only seeds', (
    tester,
  ) async {
    final state = _seedState(engineOn: false);
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    _expectPorchLifeVisible();
    _expectEngineOnlyHidden();
    // No StorageService in scope → adultThemesEnabledOf is false.
    expect(find.text('Intimate preferences'), findsNothing);
    expect(find.text('WARMS TO'), findsNothing);
    expect(find.text('NOT INTERESTED IN'), findsNothing);
  });

  testWidgets('engine off still shows intimate lists when 18+ is on', (
    tester,
  ) async {
    final state = _seedState(engineOn: false);
    addTearDown(state.dispose);
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    // adultThemesEnabledOf reads realismSettings, not StorageService's
    // own adultThemesEnabled getter (the fake's top-level getter is true
    // for Porch Life goldens and would be the wrong switch here).
    await storage.realismSettings.setAdultThemesEnabled(true);

    await tester.pumpWidget(_app(state, storage: storage));
    await tester.pumpAndSettle();

    _expectPorchLifeVisible();
    _expectEngineOnlyHidden();
    expect(find.text('Intimate preferences'), findsOneWidget);
    expect(find.text('WARMS TO'), findsOneWidget);
    expect(find.text('NOT INTERESTED IN'), findsOneWidget);
  });

  testWidgets(
    'engine on reveals Needs and bond because RealismStep wires them',
    (tester) async {
      final state = _seedState(engineOn: true);
      addTearDown(state.dispose);

      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();

      _expectPorchLifeVisible();
      expect(find.byType(NeedsFormSection), findsOneWidget);
      // Header + toggle row both say this; one would be a false red.
      expect(find.text('Needs Simulation'), findsAtLeastNWidgets(1));
      expect(find.text('Short-Term Bond'), findsOneWidget);
      expect(find.text('Long-Term Bond'), findsOneWidget);
      expect(find.text('Trust Level'), findsOneWidget);
      expect(find.text('Starting Emotion'), findsOneWidget);
      expect(find.text('Afterglow (intimacy pacing)'), findsOneWidget);
      expect(
        find.text('Realism Verification (Director/Verifier)'),
        findsOneWidget,
      );
    },
  );
}
