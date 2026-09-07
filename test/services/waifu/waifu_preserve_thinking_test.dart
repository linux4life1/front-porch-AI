// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/llm_service.dart';

CharacterCard _iris() =>
    CharacterCard(name: 'Iris', personality: 'dry, does the work');

void main() {
  test('off drops thought tokens from the next prompt', () async {
    final root = await Directory.systemTemp.createTemp('waifu_think_off_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [],
        text: 'Hmph. First.',
        reasoning: 'SECRET_PLAN count the files',
      ),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _iris(),
      preserveThinking: false,
    );
    final harness = WaifuHarness(session: session, llm: llm);
    await harness.send('look');
    await harness.send('again');
    expect(session.transcript.last.reasoning, isNot(contains('SECRET_PLAN')));
    expect(llm.calls.last.prompt, isNot(contains('SECRET_PLAN')));
    expect(llm.calls.last.prompt, isNot(contains('<think>')));
  });

  test('on sends prior thought tokens back in <think>', () async {
    final root = await Directory.systemTemp.createTemp('waifu_think_on_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [],
        text: 'Hmph. First.',
        reasoning: 'SECRET_PLAN count the files',
      ),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _iris(),
      preserveThinking: true,
    );
    final harness = WaifuHarness(session: session, llm: llm);
    await harness.send('look');
    await harness.send('again');
    expect(llm.calls, hasLength(2));
    expect(
      llm.calls.last.prompt,
      contains('<think>SECRET_PLAN count the files</think>'),
    );
  });
}
