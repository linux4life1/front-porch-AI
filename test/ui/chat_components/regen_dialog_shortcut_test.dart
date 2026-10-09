// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Regenerate dialog confirms from the keyboard: Ctrl+Enter (⌘+Enter on
// macOS), on either Enter key, regenerates with the note and lookup as set.
// Plain Enter, main or numpad, is left to the note field for a new line.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/widgets/regen_critique_field.dart';

const _field = Key('regen-critique-field');

class _Seen {
  String? critique;
  String? webQuery;
  int regens = 0;
  int lookups = 0;
}

Future<_Seen> _open(WidgetTester tester, {bool web = false}) async {
  final seen = _Seen();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => promptRegenCritiqueThen(
              context,
              (c) {
                seen.regens++;
                seen.critique = c;
              },
              webEnabled: web,
              onLookup: (c, {String? webQuery, String? wikiQuery}) {
                seen.lookups++;
                seen.critique = c;
                seen.webQuery = webQuery;
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return seen;
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey enter,
) async {
  await tester.sendKeyDownEvent(modifier);
  await _press(tester, enter);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

// The test key simulator has no Windows code for Numpad Enter; the Linux
// encoding delivers the same logical key, which is all the dialog reads.
Future<bool> _press(WidgetTester tester, LogicalKeyboardKey key) =>
    tester.sendKeyEvent(
      key,
      platform:
          defaultTargetPlatform == TargetPlatform.windows &&
              key == LogicalKeyboardKey.numpadEnter
          ? 'linux'
          : null,
    );

LogicalKeyboardKey get _platformModifier =>
    defaultTargetPlatform == TargetPlatform.macOS
    ? LogicalKeyboardKey.metaLeft
    : LogicalKeyboardKey.controlLeft;

LogicalKeyboardKey get _otherModifier =>
    defaultTargetPlatform == TargetPlatform.macOS
    ? LogicalKeyboardKey.controlLeft
    : LogicalKeyboardKey.metaLeft;

final _platforms = TargetPlatformVariant(const {
  TargetPlatform.linux,
  TargetPlatform.windows,
  TargetPlatform.macOS,
});

void main() {
  for (final enter in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]) {
    testWidgets('the chord with ${enter.keyLabel} regenerates with the note', (
      tester,
    ) async {
      final seen = await _open(tester);
      await tester.enterText(find.byKey(_field), 'less lecture');
      await _chord(tester, _platformModifier, enter);
      expect(seen.regens, 1);
      expect(seen.critique, 'less lecture');
      expect(find.byKey(_field), findsNothing);
    }, variant: _platforms);

    testWidgets('plain ${enter.keyLabel} is left to the note field', (
      tester,
    ) async {
      final seen = await _open(tester);
      await tester.enterText(find.byKey(_field), 'first line');
      final handled = await _press(tester, enter);
      await tester.pumpAndSettle();
      // Unhandled means the key reaches the platform text input, which is
      // what puts the new line into a multi-line field.
      expect(handled, isFalse);
      expect(seen.regens, 0);
      expect(find.byKey(_field), findsOneWidget);
    }, variant: _platforms);
  }

  testWidgets('the other platform\'s modifier does not regenerate', (
    tester,
  ) async {
    final seen = await _open(tester);
    await tester.enterText(find.byKey(_field), 'note');
    await _chord(tester, _otherModifier, LogicalKeyboardKey.enter);
    expect(seen.regens, 0);
    expect(find.byKey(_field), findsOneWidget);
  }, variant: _platforms);

  testWidgets('the chord carries the lookup words too', (tester) async {
    final seen = await _open(tester, web: true);
    await tester.enterText(find.byKey(_field), 'wrong year');
    await tester.enterText(
      find.byKey(const Key('regen-lookup-query')),
      'Treaty of Ghent',
    );
    await _chord(tester, _platformModifier, LogicalKeyboardKey.enter);
    expect(seen.lookups, 1);
    expect(seen.critique, 'wrong year');
    expect(seen.webQuery, 'Treaty of Ghent');
  }, variant: _platforms);

  testWidgets('the dialog shows the chord for this platform', (tester) async {
    await _open(tester);
    final chord = tester.widget<Text>(
      find.byKey(const Key('regen-critique-chord')),
    );
    expect(
      chord.data,
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘↵' : 'Ctrl+Enter',
    );
  }, variant: _platforms);
}
