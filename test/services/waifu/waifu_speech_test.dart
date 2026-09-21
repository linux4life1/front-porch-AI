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
    expect(kWaifuVoicePreamble, contains('Speak as this character'));
    expect(
      RegExp(r'\bshe\b', caseSensitive: false).hasMatch(kWaifuOpenCodePreamble),
      isFalse,
    );
  });
}
