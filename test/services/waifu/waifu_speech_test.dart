// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  WaifuHarness harness() => WaifuHarness(
    session: WaifuSession(
      folderRoot: '/tmp/waifu_speech',
      coworker: CharacterCard(name: 'Tiffany'),
    ),
    sessionId: 'ses_1',
  );

  WaifuMessage last(WaifuHarness h) =>
      h.session.transcript.lastWhere((m) => m.kind == WaifuMsgKind.assistant);

  test(
    'planning dump "The user is asking…" stays in Thought, not the bubble',
    () {
      final h = harness();
      h.onTextDelta('short native plan', thinking: true);
      h.onTextDelta(
        'The user is asking me to create a sexually explicit game. '
        'I need to check my guidelines.',
      );
      h.onTextDelta(' Looking at my instructions: stay in character.');
      final m = last(h);
      expect(m.text.trim(), isEmpty);
      expect(m.reasoning, contains('The user is asking me'));
      expect(m.reasoning, contains('Looking at my instructions'));
    },
  );

  test('token-split "The" + " user is asking" still folds into Thought', () {
    final h = harness();
    h.onTextDelta('The');
    h.onTextDelta(' user is asking me to create a fetish mario clone.');
    final m = last(h);
    expect(m.text.trim(), isEmpty);
    expect(m.reasoning, contains('The user is asking me'));
  });

  test('quoted wrap-up after a dump is the spoken bubble', () {
    final h = harness();
    h.onTextDelta('The user wants a side-scroller.');
    h.onTextDelta('\n"Alright, I will sketch the first level."');
    final m = last(h);
    expect(m.reasoning, contains('The user wants'));
    expect(m.text, contains('Alright, I will sketch'));
    expect(m.text, isNot(contains('The user wants')));
  });

  test('native think then unquoted wrap-up is still spoken, not Thought', () {
    final h = harness();
    h.onTextDelta('I will read the file first.', thinking: true);
    h.onTextDelta('Hmph. It is in.');
    final m = last(h);
    expect(m.reasoning, contains('I will read the file first.'));
    expect(m.text, 'Hmph. It is in.');
  });

  test('after a tool, unquoted wrap-up stays in the spoken bubble', () {
    final h = harness();
    h.onTextDelta('plan the patch', thinking: true);
    h.onTool(name: 'edit', detail: 'main.dart', ok: true);
    h.onTextDelta('Patched the file.');
    final m = last(h);
    expect(m.text, contains('Patched the file.'));
    expect(m.reasoning, isNot(contains('Patched the file.')));
  });

  test('after a tool, a planning dump still goes to Thought', () {
    final h = harness();
    h.onTool(name: 'read', detail: 'main.dart', ok: true);
    h.onTextDelta('The user wants me to rewrite the player controller.');
    final m = last(h);
    expect(m.text.trim(), isEmpty);
    expect(m.reasoning, contains('The user wants me'));
  });

  test('idle salvages a leaked dump out of the spoken bubble', () {
    final h = harness();
    h.onTextDelta(
      'The user is asking me to create a strip-club platformer. '
      'This falls under creating sexual content.',
    );
    h.onIdle();
    final m = last(h);
    expect(m.text.trim(), isEmpty);
    expect(m.reasoning, contains('strip-club platformer'));
  });

  test('idle does not steal unquoted speech into Thought', () {
    final h = harness();
    h.onTextDelta('Hmph. The renderer compiles.');
    h.onIdle();
    final m = last(h);
    expect(m.text, 'Hmph. The renderer compiles.');
    expect(m.reasoning, isEmpty);
  });

  test('preamble does the asked 18+ work instead of a safety lecture', () {
    expect(kWaifuOpenCodePreamble, contains('refusing the asked work is not'));
    expect(kWaifuOpenCodePreamble, contains('18+'));
    expect(kWaifuOpenCodePreamble, contains('adult or erotic'));
    expect(kWaifuOpenCodePreamble, contains('Do not lecture about safety'));
    expect(
      kWaifuOpenCodePreamble,
      contains('The spoken reply is one in-character line'),
    );
    expect(
      RegExp(r'\bshe\b', caseSensitive: false).hasMatch(kWaifuOpenCodePreamble),
      isFalse,
    );
  });
}
