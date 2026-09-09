// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

CharacterCard _iris() => CharacterCard(name: 'Iris', personality: 'dry');

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_compact_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  List<WaifuMessage> _history() => [
    for (var i = 0; i < 20; i++)
      WaifuMessage(
        isUser: i.isEven,
        text: i.isEven ? 'please edit page_$i.swift' : 'Did page_$i.swift.',
      ),
  ];

  test('under 75% fill does not fold a long transcript after send', () async {
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [], text: 'On it.'),
    ]);
    final session = WaifuSession(folderRoot: root.path, coworker: _iris())
      ..contextBudget = 100000;
    session.transcript.addAll(_history());
    await WaifuHarness(session: session, llm: llm).send('keep going');
    expect(session.compactPasses, 0);
    expect(session.transcript.length, greaterThan(kWaifuCompactKeep));
    expect(llm.calls, hasLength(1));
    expect(llm.calls.first.systemPrompt, contains(kWaifuPreamble));
  });

  test('/compact asks the model for a recap and hides it', () async {
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [],
        text: 'Edited PageLayoutEngine.swift. Tests not run yet.',
      ),
    ]);
    final session = WaifuSession(folderRoot: root.path, coworker: _iris())
      ..contextBudget = 100000;
    session.transcript.addAll(_history());
    await WaifuHarness(session: session, llm: llm).compact();
    expect(session.compactPasses, 1);
    expect(session.transcript.first.hidden, isTrue);
    expect(session.transcript.first.text, contains(kWaifuCompactPrefix));
    expect(session.transcript.first.text, contains('PageLayoutEngine.swift'));
    expect(session.transcript.last.text, 'Folded old turns.');
    expect(
      session.transcript.where((m) => !m.hidden && m.text.contains('page_0')),
      isEmpty,
    );
    expect(llm.calls.single.tools, isEmpty);
    expect(llm.calls.single.systemPrompt, contains('Do not invent files'));
  });

  test('API usage from a turn is what the bar stores', () async {
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [],
        text: 'Hmph.',
        promptTokens: 9000,
        completionTokens: 40,
        totalTokens: 9040,
      ),
    ]);
    final session = WaifuSession(folderRoot: root.path, coworker: _iris());
    var sawApi = false;
    final harness = WaifuHarness(session: session, llm: llm);
    harness.onChanged = () {
      if (session.tokensFromApi && session.tokensUsed == 9040) {
        sawApi = true;
      }
    };
    await harness.send('hi');
    expect(sawApi, isTrue);
    expect(session.tokensUsed, greaterThan(waifuEstimateTokens('hi')));
    expect(
      session.tokensUsed,
      greaterThanOrEqualTo(waifuEstimateToolsTokens(llm.calls.first.tools)),
    );
  });

  test(
    'harness compact fallback stays extractive if the model is silent',
    () async {
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(calls: [], text: ''),
      ]);
      final session = WaifuSession(folderRoot: root.path, coworker: _iris());
      session.transcript.addAll(_history());
      await WaifuHarness(session: session, llm: llm).compact();
      expect(session.compactPasses, 1);
      expect(session.transcript.first.text.toLowerCase(), contains('recap'));
      expect(session.transcript.first.text, contains('page_0.swift'));
    },
  );
}
