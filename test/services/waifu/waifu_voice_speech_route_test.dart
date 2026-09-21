// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  WaifuHarness harness() => WaifuHarness(
    session: WaifuSession(
      folderRoot: '/tmp/waifu_voice_route',
      coworker: CharacterCard(name: 'Tiffany'),
    ),
    sessionId: 'ses_1',
  );

  WaifuMessage last(WaifuHarness h) =>
      h.session.transcript.lastWhere((m) => m.kind == WaifuMsgKind.assistant);

  test('coding pass text is Thought; voice pass text is the spoken bubble', () {
    expect(waifuDeltaGoesToThought(voicePass: false, thinking: false), isTrue);
    expect(waifuDeltaGoesToThought(voicePass: true, thinking: false), isFalse);
    expect(waifuDeltaGoesToThought(voicePass: true, thinking: true), isTrue);

    final h = harness();
    h.beginCodingPass();
    h.onTextDelta(
      'I can see the project structure. Let me explore horny_mario.',
    );
    var m = last(h);
    expect(m.text.trim(), isEmpty);
    expect(m.reasoning, contains('I can see the project structure'));

    h.onIdle();
    h.onTextDelta(
      '*adjusts her glasses* All settled in, sweetie — Phase 1 is done.',
    );
    m = last(h);
    expect(m.text, contains('All settled in, sweetie'));
    expect(m.text, isNot(contains('I can see the project structure')));
    expect(m.reasoning, isNot(contains('All settled in')));
  });

  test('Kimi thinking-only voice pass is promoted to the spoken bubble', () {
    final h = harness();
    h.beginCodingPass();
    h.onTextDelta('I should list the folder.', thinking: true);
    h.onIdle();
    h.onTextDelta(
      'All settled in, sweetie — I listed the project and need to read horny_mario next.',
      thinking: true,
    );
    var m = last(h);
    expect(m.text.trim(), isEmpty);
    expect(m.reasoning, contains('All settled in, sweetie'));
    h.onIdle();
    m = last(h);
    expect(m.text, contains('All settled in, sweetie'));
  });
}
