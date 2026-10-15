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

// The desktop Interview card (docs/design/creator-interview-questions.md):
// where it sits in every mode, its rows and pills, edits that survive a
// voice change, the voice and Sex it follows, remove / add to the cap /
// reset, reorder by the handle, the saved list, the list each mode's
// Generate hands the run, and the Profile step without a transcript.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/steps/steps.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';
import '../../services/chargen/support/marker_chargen_llm.dart';

const _countTail =
    ' of 12 · remove them all and the profile comes straight from your '
    'settings, no interview';

Widget _stepFor(CreatorState s) => switch (s.creatorMode) {
  CreatorMode.quick => QuickConfigStep(state: s),
  CreatorMode.guided => GuidedConfigStep(state: s),
  CreatorMode.automated => AutomatedConfigStep(state: s),
};

/// The mode's Configure step, rebuilt on every notify as the wizard does.
Future<CreatorState> _pumpConfig(
  WidgetTester tester,
  CreatorMode mode, {
  void Function(CreatorState state)? seed,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1280, 3400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = CreatorState()..creatorMode = mode;
  addTearDown(state.dispose);
  seed?.call(state);
  final personas = FakeUserPersonaService();
  addTearDown(personas.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserPersonaService>.value(
      value: personas,
      child: MaterialApp(
        home: Scaffold(
          body: CreatorTheme(
            child: ListenableBuilder(
              listenable: state,
              builder: (_, _) => _stepFor(state),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return state;
}

Finder _row(int i) => find.byType(InterviewQuestionRow).at(i);

Finder _box(int i) =>
    find.descendant(of: _row(i), matching: find.byType(TextField));

String _text(int i, WidgetTester tester) =>
    tester.widget<TextField>(_box(i)).controller!.text;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await tester.pump();
}

/// Types into row [i] and lets the half-second typing save run.
Future<void> _type(WidgetTester tester, int i, String text) async {
  await tester.ensureVisible(_box(i));
  await tester.enterText(_box(i), text);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

String _json(List<InterviewQuestion>? qs) =>
    qs == null ? 'null' : jsonEncode(InterviewQuestion.listToJson(qs));

/// Records the inputs each run is handed, then runs it for real.
class _RecordingGen extends CharacterGenService {
  _RecordingGen(super.llm, this.seen) : super(retryDelay: (_) => Duration.zero);

  final List<GenRunInputs> seen;

  @override
  Future<GenPausedRun?> generateProfile({
    required GenRunInputs inputs,
    bool abortInFlight = true,
    void Function(String accumulated)? onProgress,
    void Function(String error)? onError,
    void Function(String status)? onStatus,
  }) {
    seen.add(inputs);
    return super.generateProfile(
      inputs: inputs,
      abortInFlight: abortInFlight,
      onProgress: onProgress,
      onError: onError,
      onStatus: onStatus,
    );
  }
}

/// A provider whose active service is the scripted model, the shape the
/// creator mode tests use.
class _Provider extends LLMProvider {
  _Provider(this._svc, StorageService s)
    : super(KoboldService(s), OpenRouterService(), s, BackendManager(s));

  final LLMService _svc;

  @override
  LLMService get activeService => _svc;
  @override
  BackendType get activeBackend => BackendType.kobold;
  @override
  bool get hasManagedProcess => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  testWidgets('the card sits directly after the card that holds the voice '
      'selector, in Quick, Guided and Automated', (tester) async {
    for (final mode in CreatorMode.values) {
      await _pumpConfig(tester, mode);
      if (mode == CreatorMode.guided) {
        // Guided's Output Settings card starts collapsed.
        await _tap(tester, find.text('Output Settings'));
      }
      final card = find.byType(InterviewQuestionsCard);
      expect(card, findsOneWidget, reason: '$mode');
      final column = tester.widget<Column>(
        find.ancestor(of: card, matching: find.byType(Column)).first,
      );
      final i = column.children.indexWhere((w) => w is InterviewQuestionsCard);
      expect(i, greaterThan(0), reason: '$mode');
      expect(
        find.ancestor(
          of: find.byType(NarrativeVoiceSelector),
          matching: find.byWidget(column.children[i - 1]),
        ),
        findsOneWidget,
        reason: '$mode: the widget right before the card holds the selector',
      );
    }
  });

  testWidgets('eleven rows, the two conditional pills, and no × on those', (
    tester,
  ) async {
    final state = await _pumpConfig(tester, CreatorMode.quick);
    expect(find.byType(InterviewQuestionRow), findsNWidgets(11));
    expect(find.text('Asked only when a relationship is set'), findsOneWidget);
    expect(find.text('Asked only when 18+ is on'), findsOneWidget);
    expect(find.text('Edited · kept as written'), findsNothing);
    for (var i = 0; i < 11; i++) {
      final conditional = state.interview.rows[i].q.isConditional;
      expect(
        find.descendant(of: _row(i), matching: find.byIcon(Icons.close)),
        conditional ? findsNothing : findsOneWidget,
        reason: 'row ${i + 1}',
      );
    }
    expect(find.text('11$_countTail'), findsOneWidget);
    expect(find.text('Answered in first person, present'), findsOneWidget);
    expect(find.text('Follows Narrative voice above.'), findsOneWidget);
  });

  testWidgets('typing marks a row edited, and a voice change re-renders '
      'only the unedited standard rows', (tester) async {
    final state = await _pumpConfig(tester, CreatorMode.quick);
    expect(_text(0, tester), startsWith('How do you talk?'));
    await _type(tester, 6, 'She snaps first and is kind after.');
    expect(find.text('Edited · kept as written'), findsOneWidget);
    expect(state.interview.rows[6].q.isEdited, isTrue);
    // A voice change must leave an edited box alone, caret included (a
    // re-render would put the caret nowhere while the box keeps focus).
    final edited = state.interview.rows[6].c;
    edited.selection = const TextSelection.collapsed(offset: 3);

    await _tap(tester, find.text('Third person'));
    expect(edited.selection, const TextSelection.collapsed(offset: 3));
    expect(find.text('Answered in third person, present'), findsOneWidget);
    expect(_text(0, tester), startsWith('How does {{char}} talk?'));
    expect(_text(1, tester), startsWith('What do they want today'));
    expect(_text(6, tester), 'She snaps first and is kind after.');

    await _tap(tester, find.text('Past'));
    expect(find.text('Answered in third person, past'), findsOneWidget);
    expect(
      find.text(
        'Follows Narrative voice above. Their own words are quoted when they '
        'speak.',
      ),
      findsOneWidget,
    );
    expect(_text(6, tester), 'She snaps first and is kind after.');
  });

  testWidgets('typing Sex in Quick re-renders the third-person pronouns', (
    tester,
  ) async {
    await _pumpConfig(
      tester,
      CreatorMode.quick,
      seed: (s) => s.narrativePerspective = 'third',
    );
    expect(_text(1, tester), startsWith('What do they want today'));
    final sex = find.widgetWithText(TextField, 'e.g. Female, Male, they/them');
    await tester.ensureVisible(sex);
    await tester.enterText(sex, 'female');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(_text(1, tester), startsWith('What does she want today'));
    expect(
      find.text(
        'Follows Narrative voice above. Her own words are quoted when she '
        'speaks.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('remove, add up to twelve, then Reset brings back the eleven', (
    tester,
  ) async {
    final state = await _pumpConfig(tester, CreatorMode.quick);
    await _tap(
      tester,
      find.descendant(of: _row(0), matching: find.byType(IconButton)),
    );
    expect(find.byType(InterviewQuestionRow), findsNWidgets(10));
    expect(state.interview.rows.first.q.key, 'wants');
    expect(find.text('10$_countTail'), findsOneWidget);

    final add = find.byKey(const ValueKey('interview-add'));
    await _tap(tester, add);
    await _tap(tester, add);
    expect(find.byType(InterviewQuestionRow), findsNWidgets(12));
    expect(find.text('12$_countTail'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(add).enabled, isFalse);
    await _type(tester, 11, 'Who taught you to sail?');
    expect(state.interview.forRun!.last.text, 'Who taught you to sail?');

    await _tap(tester, find.byKey(const ValueKey('interview-reset')));
    expect(find.byType(InterviewQuestionRow), findsNWidgets(11));
    expect(state.interview.isStandard, isTrue);
    expect(state.interview.forRun, isNull);
    expect(tester.widget<ButtonStyleButton>(add).enabled, isTrue);
  });

  testWidgets('dragging a row by its handle reorders the questions', (
    tester,
  ) async {
    final state = await _pumpConfig(tester, CreatorMode.quick);
    final handle = find.descendant(
      of: _row(0),
      matching: find.byType(ReorderableDragStartListener),
    );
    await tester.ensureVisible(_row(3));
    await tester.pumpAndSettle();
    final below = tester.getCenter(_row(2)).dy - tester.getCenter(_row(0)).dy;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, (below + 12) / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final keys = [for (final r in state.interview.rows) r.q.key];
    expect(keys.take(3), ['wants', 'wound', 'voice']);
    expect(state.interview.forRun, isNotNull);
    expect(_text(2, tester), startsWith('How do you talk?'));
  });

  testWidgets('a focused handle moves its row with ArrowDown and ArrowUp', (
    tester,
  ) async {
    final state = await _pumpConfig(tester, CreatorMode.quick);
    final handle = find.descendant(
      of: _row(1),
      matching: find.byWidgetPredicate(
        (w) => w is Focus && w.onKeyEvent != null,
      ),
    );
    tester.widget<Focus>(handle).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    List<String?> keys() => [for (final r in state.interview.rows) r.q.key];
    expect(keys().take(4), ['voice', 'wound', 'relationship', 'wants']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(keys().take(4), ['voice', 'wound', 'wants', 'relationship']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(keys().first, 'wants', reason: 'stops at the top');
  });

  test('the list survives a restart; Reset and Clear Everything store the '
      'standard set as an empty value', () async {
    SharedPreferences.setMockInitialValues({});
    const key = 'chargen_interview_questions';
    final a = CreatorState();
    addTearDown(a.dispose);
    a.interview.edit(1, 'What does {{char}} want for breakfast?');
    expect(a.interview.remove(0), isTrue);
    expect(a.interview.remove(2), isFalse, reason: 'relationship row');
    a.interview.add();
    a.interview.edit(a.interview.rows.length - 1, 'Who taught you to sail?');
    await a.saveState();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), isNotEmpty);

    final b = CreatorState();
    addTearDown(b.dispose);
    await b.loadSavedState();
    expect(_json(b.interview.forRun), _json(a.interview.forRun));
    expect(
      b.interview.rows.first.c.text,
      'What does {{char}} want for '
      'breakfast?',
    );
    expect(b.interview.rows.last.c.text, 'Who taught you to sail?');

    a.interview.reset();
    await a.saveState();
    expect(prefs.getString(key), '');

    a.interview.add();
    await a.saveState();
    expect(prefs.getString(key), isNotEmpty);
    a.resetAllFields();
    await a.saveState();
    expect(prefs.getString(key), '');

    SharedPreferences.setMockInitialValues({key: '{not json'});
    final c = CreatorState();
    addTearDown(c.dispose);
    await c.loadSavedState();
    expect(c.interview.isStandard, isTrue);
  });

  test('Generate in every mode hands the edited list to the run, and the '
      'edited question reaches the model', () async {
    final storage = await makeGoldenStorage();
    final personas = FakeUserPersonaService();
    for (final mode in CreatorMode.values) {
      final llm = MarkerChargenLlm();
      final provider = _Provider(llm, storage);
      addTearDown(provider.dispose);
      final seen = <GenRunInputs>[];
      final state = CreatorState()
        ..creatorMode = mode
        ..newGenService = (l) => _RecordingGen(l, seen);
      addTearDown(state.dispose);
      state.nameController.text = 'Wren Ashby';
      state.interview.edit(1, 'What is in the left coat pocket, and why?');
      await state.generateFromMode(
        llmProvider: provider,
        storage: storage,
        personaService: personas,
      );
      expect(seen, hasLength(1), reason: '$mode');
      expect(
        _json(seen.single.interviewQuestions),
        _json(state.interview.forRun),
        reason: '$mode: the run is given the card\'s list',
      );
      expect(
        llm.prompts.any((p) => p.contains('in the left coat pocket, and why')),
        isTrue,
        reason: '$mode: the edited question was asked',
      );
    }

    final seen = <GenRunInputs>[];
    final untouched = CreatorState()
      ..creatorMode = CreatorMode.quick
      ..newGenService = (l) => _RecordingGen(l, seen);
    addTearDown(untouched.dispose);
    final provider = _Provider(MarkerChargenLlm(), storage);
    addTearDown(provider.dispose);
    await untouched.generateFromMode(
      llmProvider: provider,
      storage: storage,
      personaService: personas,
    );
    expect(seen.single.interviewQuestions, isNull, reason: 'standard set');
  });

  testWidgets('the Profile step shows no transcript row when nothing was '
      'asked', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final transcript in ['', 'Q: Who are you?\nA: The keeper.']) {
      final state = CreatorState();
      addTearDown(state.dispose);
      final card = CharacterCard(name: 'Aria Vale', description: 'A keeper.');
      state.generatedCard = card;
      state.profile.paused = GenPausedRun(
        inputs: const GenRunInputs(name: 'Aria Vale', concept: 'A keeper.'),
        card: card,
        interviewTranscript: transcript,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CreatorTheme(child: ProfileStep(state: state)),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('profile-transcript')),
        transcript.isEmpty ? findsNothing : findsOneWidget,
        reason: transcript.isEmpty ? 'no interview' : 'one question',
      );
    }
  });

  group('CreatorInterview', () {
    test('a box typed back to the standard words stays edited', () {
      final iv = CreatorInterview();
      addTearDown(iv.dispose);
      final standard = iv.rows[4].c.text;
      iv.edit(4, 'something else');
      iv.edit(4, standard);
      expect(iv.rows[4].q.isEdited, isTrue);
      expect(iv.isStandard, isFalse);
      expect(iv.toPrefs(), isNotEmpty);
    });

    test('the same voice twice changes nothing; a new one re-renders', () {
      final iv = CreatorInterview();
      addTearDown(iv.dispose);
      const third = NarrativeVoice(perspective: NarrativePerspective.third);
      iv.applyVoice(third, NarrativePronouns.he);
      expect(iv.rows[1].c.text, startsWith('What does he want today'));
      iv.rows[1].c.text = 'left on screen';
      iv.applyVoice(third, NarrativePronouns.he);
      expect(iv.rows[1].c.text, 'left on screen', reason: 'no-op call');
      iv.applyVoice(third, NarrativePronouns.she);
      expect(iv.rows[1].c.text, startsWith('What does she want today'));
    });

    test('a saved empty list stays empty; Reset restores the standard set', () {
      final iv = CreatorInterview();
      addTearDown(iv.dispose);
      iv.restore('[]');
      expect(iv.rows, isEmpty);
      expect(iv.forRun, isEmpty);
      expect(iv.toPrefs(), '[]');
      iv.reset();
      expect(iv.isStandard, isTrue);
      expect(iv.toPrefs(), '');
    });

    test('move lands the row at the index it is dropped at', () {
      final iv = CreatorInterview();
      addTearDown(iv.dispose);
      iv.move(0, 2);
      expect(
        [for (final r in iv.rows.take(3)) r.q.key],
        ['wants', 'wound', 'voice'],
      );
      iv.move(2, 0);
      expect(iv.isStandard, isTrue);
    });
  });
}
