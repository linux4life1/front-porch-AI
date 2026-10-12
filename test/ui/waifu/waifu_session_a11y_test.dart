// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

/// The session screen tells outcomes by shape and words, not colour, and
/// Enter waits for an input method to finish.
void main() {
  testWidgets('a failed tool reads as a cross and says failed', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WaifuToolLog(
            chips: [
              WaifuToolChip(name: 'bash', detail: 'npm test', ok: true),
              WaifuToolChip(name: 'edit', detail: 'no such file', ok: false),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('waifu-tool-ok-0')), findsOneWidget);
    expect(find.byKey(const Key('waifu-tool-fail-1')), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byKey(const Key('waifu-tool-fail-1'))).icon,
      isNot(tester.widget<Icon>(find.byKey(const Key('waifu-tool-ok-0'))).icon),
    );
    expect(find.bySemanticsLabel('failed'), findsOneWidget);
    expect(find.bySemanticsLabel('done'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('screen readers hear a todo status in words', (tester) async {
    final semantics = tester.ensureSemantics();
    final todos = WaifuTodos()
      ..write([
        {'id': '1', 'content': 'Read the code', 'status': 'completed'},
        {'id': '2', 'content': 'Wire the flag', 'status': 'in_progress'},
        {'id': '3', 'content': 'Write tests', 'status': 'pending'},
      ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WaifuTodoList(todos: todos)),
      ),
    );
    expect(find.bySemanticsLabel('In progress'), findsOneWidget);
    expect(find.bySemanticsLabel('Done'), findsOneWidget);
    expect(find.bySemanticsLabel('To do'), findsOneWidget);
    expect(find.bySemanticsLabel('in_progress'), findsNothing);
    semantics.dispose();
  });

  test('Enter while an input method is composing does not send', () {
    var sent = 0;
    const enter = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: LogicalKeyboardKey.enter,
      timeStamp: Duration.zero,
    );
    expect(
      waifuComposerKeyEvent(
        enter,
        shiftPressed: false,
        enabled: true,
        composing: true,
        onSend: () => sent++,
      ),
      KeyEventResult.ignored,
    );
    expect(sent, 0);
  });

  testWidgets('the composer box passes the composing state through', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    final box = find.byKey(const Key('waifu-composer'));
    await tester.tap(box);
    await tester.pump();
    tester.widget<TextField>(box).controller!.value = const TextEditingValue(
      text: 'にほん',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.transcript, isEmpty);
  });
}
