// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GLM/Nano-GPT wrap-up is often a planning dump. That stays in Thought.
// The porch line must not become the harness essay about empty bubbles.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

const _dump =
    'The user wants two things:\n'
    '1. Images not loading in the EPUB.\n'
    'Let me look at NSAttributedString and the OEBPS folder. '
    'Actually I should unzip the EPUB and inspect the image hrefs. '
    'This is a significant rendering issue in the current implementation.';

void main() {
  test('planning dump is thought, not wrap-up speech', () {
    expect(waifuLooksThinkDump(_dump), isTrue);
    expect(waifuSpokenLine(_dump), isEmpty);
    expect(kWaifuStuckWrap, isNot(contains('empty bubble')));
    expect(kWaifuStuckWrap, isNot(contains('porch report')));
  });

  test(
    'a dump wrap-up speaks a short fallback, not the empty-bubble essay',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_wrap_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'glob', arguments: {'pattern': '*.epub'}),
          ],
          text: _dump,
        ),
        const LlmToolResponse(calls: [], text: _dump),
        const LlmToolResponse(calls: [], text: _dump),
        const LlmToolResponse(calls: [], text: _dump),
        const LlmToolResponse(calls: [], text: _dump),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
      );
      await WaifuHarness(session: session, llm: llm).send('please?');
      final spoken = session.transcript
          .where((m) => m.kind == WaifuMsgKind.assistant)
          .map((m) => m.text)
          .join('\n');
      expect(spoken, isNot(contains('empty bubble')));
      expect(spoken, isNot(contains('proper porch report')));
      expect(spoken, contains(kWaifuStuckWrap));
      expect(
        session.toolChips.any(
          (c) =>
              c.name == 'turn' &&
              c.detail.contains('without an in-character spoken line'),
        ),
        isFalse,
      );
    },
  );
}
