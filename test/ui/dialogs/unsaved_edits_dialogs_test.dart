// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The editor dialogs used to vanish on Escape, a stray click outside or
// Cancel, taking whatever was typed with them. Each one now asks first when
// something changed, and still closes quietly when nothing did.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart' as db;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/growth_panel.editor.dart';
import 'package:front_porch_ai/ui/dialogs/data_bank_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/journal_card_editor.dart';
import 'package:front_porch_ai/ui/dialogs/lorebook_entry/lorebook_entry_fields.dart';
import 'package:front_porch_ai/ui/dialogs/lorebook_entry_dialog.dart';
import 'package:front_porch_ai/ui/pages/worlds/climate_editor_dialog.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';

const _question = 'Discard unsaved changes?';

/// The climate editor's header X: the first close button in the dialog (the
/// skin rows below it carry their own).
final _climateClose = find
    .byWidgetPredicate(
      (w) =>
          w is IconButton &&
          w.icon is Icon &&
          (w.icon as Icon).icon == Icons.close,
    )
    .first;

/// Opens [open] from a button and records whether it has returned.
Future<_Opened> _open(
  WidgetTester tester,
  Future<Object?> Function(BuildContext) open, {
  Size window = const Size(1400, 900),
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final opened = _Opened();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                opened.result = await open(context);
                opened.closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return opened;
}

class _Opened {
  bool closed = false;
  Object? result;
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

Future<void> _keepEditing(WidgetTester tester) async {
  expect(find.text(_question), findsOneWidget);
  await tester.tap(find.text('Keep editing'));
  await tester.pumpAndSettle();
}

Future<void> _discard(WidgetTester tester) async {
  expect(find.text(_question), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('unsaved-discard')));
  await tester.pumpAndSettle();
}

void main() {
  group('lorebook entry', () {
    Future<_Opened> openEntry(WidgetTester tester, [LorebookEntry? e]) => _open(
      tester,
      (ctx) => showLorebookEntryDialog(context: ctx, existing: e),
    );

    testWidgets('Escape with nothing changed closes without asking', (
      tester,
    ) async {
      final opened = await openEntry(
        tester,
        LorebookEntry(key: 'harbor', content: 'Fog rolls in.'),
      );
      await _escape(tester);
      expect(find.text(_question), findsNothing);
      expect(opened.closed, isTrue);
    });

    testWidgets('an imported entry with stray whitespace is not an edit', (
      tester,
    ) async {
      final opened = await openEntry(
        tester,
        LorebookEntry(
          name: ' Harbor ',
          keys: const ['harbor ', ' docks'],
          content: 'Fog rolls in.\n\n',
        ),
      );
      await _escape(tester);
      expect(find.text(_question), findsNothing);
      expect(opened.closed, isTrue);
    });

    testWidgets('typed content survives Escape until the user discards', (
      tester,
    ) async {
      final opened = await openEntry(tester);
      await tester.enterText(find.byType(TextField).last, 'Hours of lore');
      await _escape(tester);
      await _keepEditing(tester);
      expect(opened.closed, isFalse);
      expect(find.text('Hours of lore'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await _discard(tester);
      expect(opened.closed, isTrue);
      expect(opened.result, isNull);
    });

    testWidgets('an Advanced-only change counts as unsaved', (tester) async {
      final opened = await openEntry(
        tester,
        LorebookEntry(keys: const ['queen'], content: 'Original'),
      );
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      final prioritize = find.descendant(
        of: find.widgetWithText(LoreToggle, 'Prioritize in group'),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(prioritize);
      await tester.tap(prioritize);
      await tester.pumpAndSettle();
      await _escape(tester);
      await _keepEditing(tester);
      expect(opened.closed, isFalse);
    });

    testWidgets('Save still returns the entry without asking', (tester) async {
      final opened = await openEntry(tester);
      await tester.enterText(find.byType(TextField).last, 'Kept lore');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text(_question), findsNothing);
      expect((opened.result as LorebookEntry?)?.content, 'Kept lore');
    });
  });

  testWidgets('journal card: a click outside a typed memory asks', (
    tester,
  ) async {
    final opened = await _open(
      tester,
      (ctx) => JournalCardEditorDialog.show(
        ctx,
        title: 'Plant a memory',
        userName: 'You',
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'We met at the fair');
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await _keepEditing(tester);
    expect(find.text('We met at the fair'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await _discard(tester);
    expect(opened.closed, isTrue);
  });

  testWidgets('story dialog: typed form text asks before Escape drops it', (
    tester,
  ) async {
    final name = TextEditingController(text: 'Ada');
    addTearDown(name.dispose);
    final opened = await _open(
      tester,
      (ctx) => showStoryDialog<bool>(
        ctx,
        title: 'Edit Ada',
        isDirty: storyTextChanged([name]),
        body: StoryField(controller: name, hint: 'Name'),
        actions: (c) => [
          StoryButton.ghost(
            'Cancel',
            onPressed: () => Navigator.maybePop(c, false),
          ),
        ],
      ),
    );
    await _escape(tester);
    expect(opened.closed, isTrue, reason: 'unchanged closes quietly');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    opened.closed = false;
    await tester.enterText(find.byType(TextField), 'Ada Lovelace');
    await _escape(tester);
    await _keepEditing(tester);
    expect(opened.closed, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _discard(tester);
    expect(opened.closed, isTrue);
    expect(opened.result, isFalse);
  });

  testWidgets('climate editor: a renamed season asks before the close X', (
    tester,
  ) async {
    final opened = await _open(
      tester,
      (ctx) => showClimateEditorDialog(
        ctx,
        worldName: 'Harbor',
        existingBiomeJson: null,
        fahrenheit: false,
      ),
    );
    await tester.tap(_climateClose);
    await tester.pumpAndSettle();
    expect(find.text(_question), findsNothing);
    expect(opened.closed, isTrue);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    opened.closed = false;
    await tester.enterText(find.byType(TextField).first, 'Monsoon');
    await tester.pump();
    await tester.tap(_climateClose);
    await tester.pumpAndSettle();
    await _keepEditing(tester);
    expect(opened.closed, isFalse);

    await tester.tap(find.text('Save climate'));
    await tester.pumpAndSettle();
    expect(find.text(_question), findsNothing);
    expect(jsonDecode(opened.result! as String), isA<Map<String, dynamic>>());
  });

  testWidgets('climate editor: a weather renamed before its danger level '
      'still asks', (tester) async {
    final opened = await _open(
      tester,
      (ctx) => showClimateEditorDialog(
        ctx,
        worldName: 'Harbor',
        existingBiomeJson: null,
        fahrenheit: false,
      ),
    );
    final rename = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == 'rename (e.g. Dust Squall)',
    );
    // The form is a lazy list: scroll the left column down to the renames.
    await tester.drag(find.byType(ListView).first, const Offset(0, -2500));
    await tester.pumpAndSettle();
    await tester.enterText(rename.first, 'Dust Squall');
    await tester.pump();
    await tester.tap(_climateClose);
    await tester.pumpAndSettle();
    await _keepEditing(tester);
    expect(opened.closed, isFalse);
    expect(find.text('Dust Squall'), findsOneWidget);
  });

  testWidgets('data bank: a typed entry asks before Cancel or the X drop it', (
    tester,
  ) async {
    // Never closed: drift's close wall-hangs under testWidgets.
    final database = db.AppDatabase.forTesting(sameIsolate: true);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var closed = false;
    await tester.pumpWidget(
      Provider<db.AppDatabase>.value(
        value: database,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => const DataBankDialog(
                      characterId: 'Ada_1',
                      characterName: 'Ada',
                    ),
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The entry list loads from the database before the toolbar settles.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text(_question), findsNothing, reason: 'empty form is quiet');
    expect(find.text('New Entry'), findsNothing);

    await tester.tap(find.text('Add Entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Hours of notes');
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _keepEditing(tester);
    expect(find.text('Hours of notes'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await _keepEditing(tester);
    expect(closed, isFalse);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await _discard(tester);
    expect(closed, isTrue);
  });

  testWidgets('growth ring: a changed sentence or category asks first', (
    tester,
  ) async {
    final opened = await _open(
      tester,
      (ctx) => GrowthRingEditorDialog.show(
        ctx,
        title: 'Edit ring',
        initialContent: 'Guards their sleep.',
      ),
    );
    await _escape(tester);
    expect(find.text(_question), findsNothing);
    expect(opened.closed, isTrue, reason: 'unchanged closes quietly');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    opened.closed = false;
    await tester.tap(find.text('habit'));
    await tester.pumpAndSettle();
    await _escape(tester);
    await _keepEditing(tester);
    expect(opened.closed, isFalse);

    await tester.enterText(find.byType(TextField), 'Reads to them at night.');
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _discard(tester);
    expect(opened.closed, isTrue);
    expect(opened.result, isNull);
  });
}
