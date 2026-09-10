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

  test(
    'hot window folds between steps, not only after the send ends',
    () async {
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'glob', arguments: {'pattern': '*'}),
          ],
          text: '',
          totalTokens: 180,
        ),
        const LlmToolResponse(
          calls: [],
          text: 'Edited PageLayoutEngine.swift. Tests not run yet.',
        ),
        const LlmToolResponse(calls: [], text: 'On it.'),
      ]);
      final session = WaifuSession(folderRoot: root.path, coworker: _iris())
        ..contextBudget = 200
        ..tokensUsed = 40
        ..tokensFromApi = true;
      session.transcript.addAll(_history());
      await WaifuHarness(session: session, llm: llm).send('keep going');
      expect(llm.calls.first.systemPrompt, contains(kWaifuPreamble));
      expect(llm.calls.length, greaterThanOrEqualTo(2));
      expect(llm.calls[1].systemPrompt, contains('Do not invent files'));
      expect(session.compactPasses, greaterThanOrEqualTo(1));
    },
  );

  test('Stop on a hot window still folds', () async {
    late WaifuHarness harness;
    final llm = ScriptedWaifuLlm(
      [
        const LlmToolResponse(calls: [], text: ''),
        const LlmToolResponse(calls: [], text: ''),
      ],
      beforeGenerate: (i) async {
        if (i == 0) harness.abort();
      },
    );
    final session = WaifuSession(folderRoot: root.path, coworker: _iris())
      ..contextBudget = 100
      ..tokensUsed = 90
      ..tokensFromApi = true;
    session.transcript.addAll(_history());
    harness = WaifuHarness(session: session, llm: llm);
    await harness.send('keep going');
    expect(session.compactPasses, 1);
    expect(session.transcript.first.hidden, isTrue);
  });

  test('/compact remeters when the bar is API-stuck over the cap', () async {
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [], text: 'Prior turn folded.'),
    ]);
    final session = WaifuSession(folderRoot: root.path, coworker: _iris())
      ..contextBudget = 277518
      ..tokensUsed = 300086
      ..tokensFromApi = true;
    session.transcript.addAll([
      const WaifuMessage.user('fix the reader'),
      const WaifuMessage.assistant('On it.'),
      const WaifuMessage.user('still broken'),
    ]);
    await WaifuHarness(session: session, llm: llm).compact();
    expect(session.compactPasses, 1);
    expect(session.tokensFromApi, isFalse);
    expect(session.tokensUsed, lessThan(300086));
    expect(session.transcript.last.text, 'Folded old turns.');
  });

  test('/compact stubs a tool storm on the live turn', () async {
    final llm = ScriptedWaifuLlm(const []);
    final session = WaifuSession(folderRoot: root.path, coworker: _iris())
      ..contextBudget = 8000;
    session.transcript.add(const WaifuMessage.user('fix it'));
    for (var i = 0; i < 12; i++) {
      session.transcript.add(
        WaifuMessage.tool(
          name: 'read',
          output: 'read\n${'x' * 4000}',
          ok: true,
          path: 'f$i.swift',
        ),
      );
    }
    final before = session.transcript
        .where((m) => m.kind == WaifuMsgKind.tool)
        .fold<int>(0, (n, m) => n + m.text.length);
    await WaifuHarness(session: session, llm: llm).compact();
    expect(session.compactPasses, 1);
    expect(session.transcript.last.text, 'Folded old turns.');
    final after = session.transcript
        .where((m) => m.kind == WaifuMsgKind.tool)
        .fold<int>(0, (n, m) => n + m.text.length);
    expect(after, lessThan(before));
  });
}
