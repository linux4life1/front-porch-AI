// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

/// The line above the composer says what she is doing, in her name.
void main() {
  WaifuSession running() => WaifuSession(
    folderRoot: '.',
    coworker: CharacterCard(name: 'Mira'),
  )..running = true;

  test('a running test command reads as running tests', () {
    final session = running()
      ..transcript.addAll([
        const WaifuMessage.user('fix it'),
        const WaifuMessage.assistant(
          '',
          chips: [
            WaifuToolChip(name: 'read', detail: 'lib/a.dart', ok: true),
            WaifuToolChip(
              name: 'bash',
              detail: 'flutter test test/a_test.dart',
              ok: true,
              pending: true,
            ),
          ],
        ),
      ]);
    expect(waifuStatusLine(session), 'Mira is running tests…');
  });

  test('with no tool live, the todo in progress is the status', () {
    final session = running();
    session.todos.write([
      {'id': '1', 'content': 'Write the parser', 'status': 'completed'},
      {'id': '2', 'content': 'Wire the CLI flag', 'status': 'in_progress'},
    ]);
    expect(waifuStatusLine(session), 'Mira is working on: Wire the CLI flag');
  });

  test('idle shows nothing; a fresh turn is thinking', () {
    final session = running();
    expect(waifuStatusLine(session), 'Mira is thinking…');
    session.running = false;
    expect(waifuStatusLine(session), isNull);
  });

  test('a pending edit names the file once it is known', () {
    expect(waifuToolDoing('edit', 'pending'), 'is editing a file');
    expect(waifuToolDoing('edit', 'lib/main.dart'), 'is editing lib/main.dart');
  });

  testWidgets('the status line paints while a turn runs', (tester) async {
    final session = running()
      ..transcript.add(
        const WaifuMessage.assistant(
          '',
          chips: [
            WaifuToolChip(
              name: 'read',
              detail: 'README.md',
              ok: true,
              pending: true,
            ),
          ],
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WaifuStatusLine(session: session)),
      ),
    );
    expect(find.text('Mira is reading README.md…'), findsOneWidget);
  });
}
