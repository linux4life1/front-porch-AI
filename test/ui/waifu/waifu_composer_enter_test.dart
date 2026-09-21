// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_composer.dart';
import 'package:front_porch_ai/ui/waifu/waifu_page.dart';

void main() {
  test('bare Enter is handled as send; Shift+Enter is ignored', () {
    var sent = 0;
    KeyEvent down(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.enter,
      logicalKey: key,
      timeStamp: Duration.zero,
    );
    expect(
      waifuComposerKeyEvent(
        down(LogicalKeyboardKey.enter),
        shiftPressed: false,
        enabled: true,
        onSend: () => sent++,
      ),
      KeyEventResult.handled,
    );
    expect(sent, 1);
    expect(
      waifuComposerKeyEvent(
        down(LogicalKeyboardKey.enter),
        shiftPressed: true,
        enabled: true,
        onSend: () => sent++,
      ),
      KeyEventResult.ignored,
    );
    expect(sent, 1);
    expect(
      waifuComposerKeyEvent(
        down(LogicalKeyboardKey.enter),
        shiftPressed: false,
        enabled: false,
        onSend: () => sent++,
      ),
      KeyEventResult.ignored,
    );
    expect(sent, 1);
    expect(
      waifuComposerKeyEvent(
        down(LogicalKeyboardKey.numpadEnter),
        shiftPressed: false,
        enabled: true,
        onSend: () => sent++,
      ),
      KeyEventResult.handled,
    );
    expect(sent, 2);
  });

  testWidgets('Enter in the box sends the task', (tester) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    await tester.enterText(
      find.byKey(const Key('waifu-composer')),
      'hello waifu',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.transcript, isNotEmpty);
    expect(session.transcript.last.text, 'hello waifu');
  });
}
