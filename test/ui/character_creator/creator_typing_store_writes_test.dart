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

// TYPING IN THE AI CREATOR TOOK UP TO A SECOND PER KEY ON WINDOWS (#371).
//
// Every keystroke in the creator's text boxes ran CreatorState.saveState(),
// which wrote all 71 wizard preferences one after another. On Windows and
// Linux each preference write re-encodes the whole preferences map and
// rewrites the whole file synchronously, so one key cost 71 file rewrites on
// the UI thread before the character could be drawn. macOS keeps preferences
// in NSUserDefaults, which is why it never showed there.
//
// This test types into EVERY text box of each creation mode and counts the
// writes that reach the real legacy preferences store (its platform channel
// is answered here, so each write is counted where it would cost a rewrite).
// Nothing may be written while the user types; one write, of the field that
// changed, lands once they pause; and leaving the wizard mid-pause still
// keeps the last letters.
//
// Proven to fail first: before the fix every box cost 71 writes per key.
// Each part of the fix was removed in turn and reds a check here: the
// changed-only save (71 writes after the pause), each mode's typing handler
// (writes while typing), the flush on leaving (text lost), and Guided's
// immediate redraw (the Generate button stays off).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

const _channel = MethodChannel('plugins.flutter.io/shared_preferences');

/// The platform side of the legacy preferences store, recording each write.
class _PrefsStore {
  final Map<String, Object> data = {};
  final List<MapEntry<String, Object>> writes = [];

  /// Writes of the wizard's own keys since [from] (an index into [writes]).
  List<MapEntry<String, Object>> wizardWritesSince(int from) => writes
      .sublist(from)
      .where((w) => w.key.startsWith('flutter.chargen_'))
      .toList();

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments is Map ? call.arguments as Map : const {};
    switch (call.method) {
      case 'getAll':
      case 'getAllWithParameters':
        return Map<String, Object>.of(data);
      case 'setString':
      case 'setBool':
      case 'setInt':
      case 'setDouble':
      case 'setStringList':
        final key = args['key'] as String;
        final value = args['value'] as Object;
        data[key] = value;
        writes.add(MapEntry(key, value));
        return true;
      case 'remove':
        data.remove(args['key']);
        return true;
      case 'clear':
      case 'clearWithParameters':
        data.clear();
        return true;
    }
    return null;
  }
}

/// The real HardwareService shells out on detection; Setup needs no answer.
class _NoHardware extends ChangeNotifier implements HardwareService {
  @override
  HardwareInfo? get hardwareInfo => null;
  @override
  bool get isDetecting => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SetupCapableStorage extends FakeStorageService {
  _SetupCapableStorage() {
    backendSettings.setBackendType('kobold');
  }
}

/// Which preference each text box is saved under; `null` = never saved.
Map<TextEditingController, String?> _prefKeyOf(CreatorState s) => {
  s.nameController: 'chargen_name',
  s.conceptController: 'chargen_concept',
  s.keywordsController: 'chargen_keywords',
  s.ageController: 'chargen_age',
  s.sexController: 'chargen_sex',
  s.relationshipController: 'chargen_relationship',
  s.quickScenarioController: 'chargen_quick_scenario',
  s.customRaceController: 'chargen_custom_race',
  s.customKinksController: 'chargen_custom_kinks',
  s.backstoryNotesController: 'chargen_backstory_notes',
  s.guidedVisionController: 'chargen_guided_vision',
  s.guidedAppearanceController: 'chargen_guided_appearance',
  s.guidedHairController: 'chargen_guided_hair',
  s.guidedFeaturesController: 'chargen_guided_features',
  s.guidedRaceController: 'chargen_guided_race',
  s.guidedPersonalityController: 'chargen_guided_personality',
  s.guidedSpeechController: 'chargen_guided_speech',
  s.guidedSecretController: 'chargen_guided_secret',
  s.guidedOriginController: 'chargen_guided_origin',
  s.guidedSettingController: 'chargen_guided_setting',
  s.guidedToneController: 'chargen_guided_tone',
  s.guidedRelDynamicController: 'chargen_guided_rel_dynamic',
  s.guidedRelScenarioController: 'chargen_guided_rel_scenario',
  s.guidedNsfwBodyController: 'chargen_guided_nsfw_body',
  s.guidedNsfwExpController: 'chargen_guided_nsfw_exp',
  s.guidedNsfwDomController: 'chargen_guided_nsfw_dom',
  s.guidedNsfwKinksController: 'chargen_guided_nsfw_kinks',
  s.guidedNsfwClothingController: 'chargen_guided_nsfw_clothing',
  s.guidedNsfwPersonalityController: 'chargen_guided_nsfw_personality',
  s.loreUrlsController: null,
};

CreatorState _stateOf(WidgetTester tester) {
  final dynamic pageState = tester.state(find.byType(CharacterCreatorPage));
  return pageState.creatorState as CreatorState;
}

Finder _boxFor(TextEditingController c) => find
    .byWidgetPredicate((w) => w is TextField && identical(w.controller, c))
    .first;

/// Pumps the real wizard with the providers its Setup step reads.
Future<void> _pumpApp(WidgetTester tester, Widget home) async {
  await tester.binding.setSurfaceSize(const Size(1280, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final llm = FakeLLMProvider();
  final storage = _SetupCapableStorage();
  final personas = FakeUserPersonaService();
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
      child: MaterialApp(home: home),
    ),
  );
  await tester.pump();
}

/// Moves the wizard to the Configure step of [mode], then saves once so the
/// store holds every key: the first save ever writes them all, by design, and
/// this test is about what each keystroke costs after that.
Future<void> _openConfigure(
  WidgetTester tester,
  CreatorState state,
  CreatorMode mode,
) async {
  state.creatorMode = mode;
  state.currentStep = 2;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  state.saveState();
  await tester.pump();
  await tester.pump();
}

/// Opens every collapsed section so each text box of the step is on screen.
Future<void> _openEverySection(WidgetTester tester) async {
  final tiles = tester.widgetList<ExpansionTile>(find.byType(ExpansionTile));
  for (final tile in tiles.toList()) {
    if (tile.initiallyExpanded) continue;
    final header = find
        .descendant(of: find.byWidget(tile), matching: find.byType(ListTile))
        .first;
    await tester.ensureVisible(header);
    await tester.pump();
    await tester.tap(header);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Types into every enabled text box on the step, one at a time, and checks
/// what reached the store while typing and after the user paused.
Future<void> _typeIntoEveryBox(
  WidgetTester tester,
  _PrefsStore store,
  CreatorState state,
) async {
  final keys = _prefKeyOf(state);
  final boxes = <TextEditingController>{
    for (final f in tester.widgetList<TextField>(find.byType(TextField)))
      if ((f.enabled ?? true) && !f.readOnly && f.controller != null)
        f.controller!,
  };
  expect(boxes, isNotEmpty);
  for (final c in boxes) {
    final key = keys[c];
    final label = key ?? (keys.containsKey(c) ? 'lore URLs' : 'unknown box');
    final box = _boxFor(c);
    await tester.ensureVisible(box);
    await tester.pump();
    await tester.showKeyboard(box);
    await tester.pump();

    final mark = store.writes.length;
    var text = c.text;
    for (final ch in const ['W', 'r', 'e', 'n']) {
      text += ch;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    final whileTyping = store.wizardWritesSince(mark);
    await tester.pump(const Duration(milliseconds: 600));
    final afterPause = store.wizardWritesSince(mark);

    expect(
      whileTyping,
      isEmpty,
      reason: '$label: nothing may be saved while the user is still typing',
    );
    if (key != null) {
      expect(afterPause.map((w) => '${w.key}=${w.value}'), [
        'flutter.$key=${c.text}',
      ], reason: '$label: one write, of what was typed, once the user pauses');
    } else if (keys.containsKey(c)) {
      expect(afterPause, isEmpty, reason: '$label are never saved');
    } else {
      expect(
        afterPause.length,
        lessThanOrEqualTo(1),
        reason: '$label: the pause must not rewrite the whole wizard',
      );
    }
  }
}

/// Opens the wizard from a launcher screen, types into the box [boxOf]
/// picks, and leaves with the AppBar's back arrow before the pause is over.
Future<void> _typeThenLeave(
  WidgetTester tester,
  _PrefsStore store,
  CreatorMode mode,
  TextEditingController Function(CreatorState) boxOf,
  String key,
) async {
  await _pumpApp(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            // No transition, so the wizard is gone the frame after Back
            // instead of after an animation that could outlast the pause.
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
                pageBuilder: (_, _, _) => const CharacterCreatorPage(),
              ),
            ),
            child: const Text('Open creator'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open creator'));
  await tester.pump();
  await tester.pump();
  final state = _stateOf(tester);
  await _openConfigure(tester, state, mode);

  final box = _boxFor(boxOf(state));
  await tester.ensureVisible(box);
  await tester.pump();
  await tester.showKeyboard(box);
  await tester.pump();
  final mark = store.writes.length;
  tester.testTextInput.updateEditingValue(
    const TextEditingValue(
      text: 'Wren',
      selection: TextSelection.collapsed(offset: 4),
    ),
  );
  await tester.pump();
  expect(store.wizardWritesSince(mark), isEmpty);

  // Back well inside the half-second pause, so only the flush on leaving
  // can have saved what follows.
  await tester.tap(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.arrow_back),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(find.byType(CharacterCreatorPage), findsNothing);
  expect(
    store.data['flutter.$key'],
    'Wren',
    reason: 'letters typed just before leaving must not be lost',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PrefsStore store;

  setUp(() {
    store = _PrefsStore();
    SharedPreferences.resetStatic();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, store.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    SharedPreferences.resetStatic();
  });

  testWidgets('Quick: typing in any box does not rewrite the whole wizard', (
    tester,
  ) async {
    await _pumpApp(tester, const CharacterCreatorPage());
    final state = _stateOf(tester);
    // Third person shows the Sex box inside the greeting-voice picker.
    state.narrativePerspective = 'third';
    await _openConfigure(tester, state, CreatorMode.quick);
    await _openEverySection(tester);
    await _typeIntoEveryBox(tester, store, state);
  });

  testWidgets('Guided: typing in any box does not rewrite the whole wizard', (
    tester,
  ) async {
    await _pumpApp(tester, const CharacterCreatorPage());
    final state = _stateOf(tester);
    state.nsfwEnabled = true; // shows the Intimate Details boxes too
    await _openConfigure(tester, state, CreatorMode.guided);
    await _openEverySection(tester);
    await _typeIntoEveryBox(tester, store, state);
  });

  testWidgets(
    'Automated: typing in any box does not rewrite the whole wizard',
    (tester) async {
      await _pumpApp(tester, const CharacterCreatorPage());
      final state = _stateOf(tester);
      state.nsfwEnabled = true; // shows the Custom Kinks box
      state.conceptGenerated = true; // unlocks the Description box
      await _openConfigure(tester, state, CreatorMode.automated);
      await _openEverySection(tester);
      await _typeIntoEveryBox(tester, store, state);
    },
  );

  testWidgets('Guided: the name wakes the Generate button at once, '
      'before anything is saved', (tester) async {
    await _pumpApp(tester, const CharacterCreatorPage());
    final state = _stateOf(tester);
    await _openConfigure(tester, state, CreatorMode.guided);
    final generate = find.ancestor(
      of: find.text('Generate Character Description'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    await tester.ensureVisible(generate);
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(generate).onPressed, isNull);

    final box = _boxFor(state.nameController);
    await tester.ensureVisible(box);
    await tester.pump();
    final mark = store.writes.length;
    await tester.enterText(box, 'W');
    await tester.pump();

    expect(
      tester.widget<ButtonStyleButton>(generate).onPressed,
      isNotNull,
      reason: 'only the save waits for a pause; the screen must not',
    );
    expect(store.wizardWritesSince(mark), isEmpty);
  });

  testWidgets('Quick: leaving mid-pause keeps the last letters', (
    tester,
  ) async {
    await _typeThenLeave(
      tester,
      store,
      CreatorMode.quick,
      (s) => s.nameController,
      'chargen_name',
    );
  });

  testWidgets('Guided: leaving mid-pause keeps the last letters', (
    tester,
  ) async {
    await _typeThenLeave(
      tester,
      store,
      CreatorMode.guided,
      (s) => s.guidedVisionController,
      'chargen_guided_vision',
    );
  });

  testWidgets('Automated: leaving mid-pause keeps the last letters', (
    tester,
  ) async {
    await _typeThenLeave(
      tester,
      store,
      CreatorMode.automated,
      (s) => s.nameController,
      'chargen_name',
    );
  });
}
