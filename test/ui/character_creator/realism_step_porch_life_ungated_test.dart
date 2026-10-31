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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state_engine.core.dart';
import 'package:front_porch_ai/ui/character_creator/steps/realism_step.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
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
  // Section header + toggle row + IdentityChipLists header all say this
  // now that RealismStep wires the per-char pair. Exactly-one is a false
  // red — same shape as Needs Simulation below.
  expect(find.text('Pockets & Wardrobe'), findsAtLeastNWidgets(1));
  // Unique toggle subtitle: the new control is on the step, not only the
  // older chip-list header.
  expect(find.textContaining('skips inventory tracking'), findsOneWidget);
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
      // 2026-10-24: no per-card Afterglow switch any more; Porch Life
      // Afterglow (with 18+ on) is the one gate.
      expect(find.text('Afterglow (intimacy pacing)'), findsNothing);
      expect(
        find.text('Realism Verification (Director/Verifier)'),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows the values generation seeded, through the same controls', (
    tester,
  ) async {
    final state = _seedState(engineOn: true);
    addTearDown(state.dispose);
    // What Phase A (the facts) and Phase B (mood, time, outfit) write on
    // the card, applied the way the creator applies it.
    final card = CharacterCard(name: 'Aria Vale')
      ..frontPorchExtensions = FrontPorchExtensions(
        shortTermBond: 15,
        trustLevel: 12,
        characterEmotion: 'wistful',
        emotionIntensity: 'strong',
        timeOfDay: 'evening',
        occupation: 'lighthouse keeper',
        birthday: '1998-03-14',
        currentTask: 'Trim the lamp before the storm.',
      );
    CreatorGenerationCore(state).applyGeneratedRealism(card);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    RealismSliderRow slider(String label) => tester
        .widgetList<RealismSliderRow>(find.byType(RealismSliderRow))
        .firstWhere((w) => w.label == label);
    expect(slider('Short-Term Bond').value, 15);
    expect(slider('Trust Level').value, 12);
    final mood = tester.widget<RealismEmotionCard>(
      find.byType(RealismEmotionCard),
    );
    expect(mood.emotion, 'wistful');
    expect(mood.emotionIntensity, 'strong');
    expect(
      tester
          .widget<RealismTimeDayCard>(find.byType(RealismTimeDayCard))
          .timeOfDay,
      'evening',
    );
    final identity = tester.widget<IdentityChipLists>(
      find.byType(IdentityChipLists),
    );
    expect(identity.occupation, 'lighthouse keeper');
    expect(identity.birthday, '1998-03-14');
    expect(state.realismCurrentTask, 'Trim the lamp before the storm.');
  });

  // The engine switch opens on Porch Life's, not on a hard-coded off.
  testWidgets('Porch Life engine on opens the step with the engine on', (
    tester,
  ) async {
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    await storage.realismSettings.setRealismDefault(true);
    final state = CreatorState();
    addTearDown(state.dispose);
    state.generatedCard = CharacterCard(name: 'Aria Vale');

    state.seedRealismFromPorchLife(storage);

    expect(state.realismStepEnabled, isTrue);
    await tester.pumpWidget(_app(state, storage: storage));
    await tester.pumpAndSettle();
    _expectPorchLifeVisible();
    expect(find.byType(NeedsFormSection), findsOneWidget);
    expect(find.text('Short-Term Bond'), findsOneWidget);
    expect(find.text('Starting Emotion'), findsOneWidget);
  });

  testWidgets('Porch Life engine off opens the step with the engine off', (
    tester,
  ) async {
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    await storage.realismSettings.setRealismDefault(false);
    // A switch left on by an earlier visit must not outlive the global.
    final state = _seedState(engineOn: true);
    addTearDown(state.dispose);

    state.seedRealismFromPorchLife(storage);

    expect(state.realismStepEnabled, isFalse);
    await tester.pumpWidget(_app(state, storage: storage));
    await tester.pumpAndSettle();
    _expectPorchLifeVisible();
    _expectEngineOnlyHidden();
  });

  test(
    'Clear Everything puts the switch back on the Porch Life value',
    () async {
      final storage = FakeStorageService();
      addTearDown(storage.dispose);
      final state = CreatorState();
      addTearDown(state.dispose);

      await storage.realismSettings.setRealismDefault(true);
      state.seedRealismFromPorchLife(storage);
      state.realismStepEnabled = false;
      state.resetAllFields();
      expect(state.realismStepEnabled, isTrue);

      await storage.realismSettings.setRealismDefault(false);
      state.seedRealismFromPorchLife(storage);
      state.realismStepEnabled = true;
      state.resetAllFields();
      expect(state.realismStepEnabled, isFalse);
    },
  );

  // The page is where the creator meets StorageService: leaving its call out
  // leaves every other guard here green and the product unchanged.
  testWidgets('the creator page opens its Realism switch on Porch Life\'s', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final llm = FakeLLMProvider();
    final storage = FakeStorageService();
    final personas = FakeUserPersonaService();
    final kobold = KoboldService(storage);
    final models = ModelManager(
      storage,
      DownloadManager(targetDir: Directory.systemTemp.path),
    );
    final hardware = FakeHardwareService();
    for (final s in [llm, storage, personas, kobold, models, hardware]) {
      addTearDown(s.dispose);
    }
    // The Setup step reads the backend type at build; the fake defaults to
    // a remote one.
    await storage.backendSettings.setBackendType('kobold');
    await storage.realismSettings.setRealismDefault(true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<UserPersonaService>.value(value: personas),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
          ChangeNotifierProvider<ModelManager>.value(value: models),
          ChangeNotifierProvider<HardwareService>.value(value: hardware),
        ],
        child: const MaterialApp(home: CharacterCreatorPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    final dynamic page = tester.state(find.byType(CharacterCreatorPage));
    expect((page.creatorState as CreatorState).realismStepEnabled, isTrue);
  });

  testWidgets("the card's Afterglow switch shows while Porch Life allows "
      'Afterglow, and sets how new chats start it', (tester) async {
    final state = _seedState(engineOn: true);
    addTearDown(state.dispose);
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);

    await tester.pumpWidget(_app(state, storage: storage));
    await tester.pumpAndSettle();
    final afterglowSwitch = find.descendant(
      of: find
          .ancestor(of: find.text('Afterglow'), matching: find.byType(Row))
          .first,
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(afterglowSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(afterglowSwitch).value, isTrue);
    await tester.tap(afterglowSwitch);
    await tester.pumpAndSettle();
    expect(state.realismAfterglow, isFalse);
  });

  test("the saved card starts new chats with the creator's Afterglow "
      'switch', () async {
    setupPathProviderMock();
    final storage = await makeGoldenStorage();
    final db = AppDatabase.forTesting();
    final repo = CharacterRepository(db, storage);
    addTearDown(() async => db.close());
    final state = CreatorState();
    addTearDown(state.dispose);
    final card = CharacterCard(name: 'Aria Vale', description: 'A keeper.');
    state.generatedCard = card;
    state.realismAfterglow = false;
    expect(await state.saveCharacter(repo: repo, storage: storage), isTrue);
    expect(card.frontPorchExtensions?.afterglowEnabled, isFalse);
  });
}
