// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ⌘R (Ctrl+R elsewhere) opens the Regenerate dialog from the chat box.
// Pressing it again in the dialog regenerates straight away, so a quick
// re-roll needs no reason typed and no reach for the mouse. Before, the
// second press went unhandled and macOS played its error sound.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/widgets/regen_critique_field.dart';

const _field = Key('regen-critique-field');

class _Seen {
  String? critique;
  int regens = 0;
}

Future<_Seen> _open(WidgetTester tester) async {
  final seen = _Seen();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => promptRegenCritiqueThen(context, (c) {
              seen.regens++;
              seen.critique = c;
            }),
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

Future<bool> _chordR(WidgetTester tester, LogicalKeyboardKey modifier) async {
  await tester.sendKeyDownEvent(modifier);
  final handled = await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
  return handled;
}

bool get _mac => defaultTargetPlatform == TargetPlatform.macOS;

final _platforms = TargetPlatformVariant(const {
  TargetPlatform.linux,
  TargetPlatform.windows,
  TargetPlatform.macOS,
});

void main() {
  testWidgets('pressing the shortcut again regenerates with no reason', (
    tester,
  ) async {
    final seen = await _open(tester);
    final handled = await _chordR(
      tester,
      _mac ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
    );
    expect(handled, isTrue, reason: 'unhandled is the macOS error sound');
    expect(seen.regens, 1);
    expect(seen.critique, '');
    expect(find.byKey(_field), findsNothing);
  }, variant: _platforms);

  testWidgets('a reason already typed goes with it', (tester) async {
    final seen = await _open(tester);
    await tester.enterText(find.byKey(_field), 'shorter');
    await _chordR(
      tester,
      _mac ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
    );
    expect(seen.regens, 1);
    expect(seen.critique, 'shorter');
  }, variant: _platforms);

  testWidgets('the other platform\'s modifier with R does nothing', (
    tester,
  ) async {
    final seen = await _open(tester);
    await _chordR(
      tester,
      _mac ? LogicalKeyboardKey.controlLeft : LogicalKeyboardKey.metaLeft,
    );
    expect(seen.regens, 0);
    expect(find.byKey(_field), findsOneWidget);
  }, variant: _platforms);
}
