// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// THE AI CREATOR'S GREETINGS STEP (#370), driven through the real wizard.
//
// Every mode's Generate lands on Greetings. There, a steered Regenerate sends
// the steer to the model as a direction and puts the new text (name turned
// into {{char}}) in the box; while it is written only Stop works and Back and
// Next wait, but the AppBar's back arrow keeps today's lock. Stop leaves the
// old text. Delete takes an alternate and its starting state together. Add
// writes a new one until 5, then waits. A new first message leaves the outfit
// alone and the Realism step offers the re-read, which runs the creation pass
// on the NEW first message; Keep this outfit just closes the hint. Each
// greeting's starting state stays on Review.
//
// The model is the scripted LLMService the creator tests already use (it
// answers by what the prompt asks for). The real CharacterGenService builds
// the prompts and cleans the text.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

const _name = 'Aria Vale';

/// Answers each chargen stage by what its prompt asks for. A greeting can be
/// held after its first words, the way a slow model leaves one half written;
/// abortGeneration (what Stop sends) lets it go, as a closed connection would.
class _GreetingLlm extends LLMService {
  final List<String> greetingPrompts = [];
  final List<String> porchPrompts = [];
  String nextGreeting = '*$_name trims the lamp wick.* "Another ship lost?"';
  Map<String, List<String>> porch = const {
    'worn': ['oilskin coat'],
    'carrying': ['brass spyglass'],
  };
  bool holdNext = false;
  Completer<void>? _held;
  int _created = 0;

  void release() {
    final held = _held;
    if (held != null && !held.isCompleted) held.complete();
  }

  @override
  void abortGeneration() => release();

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('Seed Porch Life identity')) {
      porchPrompts.add(p);
      yield jsonEncode({
        'ambitions': ['keep the lamp lit'],
        ...porch,
      });
      return;
    }
    if (p.contains('Write an opening roleplay message')) {
      greetingPrompts.add(p);
      // Creation writes three greetings per card; after that, the step.
      final text = greetingPrompts.length <= 3 * CreatorMode.values.length
          ? '*$_name looks up from the logbook.* "Opening ${++_created}."'
          : nextGreeting;
      if (holdNext) {
        holdNext = false;
        yield text.substring(0, 20);
        final held = _held = Completer<void>();
        await held.future;
        _held = null;
        yield text.substring(20);
        return;
      }
      yield text;
      return;
    }
    if (p.contains('completely different meeting scenarios')) {
      yield '{"scenarios": ["a market at noon", "a storm on the jetty"]}';
      return;
    }
    yield jsonEncode({
      'description': '{{char}} keeps the lighthouse on a wind-scoured cape.',
      'personality': 'Patient, dry-humored, never leaves a lamp unlit.',
      'scenario': '{{user}} climbs the tower stairs at dusk.',
      'tags': ['lighthouse'],
      'lorebook': {'entries': []},
    });
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'scripted-test';
}

class _Provider extends FakeLLMProvider {
  _Provider(this.svc);
  final LLMService svc;

  @override
  LLMService? serviceForModel(String selectedModelId) => svc;

  @override
  LLMService get activeService => svc;
}

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

CreatorState _stateOf(WidgetTester tester) {
  final dynamic pageState = tester.state(find.byType(CharacterCreatorPage));
  return pageState.creatorState as CreatorState;
}

VoidCallback? _pressable(WidgetTester tester, String key) {
  final f = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byWidgetPredicate(
      (w) => w is ButtonStyleButton || w is IconButton,
    ),
  );
  final w = tester.widget(f.first);
  return w is IconButton ? w.onPressed : (w as ButtonStyleButton).onPressed;
}

ButtonStyleButton _navButton(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Greetings: every mode, steer, stop, delete, add, the cap, and '
      'the outfit hint', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final llm = _GreetingLlm();
    final provider = _Provider(llm);
    final storage = _SetupCapableStorage();
    final personas = FakeUserPersonaService();
    final kobold = KoboldService(storage);
    final models = ModelManager(
      storage,
      DownloadManager(targetDir: Directory.systemTemp.path),
    );
    final hardware = _NoHardware();
    // Review's Portrait & Avatars panel reads these two at build.
    final repo = FakeCharacterRepository();
    final images = ImageGenService(storage);
    for (final s in [
      provider,
      storage,
      personas,
      kobold,
      models,
      hardware,
      repo,
      images,
    ]) {
      addTearDown(s.dispose);
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LLMProvider>.value(value: provider),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<UserPersonaService>.value(value: personas),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
          ChangeNotifierProvider<ModelManager>.value(value: models),
          ChangeNotifierProvider<HardwareService>.value(value: hardware),
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
          ChangeNotifierProvider<ImageGenService>.value(value: images),
        ],
        child: const MaterialApp(home: CharacterCreatorPage()),
      ),
    );
    await tester.pump();
    final state = _stateOf(tester);

    // ── Every mode's Generate lands on Greetings, with every greeting ──
    for (final mode in CreatorMode.values) {
      state
        ..creatorMode = mode
        ..quickGreetingCount = 2
        ..altGreetingCount = 2
        ..selectedTones = {'Neutral', 'Romantic', 'Wholesome'}
        ..quickSelectedTones = ['Neutral', 'Romantic', 'Wholesome']
        ..narrativePerspective = 'third'
        ..narrativeTense = 'past';
      state.nameController.text = _name;
      state.sexController.text = 'female';
      await state.generateFromMode(
        llmProvider: provider,
        storage: storage,
        personaService: personas,
      );
      await _settle(tester);
      expect(state.currentStep, 4, reason: '$mode: Generate → Greetings');
      expect(find.text('Greetings'), findsNWidgets(2)); // heading + step dot
      expect(find.byKey(const ValueKey('greeting-box-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('greeting-box-2')), findsOneWidget);
      expect(find.text('2 of 5'), findsOneWidget);
      expect(find.text('Next: Realism'), findsOneWidget);
    }
    expect(state.realismWorn, ['oilskin coat'], reason: 'set at creation');

    // ── A steered Regenerate of the first message, held halfway ──
    final oldFirst = state.firstMessageController.text;
    await tester.enterText(
      find.byKey(const ValueKey('greeting-steer-0')),
      'start at the harbor at dawn',
    );
    llm
      ..holdNext = true
      ..nextGreeting =
          '*$_name coiled a rope on the harbor wall as the sun came up.* '
          '"Early, {{user}}."';
    await _tap(tester, find.byKey(const ValueKey('greeting-regenerate-0')));

    expect(find.text('Writing…'), findsOneWidget);
    // The first 20 characters, as they streamed in.
    expect(find.textContaining('*$_name coiled a'), findsOneWidget);
    expect(find.byKey(const ValueKey('greeting-stop')), findsOneWidget);
    expect(_pressable(tester, 'greeting-regenerate-1'), isNull);
    expect(_pressable(tester, 'greeting-delete-1'), isNull);
    expect(_pressable(tester, 'greeting-add'), isNull);
    expect(_navButton(tester, 'Back').onPressed, isNull);
    expect(_navButton(tester, 'Next: Realism').onPressed, isNull);
    final appBarBack = tester.widget<IconButton>(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithIcon(IconButton, Icons.arrow_back),
      ),
    );
    expect(
      appBarBack.onPressed,
      isNotNull,
      reason:
          'the AppBar back arrow keeps today\'s lock (whole-card '
          'generation only); leaving stops the write',
    );
    expect(state.firstMessageController.text, oldFirst);

    llm.release();
    await _settle(tester);
    expect(find.text('Writing…'), findsNothing);
    expect(
      state.firstMessageController.text,
      '*{{char}} coiled a rope on the harbor wall as the sun came up.* '
      '"Early, {{user}}."',
    );
    final steered = llm.greetingPrompts.last;
    expect(steered, contains('== DIRECTION FROM THE AUTHOR =='));
    expect(steered, contains('start at the harbor at dawn'));
    expect(steered, contains('Third person past tense'), reason: 'card voice');
    expect(
      steered,
      isNot(contains('Tone: Romantic')),
      reason: 'the first message keeps the first tone (Neutral)',
    );
    expect(state.realismWorn, ['oilskin coat'], reason: 'outfit untouched');

    // ── Stop leaves the old text ──
    final oldAlt1 = state.altGreetingControllers[0].text;
    llm
      ..holdNext = true
      ..nextGreeting = '*This text must never land in the box at all.*';
    await _tap(tester, find.byKey(const ValueKey('greeting-regenerate-1')));
    expect(find.text('Writing…'), findsOneWidget);
    expect(
      llm.greetingPrompts.last,
      isNot(contains('DIRECTION FROM THE AUTHOR')),
      reason: 'an empty steer adds no direction',
    );
    expect(
      llm.greetingPrompts.last,
      contains('Tone: Romantic'),
      reason: 'alternate 1 keeps the tone creation gave it',
    );
    await _tap(tester, find.byKey(const ValueKey('greeting-stop')));
    expect(find.text('Writing…'), findsNothing);
    expect(state.altGreetingControllers[0].text, oldAlt1);
    expect(find.textContaining('must never land'), findsNothing);
    expect(find.byType(GreetingErrorLine), findsNothing);
    expect(_pressable(tester, 'greeting-regenerate-1'), isNotNull);
    expect(_navButton(tester, 'Next: Realism').onPressed, isNotNull);

    // ── Delete takes an alternate and its starting state together ──
    const seed = GreetingRealismSeed(characterEmotion: 'wistful');
    state.greetingSeeds = [null, seed];
    final keptAlt = state.altGreetingControllers[1].text;
    expect(find.byKey(const ValueKey('greeting-delete-0')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('greeting-delete-1')));
    expect(state.altGreetingControllers.map((c) => c.text), [keptAlt]);
    expect(state.greetingSeeds, [seed]);
    expect(find.text('1 of 5'), findsOneWidget);

    // ── Add writes one right away; Stop on an add leaves nothing ──
    llm
      ..holdNext = true
      ..nextGreeting = '*An opening that is stopped before it is done.*';
    await _tap(tester, find.byKey(const ValueKey('greeting-add')));
    expect(find.text('Alternate 2'), findsOneWidget);
    expect(find.text('Writing…'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('greeting-stop')));
    expect(find.text('Alternate 2'), findsNothing);
    expect(state.altGreetingControllers, hasLength(1));

    for (var n = 2; n <= 5; n++) {
      llm.nextGreeting = '*$_name lights the lamp for opening $n.*';
      await _tap(tester, find.byKey(const ValueKey('greeting-add')));
      expect(find.text('$n of 5'), findsOneWidget);
      expect(
        state.altGreetingControllers.last.text,
        '*{{char}} lights the lamp for opening $n.*',
      );
    }
    expect(llm.greetingPrompts.last, contains('have ALREADY been written'));
    expect(_pressable(tester, 'greeting-add'), isNull, reason: 'cap of 5');
    expect(state.greetingSeeds, hasLength(5), reason: 'seeds stay aligned');

    // ── Realism: the hint, and the re-read from the NEW first message ──
    await _tap(tester, find.text('Next: Realism'));
    expect(state.currentStep, 5);
    final hint = find.byKey(const ValueKey('outfit-hint'));
    expect(hint, findsOneWidget, reason: 'a new first message shows the hint');
    await tester.ensureVisible(hint);
    expect(find.text('The first message changed'), findsOneWidget);
    llm.porch = const {
      'worn': ['salt-stiff work shirt'],
      'carrying': ['coil of rope'],
    };
    await _tap(tester, find.byKey(const ValueKey('outfit-reread')));
    expect(state.realismWorn, ['salt-stiff work shirt']);
    expect(state.realismCarrying, ['coil of rope']);
    expect(llm.porchPrompts.last, contains('$_name coiled a rope'));
    expect(find.text('The first message changed'), findsNothing);

    // ── Keep this outfit closes the hint and changes nothing ──
    await _tap(tester, find.text('Back'));
    expect(state.currentStep, 4);
    llm.nextGreeting = '*$_name trims a wick in the lamp room.*';
    await _tap(tester, find.byKey(const ValueKey('greeting-regenerate-0')));
    await _tap(tester, find.text('Next: Realism'));
    expect(hint, findsOneWidget);
    await tester.ensureVisible(hint);
    expect(find.text('The first message changed'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('outfit-keep')));
    expect(find.text('The first message changed'), findsNothing);
    expect(state.realismWorn, ['salt-stiff work shirt']);

    // ── Each greeting's starting state stays on Review ──
    await _tap(tester, find.text('Next: Review'));
    expect(state.currentStep, 6);
    expect(find.byType(GreetingSeedForm), findsNWidgets(5));
    expect(find.text('Save & Finish'), findsOneWidget);
  });
}
