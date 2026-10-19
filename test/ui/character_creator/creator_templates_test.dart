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

// Desktop creator templates (docs/design/creator-templates.md): the Mode
// step's picker and its order, Load into every box in every mode, the
// Configure header's mark, Save as template (prefill, replace caption,
// built-in refusal, the phone's keys kept), the ⋯ menu's Rename and
// Delete, the built-ins picker, Clear Everything, and a restart. The
// library is the real one on a temp folder; its file I/O runs in real time.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state/creator_template_form.dart';
import 'package:front_porch_ai/ui/character_creator/steps/steps.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/creator_test_support.dart';
import '../../helpers/double_tap.dart';
import '../../golden/support/fakes.dart';

const _persona = 'persona-sam';

class _Personas extends FakeUserPersonaService {
  @override
  List<UserPersona> get personas => [UserPersona(id: _persona, name: 'Sam')];
}

Set<String> get _desktopKeys => {
  for (final f in kTemplateFields)
    if (f.surface != TemplateSurface.phone) f.key,
};

/// Every key the schema holds, none at its default.
Map<String, Object?> _fullForm({String mode = 'guided'}) => {
  for (final f in kTemplateFields)
    f.key: switch (f.fallback) {
      _ when f.options != null => f.options!.lastWhere((o) => o != f.fallback),
      final bool b => !b,
      final int _ => 3,
      final List<String> _ => ['${f.key} one', '${f.key} two'],
      final String _ => '${f.key} text',
      _ => InterviewQuestion.listToJson([
        ...standardInterviewQuestions().skip(1),
        const InterviewQuestion(text: 'Who taught you to sail?'),
      ]),
    },
  'mode': mode,
  'greetingTones': ['Flirty', 'Dark'],
  'personaId': _persona,
  'loreUrls': ['https://a.example/wiki', 'https://b.example/wiki'],
};

Widget _stepFor(CreatorState s) => switch (s.currentStep) {
  1 => ModeSelectStep(state: s),
  _ => switch (s.creatorMode) {
    CreatorMode.quick => QuickConfigStep(state: s),
    CreatorMode.guided => GuidedConfigStep(state: s),
    CreatorMode.automated => AutomatedConfigStep(state: s),
  },
};

/// A temp library folder, removed after the test.
ChargenTemplateLibrary _tempLibrary() {
  final dir = Directory.systemTemp.createTempSync('fpai_templates_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return ChargenTemplateLibrary(dir.path);
}

/// Lets real file I/O finish, a frame at a time, until [done].
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'the file write never finished');
  await tester.pump(const Duration(milliseconds: 300));
}

/// The creator on the Mode step, rebuilt on every notify as the page does,
/// with [library] read once.
Future<CreatorState> _pumpCreator(
  WidgetTester tester, {
  ChargenTemplateLibrary? library,
  void Function(CreatorState s)? seed,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1280, 3400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = CreatorState()..currentStep = 1;
  addTearDown(state.dispose);
  seed?.call(state);
  final personas = _Personas();
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
  if (library != null) {
    state.templates.library = library;
    final before = state.templates.mine;
    state.templates.refresh();
    await _settle(tester, () => !identical(state.templates.mine, before));
  }
  return state;
}

Future<void> _save(
  WidgetTester tester,
  ChargenTemplateLibrary lib,
  String name,
  Map<String, Object?> form, {
  DateTime? at,
}) async {
  await tester.runAsync(() => lib.save(name, form, now: at));
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _tile(String slug) => find.byKey(ValueKey('template-tile-$slug'));

List<String> _tileNames(WidgetTester tester) => [
  for (final t in tester.widgetList<TemplateTile>(find.byType(TemplateTile)))
    t.template.name,
];

ButtonStyleButton _confirm(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('template-name-confirm')),
    );

String _caption(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('template-name-caption')))
    .data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  testWidgets('the Mode step lists yours newest first, then Tsundere and '
      'Kuudere, then All 15 built in', (tester) async {
    final lib = _tempLibrary();
    // Saved oldest last, so the order is the dates', not the writes'.
    await _save(
      tester,
      lib,
      'Harbor town, slow burn',
      _fullForm(),
      at: DateTime.utc(2026, 10, 4),
    );
    await _save(
      tester,
      lib,
      'Modern 18+ quick',
      _fullForm(mode: 'quick'),
      at: DateTime.utc(2026, 10, 9),
    );
    await _save(
      tester,
      lib,
      'Old sketch',
      _fullForm(),
      at: DateTime.utc(2026, 9, 1),
    );
    await _pumpCreator(tester, library: lib);

    expect(find.text('Start from a template'), findsOneWidget);
    expect(_tileNames(tester), [
      'Modern 18+ quick',
      'Harbor town, slow burn',
      'Old sketch',
      'Tsundere',
      'Kuudere',
    ]);
    expect(kBuiltInTemplates, hasLength(15));
    expect(find.text('All 15 built in'), findsOneWidget);
    // The last tile comes after every template tile.
    expect(
      tester.getTopLeft(find.byType(AllBuiltInsTile)).dy,
      greaterThanOrEqualTo(tester.getTopLeft(_tile('kuudere')).dy),
    );
    expect(
      // The full form turns the lorebook off, so no "lore on".
      find.text('Quick · 3rd person, past · 18+'),
      findsOneWidget,
    );
    expect(
      find.text('Automated · sharp-tongued, secretly caring'),
      findsOneWidget,
    );
  });

  testWidgets('with no library the built-ins show on the first frame', (
    tester,
  ) async {
    await _pumpCreator(tester);
    expect(_tileNames(tester), ['Tsundere', 'Kuudere']);
    expect(find.byType(AllBuiltInsTile), findsOneWidget);
  });

  testWidgets('Load fills every desktop key, sets the mode, leaves the name, '
      'drops the lore files and shows the mark', (tester) async {
    final lib = _tempLibrary();
    final form = _fullForm();
    await _save(tester, lib, 'Full kit', form);
    final state = await _pumpCreator(
      tester,
      library: lib,
      seed: (s) {
        s.nameController.text = 'Wren Ashby';
        s.loreFiles.add(
          MemoryPlatformFile(name: 'notes.txt', bytes: Uint8List(3)),
        );
      },
    );
    expect(
      creatorTemplateForm(state).keys.toSet(),
      _desktopKeys,
      reason: 'the desktop writes exactly its keys',
    );

    await _tap(tester, _tile('full-kit'));
    expect(state.creatorMode, CreatorMode.guided);
    expect(state.nameController.text, 'Wren Ashby');
    expect(state.loreFiles, isEmpty);
    expect(state.selectedPersonaId, _persona);
    // The one concept box reads Guided's (Automated's) concept and writes
    // both keys from it.
    expect(creatorTemplateForm(state), {
      for (final k in _desktopKeys) k: form[k],
      'quickConcept': form['automatedConcept'],
    });
    expect(state.quickSelectedTones, ['Flirty', 'Dark']);
    expect(state.quickGreetingCount, 3);
    expect(state.quickNsfwEnabled, isTrue);

    state.currentStep = 2;
    await tester.pump();
    expect(find.text('Started from: Full kit'), findsOneWidget);
    expect(
      find.text(
        'Changes stay on this form until you save them to the '
        'template.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Load sets each mode, its concept and the mark on its '
      'Configure step', (tester) async {
    final lib = _tempLibrary();
    for (final mode in ['automated', 'guided', 'quick']) {
      await _save(tester, lib, 'Kit $mode', _fullForm(mode: mode));
    }
    final state = await _pumpCreator(tester, library: lib);
    for (final mode in CreatorMode.values) {
      state.currentStep = 1;
      await tester.pump();
      await _tap(tester, _tile('kit-${mode.name}'));
      expect(state.creatorMode, mode);
      expect(
        state.conceptController.text,
        mode == CreatorMode.quick
            ? 'quickConcept text'
            : 'automatedConcept text',
      );
      expect(
        tester.widget<TemplateTile>(_tile('kit-${mode.name}')).selected,
        isTrue,
        reason: '$mode: the picked tile is outlined',
      );
      state.currentStep = 2;
      await tester.pump();
      expect(
        find.text('Started from: Kit ${mode.name}'),
        findsOneWidget,
        reason: '$mode',
      );
      expect(
        find.byKey(const ValueKey('template-started-caption')),
        findsOneWidget,
        reason: '$mode',
      );
      expect(
        find.byKey(const ValueKey('template-save-button')),
        findsOneWidget,
        reason: '$mode',
      );
    }
  });

  testWidgets('Load drops a persona this app does not have, so the persona '
      'picker still draws', (tester) async {
    final lib = _tempLibrary();
    await _save(tester, lib, 'Elsewhere', {
      ..._fullForm(mode: 'automated'),
      'personaId': 'persona-from-another-machine',
    });
    final state = await _pumpCreator(tester, library: lib);
    await _tap(tester, _tile('elsewhere'));
    expect(state.selectedPersonaId, isEmpty);
    state.currentStep = 2;
    await tester.pump();
    expect(find.byType(AutomatedConfigStep), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save as template prefills the name, warns before replacing, '
      'refuses a built-in name, and keeps the phone\'s keys', (tester) async {
    final lib = _tempLibrary();
    await _save(tester, lib, 'Phone pick', {
      'mode': 'quick',
      'quickConcept': 'A ferry pilot.',
      'quickScenario': 'Dawn crossing.',
      'quickKeywords': 'salt, rope',
      'worldLore': 'The harbor town of Vell.',
    });
    final state = await _pumpCreator(tester, library: lib);
    await _tap(tester, _tile('phone-pick'));
    state.currentStep = 2;
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller == state.quickScenarioController,
      ),
      'A storm crossing.',
    );

    await _tap(tester, find.byKey(const ValueKey('template-save-button')));
    expect(find.text('Save as a template'), findsOneWidget);
    // The warm dialog takes the creator's Dialog shape in here.
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    final inDialog = tester.element(find.byType(AlertDialog));
    expect(dialog.backgroundColor, StudioColors.cardOf(inDialog));
    expect(
      (dialog.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(20),
    );
    final card = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Material),
    );
    expect(tester.getSize(card.first).width, 520);
    final field = find.byKey(const ValueKey('template-name-field'));
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: field, matching: find.byType(TextField)),
          )
          .controller!
          .text,
      'Phone pick',
    );
    expect(_caption(tester), kTemplateReplacesCaption);
    expect(_confirm(tester).enabled, isTrue);

    await tester.enterText(field, 'tsundere');
    await tester.pump();
    expect(_caption(tester), templateNameProblem('Tsundere'));
    expect(_confirm(tester).enabled, isFalse);

    await tester.enterText(field, 'Ferry run');
    await tester.pump();
    expect(find.byKey(const ValueKey('template-name-caption')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('template-name-confirm')));
    await _settle(
      tester,
      () => state.templates.startedFrom?.name == 'Ferry run',
    );

    expect(find.text('Save as a template'), findsNothing);
    expect(find.text('Started from: Ferry run'), findsOneWidget);
    final saved = await tester.runAsync(() => lib.read('ferry-run'));
    expect(saved!.form['quickScenario'], 'A storm crossing.');
    expect(
      saved.form['quickKeywords'],
      'salt, rope',
      reason: 'a key only the phone shows survives a desktop save',
    );
    expect(saved.form['worldLore'], 'The harbor town of Vell.');
    expect(saved.form.containsKey('name'), isFalse);
    expect(saved.form['mode'], 'quick');
  });

  testWidgets('an empty name stays quiet until it is edited, then asks for '
      'a name with Save off', (tester) async {
    await _pumpCreator(
      tester,
      seed: (s) => s
        ..creatorMode = CreatorMode.quick
        ..currentStep = 2,
    );
    await _tap(tester, find.byKey(const ValueKey('template-save-button')));
    expect(find.byKey(const ValueKey('template-name-caption')), findsNothing);
    expect(_confirm(tester).enabled, isFalse);
    final field = find.byKey(const ValueKey('template-name-field'));
    await tester.enterText(field, 'x');
    await tester.pump();
    expect(_confirm(tester).enabled, isTrue);
    await tester.enterText(field, '');
    await tester.pump();
    expect(_caption(tester), templateNameProblem(''));
    expect(_confirm(tester).enabled, isFalse);
  });

  testWidgets('the ⋯ menu renames (the mark follows) and deletes after a '
      'confirm (the mark goes); a built-in has no menu', (tester) async {
    final lib = _tempLibrary();
    await _save(
      tester,
      lib,
      'Harbor town, slow burn',
      _fullForm(),
      at: DateTime.utc(2026, 10, 4),
    );
    await _save(
      tester,
      lib,
      'Other',
      _fullForm(),
      at: DateTime.utc(2026, 9, 4),
    );
    final state = await _pumpCreator(tester, library: lib);
    expect(find.byKey(const ValueKey('template-menu-tsundere')), findsNothing);
    expect(find.byType(BuiltInPill), findsNWidgets(2));
    await _tap(tester, _tile('harbor-town-slow-burn'));

    await _tap(
      tester,
      find.byKey(const ValueKey('template-menu-harbor-town-slow-burn')),
    );
    expect(find.text('Load'), findsOneWidget);
    await _tap(tester, find.text('Rename'));
    final field = find.byKey(const ValueKey('template-name-field'));
    await tester.enterText(field, 'Other');
    await tester.pump();
    expect(_caption(tester), kTemplateTakenProblem);
    expect(_confirm(tester).enabled, isFalse);
    await tester.enterText(field, 'Harbor town, fast burn');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('template-name-confirm')));
    await _settle(
      tester,
      () => state.templates.mine.any((t) => t.name == 'Harbor town, fast burn'),
    );
    expect(_tileNames(tester).first, 'Harbor town, fast burn');
    expect(state.templates.startedFrom?.name, 'Harbor town, fast burn');
    expect(
      await tester.runAsync(() => lib.read('harbor-town-slow-burn')),
      isNull,
    );

    await _tap(
      tester,
      find.byKey(const ValueKey('template-menu-harbor-town-fast-burn')),
    );
    await _tap(tester, find.text('Delete'));
    expect(find.text('Delete this template?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Harbor town, fast burn'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('template-delete-confirm')));
    await _settle(tester, () => state.templates.mine.length == 1);
    expect(_tileNames(tester), ['Other', 'Tsundere', 'Kuudere']);
    expect(state.templates.startedFrom, isNull);
    expect(
      await tester.runAsync(() => lib.read('harbor-town-fast-burn')),
      isNull,
    );
    expect(
      state.guidedVisionController.text,
      'guidedVision text',
      reason: 'the boxes stay as they were',
    );
  });

  testWidgets('All 15 built in opens the picker; Yandere loads without '
      'naming the character', (tester) async {
    final state = await _pumpCreator(tester);
    await _tap(tester, find.byType(AllBuiltInsTile));
    expect(find.text('Built-in templates'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TemplateTile),
      ),
      findsNWidgets(15),
    );
    await _tap(tester, _tile('yandere'));
    expect(find.text('Built-in templates'), findsNothing);
    final yandere = kArchetypePresets['Yandere']!;
    expect(state.creatorMode, CreatorMode.automated);
    expect(state.selectedArchetype, 'Yandere');
    expect(state.conceptController.text, yandere['concept']);
    expect(state.keywordsController.text, yandere['keywords']);
    expect(state.nameController.text, isEmpty);
    expect(state.templates.startedFrom?.builtIn, isTrue);
    state.currentStep = 2;
    await tester.pump();
    expect(find.text('Started from: Yandere'), findsOneWidget);
  });

  testWidgets('Clear Everything resets every template field and the mark', (
    tester,
  ) async {
    final state = await _pumpCreator(tester);
    state.templates.load(
      state,
      CreatorTemplate(slug: 'full-kit', name: 'Full kit', form: _fullForm()),
      personaIds: [_persona],
    );
    state.currentStep = 2;
    await tester.pump();
    expect(find.text('Started from: Full kit'), findsOneWidget);

    state.resetAllFields();
    state.currentStep = 2;
    await tester.pump();
    final defaults = templateDefaults();
    expect(creatorTemplateForm(state), {
      for (final k in _desktopKeys) k: defaults[k],
    });
    expect(state.quickSelectedTones, ['Neutral']);
    expect(state.quickGreetingCount, 0);
    expect(state.quickNsfwEnabled, isFalse);
    expect(state.templates.startedFrom, isNull);
    expect(find.byKey(const ValueKey('template-started-pill')), findsNothing);
  });

  test(
    'a restart keeps every template field, Quick\'s own and the mark',
    () async {
      SharedPreferences.setMockInitialValues({});
      final a = CreatorState();
      addTearDown(a.dispose);
      a.templates.load(
        a,
        CreatorTemplate(slug: 'full-kit', name: 'Full kit', form: _fullForm()),
        personaIds: [_persona],
      );
      // Quick's own differ from the shared ones, so each pair is pinned.
      a.quickSelectedTones = ['Wholesome'];
      a.quickGreetingCount = 1;
      a.quickNsfwEnabled = false;
      await a.saveState();

      final b = CreatorState();
      addTearDown(b.dispose);
      await b.loadSavedState();
      expect(creatorTemplateForm(b), creatorTemplateForm(a));
      expect(b.quickSelectedTones, ['Wholesome']);
      expect(b.quickGreetingCount, 1);
      expect(b.quickNsfwEnabled, isFalse);
      expect(b.templates.startedFrom?.slug, 'full-kit');
      expect(b.templates.startedFrom?.name, 'Full kit');

      // Save & Finish clears the mark with the name.
      await b.clearSavedFormPrefsAfterSave();
      final c = CreatorState();
      addTearDown(c.dispose);
      await c.loadSavedState();
      expect(c.templates.startedFrom, isNull);
    },
  );

  testWidgets('a double click on Save writes the template once', (
    tester,
  ) async {
    final gate = Completer<void>();
    final written = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreatorTheme(
            child: TemplateNameDialog(
              title: 'Save as template',
              confirmLabel: 'Save',
              initialName: 'Porch Cat',
              check: (_) => (problem: null, replaces: false),
              submit: (name) {
                written.add(name);
                return gate.future;
              },
              failure: 'Could not save.',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await doubleTapNoFrame(
      tester,
      find.byKey(const ValueKey('template-name-confirm')),
    );
    await tester.pump();
    expect(written, ['Porch Cat']);
  });
}
