// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('recap is not labeled User or coworker in the loop prompt', () {
    const recap = WaifuMessage(
      isUser: false,
      hidden: true,
      text: '$kWaifuCompactPrefix\nEdited PageLayoutEngine.swift.',
    );
    const user = WaifuMessage(isUser: true, text: 'keep going');
    const iris = WaifuMessage(isUser: false, text: 'On it.');
    expect(waifuIsPromptRecap(recap), isTrue);
    expect(waifuIsPromptRecap(user), isFalse);
    expect(waifuIsPromptRecap(iris), isFalse);
    final recapLine = waifuPromptSpeech(recap, 'Iris', preserveThinking: false);
    expect(recapLine, startsWith('Session recap'));
    expect(recapLine, isNot(startsWith('User:')));
    expect(recapLine, isNot(startsWith('Iris:')));
    expect(
      waifuPromptSpeech(user, 'Iris', preserveThinking: false),
      'User: keep going',
    );
    expect(
      waifuPromptSpeech(iris, 'Iris', preserveThinking: false),
      'Iris: On it.',
    );
    final prompt = waifuLoopUserPrompt(
      folderName: 'app',
      coworkerName: 'Iris',
      transcript: const [recap, user, iris],
      todos: '',
      mentionBlock: '',
      toolTrace: '',
    );
    expect(prompt, contains('Session recap'));
    expect(prompt, isNot(contains('User: $kWaifuCompactPrefix')));
    expect(prompt, isNot(contains('Iris: $kWaifuCompactPrefix')));
    expect(prompt, contains('User: keep going'));
    expect(prompt, contains('Iris: On it.'));
  });

  test('extractive recap is hidden and not a user line', () {
    final msgs = [
      const WaifuMessage(isUser: true, text: 'please write hello.txt'),
      for (var i = 0; i < 24; i++)
        WaifuMessage(isUser: i.isEven, text: 'pad $i ' * 40),
    ];
    final compact = waifuCompactTranscript(msgs, budgetChars: 80, keep: 4);
    expect(compact.first.hidden, isTrue);
    expect(compact.first.isUser, isFalse);
    final line = waifuPromptSpeech(
      compact.first,
      'Iris',
      preserveThinking: false,
    );
    expect(line, startsWith('Session recap'));
    expect(line, contains('hello.txt'));
    expect(line, isNot(startsWith('User:')));
    expect(line, isNot(startsWith('Iris:')));
  });

  test('/compact recap is not a user message', () async {
    final root = await Directory.systemTemp.createTemp('waifu_roles_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [],
        text: 'Edited PageLayoutEngine.swift. Tests not run yet.',
      ),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    )..contextBudget = 100000;
    session.transcript.addAll([
      for (var i = 0; i < 20; i++)
        WaifuMessage(
          isUser: i.isEven,
          text: i.isEven ? 'please edit page_$i.swift' : 'Did page_$i.swift.',
        ),
    ]);
    await WaifuHarness(session: session, llm: llm).compact();
    final recap = session.transcript.first;
    expect(recap.hidden, isTrue);
    expect(recap.isUser, isFalse);
    expect(recap.text, contains(kWaifuCompactPrefix));
    expect(session.transcript.where((m) => m.isUser && m.hidden), isEmpty);
    expect(
      waifuPromptSpeech(recap, 'Iris', preserveThinking: false),
      isNot(startsWith('User:')),
    );
  });

  test('saved recap marked as user is healed on load', () async {
    final dir = await Directory.systemTemp.createTemp('waifu_heal_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final folder = '${dir.path}/proj';
    await Directory('${dir.path}/sessions').create(recursive: true);
    final slug = waifuSessionSlug(folder);
    await File('${dir.path}/sessions/$slug.json').writeAsString(
      '{"title":"t","folderRoot":"$folder","mode":"build",'
      '"coworker":{"name":"Iris","personality":"","description":"",'
      '"systemPrompt":""},"transcript":[{"isUser":true,"hidden":true,'
      '"text":"$kWaifuCompactPrefix\\nEdited the renderer."}]}',
    );
    final loaded = await WaifuStore(dir.path).loadSession(folder);
    expect(loaded, isNotNull);
    expect(loaded!.transcript, hasLength(1));
    expect(loaded.transcript.first.isUser, isFalse);
    expect(loaded.transcript.first.hidden, isTrue);
  });
}
