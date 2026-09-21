// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// THE AI CHARACTER CREATOR'S NAV ROW STAYED LIVE DURING GENERATION.
//
// The AppBar's back arrow and the reset action are both gated on isGenerating,
// but the Back / "Next: …" pair at the bottom of the wizard was not. So while a
// generation streamed, Back → Generate started a SECOND CharacterGenService
// over the first: activeGenService points only at the newest one, so "Abort
// Generation" left the first still running, and whichever finished last stomped
// generatedCard plus all six review controllers and yanked the user to the
// Realism step. Pressing Next instead jumped to step 4, where RealismStep shows
// "Generation failed. The LLM did not produce valid output." for a card that is
// still being written.
//
// Red-proved: dropping the `busy ? null :` guards makes both disabled-state
// expectations fail (onPressed comes back non-null).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// The real HardwareService shells out to `system_profiler` on construction-
/// driven detection, which leaves a pending timer the test binding rejects.
/// Nothing on the Setup step needs a real answer.
class _NoHardware extends ChangeNotifier implements HardwareService {
  @override
  HardwareInfo? get hardwareInfo => null;
  @override
  bool get isDetecting => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The Setup step (step 0, built before the test can move on) reads three
/// backend getters the shared storage fake does not carry. Answering them here
/// keeps the fake untouched.
class _SetupCapableStorage extends FakeStorageService {
  _SetupCapableStorage() {
    backendSettings.setBackendType('kobold');
  }
}

/// The page owns its CreatorState privately; reach it the way the wizard's own
/// steps do — through the State object — so the test can put the page into the
/// exact condition the bug needs (mid-generation) without a live backend.
CreatorState _stateOf(WidgetTester tester) {
  final dynamic pageState = tester.state(find.byType(CharacterCreatorPage));
  return pageState.creatorState as CreatorState;
}

ButtonStyleButton _button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Back and Next lock while a generation is running', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final llm = FakeLLMProvider();
    final storage = _SetupCapableStorage();
    final personas = FakeUserPersonaService();
    // The Setup step reads these two for its local-model picker; neither does
    // any work in a static render.
    final kobold = KoboldService(storage);
    final models = ModelManager(
      storage,
      DownloadManager(targetDir: Directory.systemTemp.path),
    );
    final hardware = _NoHardware();
    for (final s in [llm, storage, personas, kobold, models, hardware]) {
      addTearDown(s.dispose);
    }

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

    final state = _stateOf(tester);

    // Step 3 is the Generating step — the screen the user is looking at while
    // the model streams, and the one both buttons were reachable from.
    state.currentStep = 3;
    await tester.pump();

    expect(
      _button(tester, 'Back').onPressed,
      isNotNull,
      reason: 'sanity: nothing is running yet, so Back still works',
    );
    expect(_button(tester, 'Next: Realism').onPressed, isNotNull);

    state.isGenerating = true;
    state.notify();
    await tester.pump();

    expect(
      _button(tester, 'Back').onPressed,
      isNull,
      reason: 'Back → Generate is how a second concurrent generation starts',
    );
    expect(
      _button(tester, 'Next: Realism').onPressed,
      isNull,
      reason:
          'Next lands on RealismStep, which calls a null card a failure '
          'while the generation is still streaming',
    );

    // The escape hatch the user is meant to take is still the Abort button on
    // the Generating step itself.
    expect(find.text('Abort Generation'), findsOneWidget);

    state.isGenerating = false;
    state.notify();
    await tester.pump();
    expect(_button(tester, 'Back').onPressed, isNotNull);
  });
}
