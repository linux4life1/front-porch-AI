// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('hot window does not steal the first model call for a recap', () async {
    final root = await Directory.systemTemp.createTemp('waifu_between_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [], text: 'On it. Next is the mesh.'),
      const LlmToolResponse(
        calls: [],
        text: 'Edited files. Tests not run yet.',
      ),
    ]);
    final session =
        WaifuSession(
            folderRoot: root.path,
            coworker: CharacterCard(name: 'Iris'),
          )
          ..contextBudget = 100
          ..tokensUsed = 90
          ..tokensFromApi = true;
    session.transcript.addAll([
      for (var i = 0; i < 20; i++)
        WaifuMessage(
          isUser: i.isEven,
          text: i.isEven ? 'please edit page_$i.swift' : 'Did page_$i.swift.',
        ),
    ]);
    await WaifuHarness(session: session, llm: llm).send('keep going');
    expect(llm.calls, isNotEmpty);
    expect(llm.calls.first.systemPrompt, contains(kWaifuPreamble));
    expect(
      llm.calls.first.systemPrompt,
      isNot(contains('Do not invent files')),
    );
    expect(llm.calls.first.prompt, contains('keep going'));
  });
}
