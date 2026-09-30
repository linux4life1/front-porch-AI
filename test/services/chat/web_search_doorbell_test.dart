// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web-search doorbell must see the latest user line, not the character
// prompt. Proven red by handing catalogDoorbellJobs the mouth prompt: the
// captured generateWithTools prompt then contains TRANSCRIPT.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

class _CaptureLlm extends LLMService {
  final List<GenerationParams> seen = [];

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    seen.add(params);
    return const LlmToolResponse(calls: [], text: '');
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

void main() {
  const lastLine = 'who is Yhwach in Bleach';
  const transcript = 'TRANSCRIPT of the whole chat, scene after scene.';
  const card = 'CARD persona and examples';

  GenerationParams mouth() => const GenerationParams(
    prompt: transcript,
    systemPrompt: card,
    maxLength: 9846,
    temperature: 1.1,
    reasoningEnabled: true,
    images: ['not-a-real-image'],
  );

  test('web search job is the last user line, not the character prompt', () {
    final jobs = catalogDoorbellJobs(
      mouth: mouth(),
      catalog: buildToolCatalog(inProcess: [inProcessWebSearchTool()]),
      lastUserMessage: '  $lastLine  ',
    );
    expect(jobs, hasLength(1));
    final job = jobs.single;
    expect(job.catalog.tools.map((t) => t.name), [kWebSearchToolName]);
    expect(job.params.prompt, lastLine);
    expect(job.params.systemPrompt, kWebSearchDoorbellSystem);
    expect(job.params.prompt, isNot(contains('TRANSCRIPT')));
    expect(job.params.systemPrompt, isNot(contains('CARD')));
    expect(job.params.chatMessages, isNull);
    expect(job.params.images, isNull);
    expect(job.params.reasoningEnabled, isFalse);
    expect(job.params.reasoningMaxTokens, 0);
    expect(job.params.maxLength, isNot(9846));
  });

  test('an empty user line does not send a web-search trip', () {
    final jobs = catalogDoorbellJobs(
      mouth: mouth(),
      catalog: buildToolCatalog(inProcess: [inProcessWebSearchTool()]),
      lastUserMessage: '   ',
    );
    expect(jobs, isEmpty);
  });

  test('wiki gets the short window and drops web_search', () {
    const window = 'Sam: who is her sister\nMara: Yoruichi\nSam: $lastLine';
    final jobs = catalogDoorbellJobs(
      mouth: mouth(),
      catalog: buildToolCatalog(
        inProcess: [inProcessWebSearchTool(), inProcessWikiSearchTool()],
      ),
      lastUserMessage: lastLine,
      wikiWindow: window,
    );
    expect(jobs, hasLength(2));
    expect(jobs[0].params.prompt, lastLine);
    expect(jobs[0].catalog.hasSearch, isTrue);
    expect(jobs[0].catalog.hasWiki, isFalse);
    expect(jobs[1].params.prompt, window);
    expect(jobs[1].params.systemPrompt, kWikiDoorbellSystem);
    expect(jobs[1].params.prompt, isNot(contains('TRANSCRIPT')));
    expect(jobs[1].params.systemPrompt, isNot(contains('CARD')));
    expect(jobs[1].catalog.hasSearch, isFalse);
    expect(jobs[1].catalog.hasWiki, isTrue);
  });

  test('runCatalogRound forwards only that line to the model', () async {
    final jobs = catalogDoorbellJobs(
      mouth: mouth(),
      catalog: buildToolCatalog(inProcess: [inProcessWebSearchTool()]),
      lastUserMessage: lastLine,
    );
    final llm = _CaptureLlm();
    await runCatalogRound(
      llm: llm,
      params: jobs.single.params,
      catalog: jobs.single.catalog,
      search: WebSearchService(getApiKey: () => ''),
    );
    expect(llm.seen, hasLength(1));
    final sent = llm.seen.single;
    expect(sent.prompt, lastLine);
    expect(sent.systemPrompt, kWebSearchDoorbellSystem);
    expect(sent.prompt, isNot(contains('TRANSCRIPT')));
    expect(sent.systemPrompt, isNot(contains('CARD')));
    final wire = sent.chatMessages!.map((m) => m['content']).join('\n');
    expect(wire, contains(lastLine));
    expect(wire, isNot(contains('TRANSCRIPT')));
    expect(wire, isNot(contains('CARD')));
  });
}
