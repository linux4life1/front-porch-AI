// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The message editor saves on Ctrl+Enter (⌘+Enter on macOS) from either
// Enter key. Plain Enter, main or numpad, is left to the text field.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/dialogs/message_edit_dialog.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

class _Seen {
  bool closed = false;
  String? saved;
}

Future<_Seen> _open(WidgetTester tester) async {
  final seen = _Seen();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              seen.saved = await showMessageEditDialog(
                context: context,
                initialText: 'Old words.',
              );
              seen.closed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return seen;
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
    testWidgets('the chord with ${enter.keyLabel} saves the edit', (
      tester,
    ) async {
      final seen = await _open(tester);
      await tester.enterText(find.byType(AppTextField).last, 'New words.');
      await tester.sendKeyDownEvent(_platformModifier);
      await _press(tester, enter);
      await tester.sendKeyUpEvent(_platformModifier);
      await tester.pumpAndSettle();
      expect(seen.closed, isTrue);
      expect(seen.saved, 'New words.');
    }, variant: _platforms);

    testWidgets('plain ${enter.keyLabel} is left to the text field', (
      tester,
    ) async {
      final seen = await _open(tester);
      await tester.enterText(find.byType(AppTextField).last, 'New words.');
      final handled = await _press(tester, enter);
      await tester.pumpAndSettle();
      // Unhandled means the key reaches the platform text input, which is
      // what puts the new line into the message.
      expect(handled, isFalse);
      expect(seen.closed, isFalse);
      expect(find.text('Edit Message'), findsOneWidget);
    }, variant: _platforms);
  }
}
