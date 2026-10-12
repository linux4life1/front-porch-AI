// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Leaving a page with unsaved edits used to throw them away without a word
// (hours of a character card, gone). Every way out of a guarded page now
// asks first: back, a dialog's barrier, the sidebar, the window close.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes.dart';

const _question = 'Discard unsaved changes?';

/// A pushed editor page whose only dirt is its text field.
class _EditorPage extends StatefulWidget {
  const _EditorPage();

  @override
  State<_EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<_EditorPage> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    isDirty: () => _text.text.isNotEmpty,
    child: Scaffold(
      appBar: AppBar(title: const Text('Editor')),
      body: Column(
        children: [
          TextField(controller: _text),
          TextButton(
            // Save writes, then leaves past the guard.
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _EditorPage()),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  expect(find.text('Editor'), findsOneWidget);
}

void main() {
  testWidgets('back from a clean page leaves without asking', (tester) async {
    await _openEditor(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(_question), findsNothing);
    expect(find.text('Editor'), findsNothing);
  });

  testWidgets('back from a page with typed edits asks; Keep editing stays, '
      'Discard leaves', (tester) async {
    await _openEditor(tester);
    await tester.enterText(find.byType(TextField), 'Hours of backstory');
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(_question), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Hours of backstory'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unsaved-discard')));
    await tester.pumpAndSettle();
    expect(find.text('Editor'), findsNothing);
  });

  testWidgets('Save leaves a dirty page without asking', (tester) async {
    await _openEditor(tester);
    await tester.enterText(find.byType(TextField), 'kept');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text(_question), findsNothing);
    expect(find.text('Editor'), findsNothing);
  });

  testWidgets('a barrier tap on a dirty dialog asks instead of closing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => UnsavedChangesGuard(
                  isDirty: () => true,
                  child: const AlertDialog(content: Text('Lore entry')),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text(_question), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Lore entry'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unsaved-discard')));
    await tester.pumpAndSettle();
    expect(find.text('Lore entry'), findsNothing);
  });

  testWidgets('the sidebar keeps a dirty tab page unless the user discards', (
    tester,
  ) async {
    final appState = AppState()..setIndex(1);
    var dirty = true;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<UpdateService>.value(
            value: FakeUpdateService(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                const Sidebar(),
                Expanded(
                  child: UnsavedChangesGuard(
                    isDirty: () => dirty,
                    child: const Text('Create Character form'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Worlds'));
    await tester.pumpAndSettle();
    expect(find.text(_question), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(appState.selectedIndex, 1);

    await tester.tap(find.text('Worlds'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unsaved-discard')));
    await tester.pumpAndSettle();
    expect(appState.selectedIndex, 5);

    dirty = false;
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text(_question), findsNothing);
    expect(appState.selectedIndex, 0);
  });

  testWidgets('the window close asks only when something is unsaved', (
    tester,
  ) async {
    var dirty = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnsavedChangesGuard(
            isDirty: () => dirty,
            child: const Text('form'),
          ),
        ),
      ),
    );
    expect(await UnsavedChanges.instance.confirmLeave(), isTrue);

    dirty = true;
    final answer = UnsavedChanges.instance.confirmLeave();
    await tester.pumpAndSettle();
    expect(find.text(_question), findsOneWidget);
    // A second close click while asking does not stack another dialog.
    expect(await UnsavedChanges.instance.confirmLeave(), isFalse);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });
}
