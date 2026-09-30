// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Wiki lookup sees two user lines and one character reply, not the
// transcript. Recipe cards still see the character prompt.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

WikiWindowTurn _line(String speaker, String text, {bool isUser = false}) {
  return WikiWindowTurn(speaker: speaker, text: text, isUser: isUser);
}

void main() {
  const older = 'who is her sister';
  const reply = 'Yoruichi, from the flashback';
  const latest = 'tell me about that ritual';
  const ancient = 'TRANSCRIPT from the first night';

  test('window is the older user line, one reply, then the latest line', () {
    final window = formatWikiLookupWindow([
      _line('Sam', ancient, isUser: true),
      _line('Mara', 'we met on the docks'),
      _line('Sam', older, isUser: true),
      _line('Mara', reply),
      _line('Sam', latest, isUser: true),
    ]);
    expect(window, 'Sam: $older\nMara: $reply\nSam: $latest');
    expect(window, isNot(contains(ancient)));
    expect(window, isNot(contains('docks')));
  });

  test('a missing earlier line is omitted', () {
    expect(
      formatWikiLookupWindow([
        _line('Mara', reply),
        _line('Sam', latest, isUser: true),
      ]),
      'Mara: $reply\nSam: $latest',
    );
    expect(
      formatWikiLookupWindow([_line('Sam', latest, isUser: true)]),
      'Sam: $latest',
    );
  });

  test('two user lines with no character between keep only the latest', () {
    final window = formatWikiLookupWindow([
      _line('Sam', older, isUser: true),
      _line('Sam', latest, isUser: true),
    ]);
    expect(window, 'Sam: $latest');
    expect(window, isNot(contains(older)));
  });

  test('an empty latest user line skips the wiki job', () {
    final jobs = catalogDoorbellJobs(
      mouth: const GenerationParams(prompt: 'TRANSCRIPT'),
      catalog: buildToolCatalog(inProcess: [inProcessWikiSearchTool()]),
      lastUserMessage: '   ',
      wikiWindow: '',
    );
    expect(jobs, isEmpty);
  });

  test('recipe cards stay on the character prompt', () {
    const transcript = 'TRANSCRIPT of the whole chat';
    const card = 'CARD persona';
    final mouth = const GenerationParams(
      prompt: transcript,
      systemPrompt: card,
    );
    final jobs = catalogDoorbellJobs(
      mouth: mouth,
      catalog: CatalogBuildResult(
        tools: [
          inProcessWikiSearchTool(),
          inProcessWikiPageTool(),
          const CatalogTool(
            name: 'recipe_card',
            description: 'a scene card',
            parameters: {},
            source: ToolSource.userCard,
          ),
        ],
        exclusions: const [],
      ),
      lastUserMessage: latest,
      wikiWindow: 'Sam: $older\nMara: $reply\nSam: $latest',
    );
    expect(jobs, hasLength(2));
    expect(jobs[0].catalog.hasWiki, isTrue);
    expect(jobs[0].params.prompt, isNot(contains('TRANSCRIPT')));
    expect(jobs[0].params.systemPrompt, kWikiDoorbellSystem);
    expect(identical(jobs[1].params, mouth), isTrue);
    expect(jobs[1].catalog.tools.single.name, 'recipe_card');
  });
}
