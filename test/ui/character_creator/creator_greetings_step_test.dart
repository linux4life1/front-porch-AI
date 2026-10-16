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
// writes a new one until 5, then waits. A new first message, rewritten or
// edited by hand, leaves the outfit alone and the Realism step offers the
// re-read, which runs the creation pass on the NEW first message; Keep this
// outfit just closes the hint. Each greeting's starting state stays on Review.
//
// The model is the scripted LLMService the creator tests already use (it
// answers by what the prompt asks for). The real CharacterGenService builds
// the prompts and cleans the text.
//
// Changed for #530 (the Profile step): Generate now stops on Profile (step
// 4) with nothing downstream written, and Next there writes the rest, so the
// walk presses Next on Profile before it reaches Greetings, which moved to
// step 5 (Realism 6, Review 7). Every greeting assertion is unchanged.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart'
    show kIdentityFactsToolName;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';

import '../../golden/support/fakes.dart';
import '../../services/chargen/support/failing_chargen_llm.dart';
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

/// Answers each chargen stage by what its prompt asks for, for the Profile
/// walk. The profile rewrite streams its JSON in two slices and can be held
/// after the description, the way a slow model leaves it half written;
/// abortGeneration (what Stop sends) lets it go.
class _ProfileLlm extends LLMService {
  static const baseDesc = '{{char}} keeps the lighthouse on a cape.';
  static const basePers = 'Patient, dry-humored, never leaves a lamp unlit.';

  final List<String> prompts = [];
  bool holdRewrite = false;

  /// Hold the rewrite again once its scenario has started.
  bool holdScenario = false;
  String occupation = 'lighthouse keeper';
  int factsReads = 0;
  int greetings = 0;
  int _rewrites = 0;
  int _dialogues = 0;
  int _lore = 0;
  Completer<void>? _held;

  bool sent(String marker) => prompts.any((p) => p.contains(marker));
  String promptWith(String marker) =>
      prompts.lastWhere((p) => p.contains(marker), orElse: () => '');

  @override
  void abortGeneration() => release();

  /// Let a held rewrite go on.
  void release() {
    final held = _held;
    if (held != null && !held.isCompleted) held.complete();
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    prompts.add(p);
    if (p.contains('Question: ')) {
      yield 'I talk plainly.';
      return;
    }
    if (p.contains('Rewrite the profile the way the author asked')) {
      final n = ++_rewrites;
      yield '{"description": "Rewritten description $n.", ';
      if (holdRewrite) {
        holdRewrite = false;
        final held = _held = Completer<void>();
        await held.future;
        _held = null;
      }
      yield '"personality": "Rewritten personality $n.", '
          '"scenario": "Rewritten scenario $n';
      if (holdScenario) {
        holdScenario = false;
        final held = _held = Completer<void>();
        await held.future;
        _held = null;
      }
      yield ': {{user}} climbs the tower stairs at dusk, soaked to the bone."}';
      return;
    }
    if (p.contains('Seed Porch Life identity')) {
      yield jsonEncode({
        'worn': ['oilskin coat'],
        'carrying': ['brass spyglass'],
      });
      return;
    }
    if (p.contains('Write an opening roleplay message')) {
      yield '*$_name looks up from the logbook.* "Opening ${++greetings}."';
      return;
    }
    if (p.contains('completely different meeting scenarios')) {
      yield '{"scenarios": ["a market at noon", "a storm on the jetty"]}';
      return;
    }
    if (p.contains('Write example dialogue exchanges')) {
      yield '<START>\n{{user}}: Hello\n{{char}}: Dialogue ${++_dialogues}.';
      return;
    }
    if (p.contains('Generate WORLD-BUILDING lorebook entries')) {
      final r = ++_lore;
      yield jsonEncode({
        'lorebook': [
          for (final (name, cat) in [
            ('The Cape', 'premise'),
            ('Gull Tavern', 'location'),
            ('Pilots Guild', 'faction'),
          ])
            {
              'name': '$name round $r',
              'category': cat,
              'key': name.toLowerCase(),
              'content': '$name, as written in round $r.',
            },
        ],
      });
      return;
    }
    yield jsonEncode({
      'description': baseDesc,
      'personality': basePers,
      'scenario': '{{user}} climbs the tower stairs at dusk.',
      'tags': ['lighthouse'],
      'lorebook': {'entries': []},
    });
  }

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    prompts.add(params.prompt);
    if (params.toolChoice != kIdentityFactsToolName) return null;
    factsReads++;
    return LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kIdentityFactsToolName,
          arguments: {
            'birthday_month': 3,
            'birthday_day': 14,
            'occupation': occupation,
            'current_task': 'Trim the lamp before the storm.',
            'relationship_warmth': 'strangers',
            'ambitions': ['keep the lamp lit'],
            'likes': ['salt wind'],
            'dislikes': ['fog horns'],
            'creator_notes': 'A keeper who outlasts every storm.',
          },
        ),
      ],
      text: '',
    );
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
      expect(state.currentStep, 4, reason: '$mode: Generate → Profile');
      await _tap(tester, find.text('Next: Greetings'));
      expect(state.currentStep, 5, reason: '$mode: Profile → Greetings');
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
    expect(state.currentStep, 6);
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
    expect(state.currentStep, 5);
    llm.nextGreeting = '*$_name trims a wick in the lamp room.*';
    await _tap(tester, find.byKey(const ValueKey('greeting-regenerate-0')));
    await _tap(tester, find.text('Next: Realism'));
    expect(hint, findsOneWidget);
    await tester.ensureVisible(hint);
    expect(find.text('The first message changed'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('outfit-keep')));
    expect(find.text('The first message changed'), findsNothing);
    expect(state.realismWorn, ['salt-stiff work shirt']);

    // ── A hand edit counts too: the outfit was read from words that are no
    // longer there. Keep settles it for the new words. ──
    await _tap(tester, find.text('Back'));
    expect(state.currentStep, 5);
    await tester.enterText(
      find.byKey(const ValueKey('greeting-box-0')),
      '*{{char}} waits on the stairs with a lantern.* "Took you long enough."',
    );
    await _settle(tester);
    await _tap(tester, find.text('Next: Realism'));
    expect(
      hint,
      findsOneWidget,
      reason: 'a hand edit leaves the outfit behind as much as a rewrite',
    );
    await tester.ensureVisible(hint);
    await _tap(tester, find.byKey(const ValueKey('outfit-keep')));
    expect(hint, findsNothing);
    expect(state.realismWorn, ['salt-stiff work shirt']);

    // ── Each greeting's starting state stays on Review ──
    await _tap(tester, find.text('Next: Review'));
    expect(state.currentStep, 7);
    expect(find.byType(GreetingSeedForm), findsNWidgets(5));
    expect(find.text('Save & Finish'), findsOneWidget);
  });

  testWidgets('Profile: pause after the profile, rewrite with a steer, Stop, '
      'Re-read, Next, the profile hint, and the Review rewrites', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final llm = _ProfileLlm();
    final provider = _Provider(llm);
    final storage = _SetupCapableStorage();
    final personas = FakeUserPersonaService();
    final kobold = KoboldService(storage);
    final models = ModelManager(
      storage,
      DownloadManager(targetDir: Directory.systemTemp.path),
    );
    final hardware = _NoHardware();
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
    TextEditingController box(String field) => switch (field) {
      'description' => state.descController,
      'personality' => state.personalityController,
      _ => state.scenarioController,
    };

    // ── Generate stops on Profile with nothing downstream written ──
    state
      ..creatorMode = CreatorMode.quick
      ..quickGreetingCount = 1;
    state.nameController.text = _name;
    await state.generateFromMode(
      llmProvider: provider,
      storage: storage,
      personaService: personas,
    );
    await _settle(tester);
    expect(state.currentStep, 4);
    expect(find.text('Profile'), findsNWidgets(2)); // heading + step dot
    expect(box('description').text, _ProfileLlm.baseDesc);
    expect(box('personality').text, _ProfileLlm.basePers);
    expect(box('scenario').text, isNotEmpty);
    for (final later in [
      'Write an opening roleplay message',
      'Write example dialogue exchanges',
      'Generate WORLD-BUILDING lorebook entries',
    ]) {
      expect(llm.sent(later), isFalse, reason: '$later before Next');
    }
    expect(state.firstMessageController.text, isEmpty);
    expect(state.realismOccupation, 'lighthouse keeper', reason: 'facts');
    expect(find.byKey(const ValueKey('profile-facts')), findsOneWidget);
    expect(find.text('Also written from the interview'), findsOneWidget);
    expect(find.text('Next: Greetings'), findsOneWidget);

    // ── Escape closes a chip list's add box without adding ──
    Finder inChips(String list, Finder f) => find.descendant(
      of: find.byKey(ValueKey('profile-chips-$list')),
      matching: f,
    );
    final ambitionsBefore = [...state.realismAmbitions];
    await _tap(tester, inChips('ambitions', find.text('+ add')));
    final addBox = find.byKey(const ValueKey('profile-chip-add-box'));
    expect(addBox, findsOneWidget);
    await tester.enterText(addBox, 'a stray thought');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(addBox, findsNothing, reason: 'Escape closes the add box');
    expect(state.realismAmbitions, ambitionsBefore, reason: 'nothing added');

    // ── A steered rewrite, held after the description: Description
    // streams first, Personality waits; Back and Next wait ──
    await tester.enterText(
      find.byKey(const ValueKey('profile-rewrite-steer')),
      'Does not follow the Tsundere personality type',
    );
    llm.holdRewrite = true;
    await _tap(tester, find.byKey(const ValueKey('profile-rewrite-run')));
    expect(state.profile.rewriting, isTrue);
    expect(find.text('Writing…'), findsOneWidget); // the Description card
    expect(find.text('Waiting for the description…'), findsOneWidget);
    // A generated scenario is rewritten too, third: it waits, locked.
    expect(find.text('Waiting…'), findsOneWidget);
    expect(find.text('Kept as it is'), findsNothing);
    expect(find.textContaining('Rewritten description 1'), findsOneWidget);
    expect(find.text('Re-read after the rewrite'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-rewrite-stop')), findsOneWidget);
    // What lands would overwrite edits made now, so the facts wait too.
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('profile-fact-occupation')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
    expect(inChips('ambitions', find.text('+ add')), findsNothing);
    expect(_navButton(tester, 'Back').onPressed, isNull);
    expect(_navButton(tester, 'Next: Greetings').onPressed, isNull);
    expect(
      llm.promptWith('Rewrite the profile the way the author asked'),
      contains('Does not follow the Tsundere personality type'),
    );

    // ── Stop keeps the old text everywhere ──
    final factsBefore = llm.factsReads;
    await _tap(tester, find.byKey(const ValueKey('profile-rewrite-stop')));
    expect(state.profile.rewriting, isFalse);
    expect(box('description').text, _ProfileLlm.baseDesc);
    expect(box('personality').text, _ProfileLlm.basePers);
    expect(llm.factsReads, factsBefore, reason: 'no facts read after Stop');
    expect(_navButton(tester, 'Next: Greetings').onPressed, isNotNull);

    // ── The same rewrite, to the end: the three boxes, then the facts.
    // Held once the scenario starts: it streams, locked, like the rest ──
    llm
      ..occupation = 'harbour pilot'
      ..holdScenario = true;
    await _tap(tester, find.byKey(const ValueKey('profile-rewrite-run')));
    expect(find.textContaining('Rewritten scenario 2'), findsOneWidget);
    expect(find.text('Writing…'), findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('profile-box-scenario')),
        matching: find.byType(TextField),
      ),
      findsNothing,
      reason: 'the scenario box is a writing box while it streams',
    );
    llm.release();
    await _settle(tester);
    expect(box('description').text, 'Rewritten description 2.');
    expect(box('personality').text, 'Rewritten personality 2.');
    expect(
      box('scenario').text,
      'Rewritten scenario 2: {{user}} climbs the tower stairs at dusk, soaked '
      'to the bone.',
    );
    expect(state.realismOccupation, 'harbour pilot', reason: 're-read after');

    // ── Re-read from the profile refreshes the facts card only ──
    llm.occupation = 'net mender';
    // 18+ is off on the form: a re-read leaves no intimate lists behind.
    state.realismIntimateInto = const ['moonlight swims'];
    await _tap(tester, find.byKey(const ValueKey('profile-reread')));
    expect(state.realismOccupation, 'net mender');
    expect(state.realismIntimateInto, isEmpty);
    expect(find.text('INTIMATE PREFERENCES · 18+ IS ON'), findsNothing);
    expect(box('description').text, 'Rewritten description 2.');

    // ── Next writes the rest from the profile as it is, lands on
    // Greetings, with no hint ──
    await _tap(tester, find.text('Next: Greetings'));
    expect(state.currentStep, 5);
    expect(
      llm.promptWith('Write an opening roleplay message'),
      contains('Rewritten description 2.'),
    );
    expect(state.firstMessageController.text, contains('Opening'));
    expect(find.byKey(const ValueKey('profile-hint')), findsNothing);

    // ── Back, rewrite again: the hint; Keep them changes nothing ──
    await _tap(tester, find.text('Back'));
    expect(state.currentStep, 4);
    await _tap(tester, find.byKey(const ValueKey('profile-rewrite-run')));
    await _tap(tester, find.text('Next: Greetings'));
    expect(state.currentStep, 5, reason: 'Phase B runs once');
    final greetingsSoFar = llm.greetings;
    final hint = find.byKey(const ValueKey('profile-hint'));
    expect(hint, findsOneWidget);
    expect(find.text('The profile changed'), findsOneWidget);
    final firstBefore = state.firstMessageController.text;
    await _tap(tester, find.byKey(const ValueKey('profile-hint-keep')));
    expect(hint, findsNothing);
    expect(state.firstMessageController.text, firstBefore);
    expect(llm.greetings, greetingsSoFar);

    // ── A hand edit of the description counts too; Rewrite the greetings
    // from it writes every greeting again ──
    await _tap(tester, find.text('Back'));
    await tester.enterText(
      find.byKey(const ValueKey('profile-box-description')),
      '{{char}} keeps the lamp and a grudge.',
    );
    await _settle(tester);
    await _tap(tester, find.text('Next: Greetings'));
    expect(hint, findsOneWidget, reason: 'a hand edit changes the profile');
    await _tap(tester, find.byKey(const ValueKey('profile-hint-rewrite')));
    expect(
      llm.greetings,
      greetingsSoFar + 1 + state.altGreetingControllers.length,
      reason: 'the first message and every alternate',
    );
    expect(hint, findsNothing);

    // ── An empty stamp (Enhance) is unknown: no hint ──
    await _tap(tester, find.text('Back'));
    await tester.enterText(
      find.byKey(const ValueKey('profile-box-description')),
      '{{char}} keeps the lamp, a grudge and a cat.',
    );
    await _settle(tester);
    state.greetings.recipe = state.greetings.recipe.withProfileFingerprint('');
    await _tap(tester, find.text('Next: Greetings'));
    expect(hint, findsNothing);

    // ── Review: example dialogue with a steer ──
    await _tap(tester, find.text('Next: Realism'));
    await _tap(tester, find.text('Next: Review'));
    expect(state.currentStep, 7);
    await tester.enterText(
      find.byKey(const ValueKey('review-dialogue-steer')),
      'shorter lines, more bite',
    );
    await _tap(tester, find.byKey(const ValueKey('review-dialogue-run')));
    expect(state.exampleDialogueController.text, contains('Dialogue 2'));
    expect(
      llm.promptWith('the way the author asked: shorter lines, more bite'),
      isNotEmpty,
    );

    // ── Review: the lorebook keeps an entry edited by hand ──
    final book = state.generatedCard!.lorebook!;
    expect(book.entries, hasLength(3));
    book.entries[1].content = 'The tavern my grandmother ran.';
    state.lorebookEntryEnabled[1] = false;
    state.notify();
    await _settle(tester);
    expect(find.text('Edited by hand'), findsOneWidget);
    final kept = book.entries[1];
    await _tap(tester, find.byKey(const ValueKey('review-lorebook-run')));
    final after = state.generatedCard!.lorebook!.entries;
    expect(identical(after[1], kept), isTrue, reason: 'kept in its slot');
    expect(after[1].content, 'The tavern my grandmother ran.');
    expect(after[0].name, contains('round 2'));
    expect(state.lorebookEntryEnabled[1], isFalse, reason: 'its checkbox');
    expect(state.lorebookEntryEnabled[0], isTrue);

    // ── Automated mode keeps its description on a rewrite ──
    state.creatorMode = CreatorMode.automated;
    await state.generateFromMode(
      llmProvider: provider,
      storage: storage,
      personaService: personas,
    );
    await _settle(tester);
    expect(state.currentStep, 4);
    await tester.enterText(
      find.byKey(const ValueKey('profile-rewrite-steer')),
      'warmer',
    );
    llm.holdRewrite = true;
    await _tap(tester, find.byKey(const ValueKey('profile-rewrite-run')));
    expect(find.text('Kept as you built it'), findsOneWidget);
    // Kept verbatim, so the box waits, read-only and dimmed, until the
    // rewrite ends: typing now would be thrown away.
    TextField descField() => tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('profile-box-description')),
        matching: find.byType(TextField),
      ),
    );
    expect(descField().readOnly, isTrue);
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('profile-box-description')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      0.35,
    );
    await _tap(tester, find.byKey(const ValueKey('profile-rewrite-stop')));
    expect(descField().readOnly, isFalse, reason: 'editable again after Stop');
    await tester.enterText(
      find.byKey(const ValueKey('profile-box-description')),
      'Typed after the rewrite.',
    );
    expect(state.descController.text, 'Typed after the rewrite.');

    // ── A scenario the user typed is kept: "Kept as it is", locked ──
    state.creatorMode = CreatorMode.quick;
    state.quickScenarioController.text =
        'Rain on the harbour. {{user}} brings {{char}} a stolen chart.';
    await state.generateFromMode(
      llmProvider: provider,
      storage: storage,
      personaService: personas,
    );
    await _settle(tester);
    expect(state.currentStep, 4);
    final typedScenario = box('scenario').text;
    await tester.enterText(
      find.byKey(const ValueKey('profile-rewrite-steer')),
      'sharper',
    );
    llm.holdRewrite = true;
    await _tap(tester, find.byKey(const ValueKey('profile-rewrite-run')));
    expect(find.text('Kept as it is'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('profile-box-scenario')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
    await _tap(tester, find.byKey(const ValueKey('profile-rewrite-stop')));
    expect(box('scenario').text, typedScenario);
  });

  testWidgets('Profile facts: typing the hours changes the hours and leaves '
      'the work days alone', (tester) async {
    final state = CreatorState();
    addTearDown(state.dispose);
    state.generatedCard = CharacterCard(name: _name);
    state
      ..realismHours = '9am–5pm'
      ..realismWorkDays = const [1, 2];
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: state,
              builder: (_, _) =>
                  ProfileFactsCard(state: state, onReread: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('· Mon–Tue'), findsOneWidget, reason: 'days outside');
    await tester.enterText(
      find.byKey(const ValueKey('profile-hours')),
      '6pm–6am',
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.realismHours, '6pm–6am');
    expect(state.realismWorkDays, [1, 2]);
  });

  testWidgets('Profile: a rewrite the model fails says it failed, not that '
      'it came back the same', (tester) async {
    final llm = FailingChargenLlm(failOn: 'Rewrite the profile the way')
      ..failing = true;
    final provider = _Provider(llm);
    addTearDown(provider.dispose);
    final state = CreatorState();
    addTearDown(state.dispose);
    // No retry waits: the failure arrives at once.
    state.newGenService = (llm) =>
        CharacterGenService(llm, retryDelay: (_) => Duration.zero);
    final card = CharacterCard(
      name: _name,
      description: _ProfileLlm.baseDesc,
      personality: _ProfileLlm.basePers,
      scenario: '{{user}} climbs the tower stairs at dusk.',
    );
    state.generatedCard = card;
    state.profile.paused = GenPausedRun(
      inputs: const GenRunInputs(name: _name, concept: 'A keeper.'),
      card: card,
      interviewTranscript: 'Q: Who are you?\nA: The keeper.',
    );
    state.descController.text = card.description;
    state.personalityController.text = card.personality;
    state.scenarioController.text = card.scenario;
    state.profile.steer.text = 'warmer';
    await tester.runAsync(() => state.rewriteProfile(llmProvider: provider));
    expect(llm.failures, greaterThan(1), reason: 'it retried, then gave up');
    expect(state.profile.error, startsWith('The rewrite failed'));
    expect(state.profile.error, contains('connection refused'));
    expect(state.profile.error, isNot(contains('the same as before')));
    expect(state.descController.text, _ProfileLlm.baseDesc);
  });

  group('workDaysText (the phone\'s twin)', () {
    test('collapses consecutive days into ranges', () {
      expect(workDaysText([1, 2, 3, 4, 5]), 'Mon–Fri');
      expect(workDaysText([6, 7]), 'Sat–Sun');
      expect(workDaysText([1, 2, 3, 4, 6]), 'Mon–Thu, Sat');
    });

    test('names a single day, every day, and the default', () {
      expect(workDaysText([3]), 'Wed');
      expect(workDaysText([7, 1, 2, 3, 4, 5, 6]), 'Every day');
      expect(workDaysText(null), 'Mon–Fri');
      expect(workDaysText([]), 'Mon–Fri');
    });
  });

  testWidgets('streamed text is coloured as the finished box will be', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StreamedText(
            text: '*{{char}} looks up.* "Late again."',
            style: TextStyle(fontSize: 15),
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(StreamedText));
    final colours = <String, Color?>{};
    tester.widget<RichText>(find.byType(RichText).first).text.visitChildren((
      span,
    ) {
      if (span is TextSpan && span.text != null) {
        colours[span.text!] = span.style?.color;
      }
      return true;
    });
    expect(colours['{{char}}'], StudioColors.tealOf(context));
    expect(colours['"Late again."'], StudioColors.honeyOf(context));
    expect(colours['*'], StudioColors.narrationOf(context));
  });
}
