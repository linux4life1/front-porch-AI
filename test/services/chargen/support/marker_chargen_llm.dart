// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A scripted model for the AI creator's engine tests. It answers each real
// prompt the generator sends by what that prompt asks for (an interview
// question, the Porch Life seed, a tool call), so the transcript, the
// profile and the lists are built by the real pipeline from these answers.
// It never hands a test the value the test asserts on.

import 'dart:convert';

import 'package:front_porch_ai/services/llm_service.dart';

/// The base card every JSON stage tolerates (base card, rewrite, lorebook,
/// scenarios). `lorebook: {entries: []}` forces the separate lorebook call.
String markerCardJson({String sentinel = 'ZZSENTINELZZ'}) => jsonEncode({
  'description':
      '$sentinel {{char}} is a wandering cartographer who maps the drowned '
      'coast, sketching ruins the tide reveals at dawn.',
  'personality':
      '$sentinel Curious, meticulous, quietly brave; speaks in measured, '
      'vivid observations and never leaves a map unfinished.',
  'scenario':
      '{{user}} finds {{char}} pinning a half-drawn chart to a tavern wall '
      'while the rain hammers the shutters and the harbour bell rings.',
  'first_message':
      '"You have the look of someone who is also lost," {{char}} says.',
  'example_dialogue': '{{user}}: Hello\n{{char}}: The roads moved again.',
  'system_prompt': '',
  'tags': ['explorer'],
  'image_prompt': 'a cartographer at a candlelit table, portrait',
  'lorebook': {'entries': []},
});

class MarkerChargenLlm extends LLMService {
  MarkerChargenLlm({
    String? cardJson,
    this.longAnswers = false,
    this.lastAnswerMarker = '',
    this.toolAnswers = const {},
    this.textAnswers = const {},
  }) : cardJson = cardJson ?? markerCardJson();

  /// Answer for every prompt nothing else claims.
  final String cardJson;

  /// Interview answers long enough that the transcript passes 1,400 chars.
  final bool longAnswers;

  /// Written only into the answer to the last interview question
  /// (appearance), so a reader that cuts the transcript short loses it.
  final String lastAnswerMarker;

  /// Tool name → the arguments a tool call answers with. A tool not listed
  /// answers nothing, so the caller falls to its text floor.
  final Map<String, Map<String, dynamic>> toolAnswers;

  /// Prompt marker → the text answered when a prompt contains it.
  final Map<String, String> textAnswers;

  /// Called with each streamed prompt before it is answered (a test can
  /// press Stop on a given step).
  void Function(String prompt)? onPrompt;

  final List<String> prompts = [];
  final List<String> toolChoices = [];
  final List<List<Map<String, dynamic>>> toolSchemas = [];

  /// The first prompt containing [marker], or '' when none was sent.
  String promptWith(String marker) =>
      prompts.firstWhere((p) => p.contains(marker), orElse: () => '');

  bool sent(String marker) => prompts.any((p) => p.contains(marker));

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    prompts.add(p);
    onPrompt?.call(p);
    if (p.contains('Question: ')) {
      final last = p.contains(
        'Question: Now describe your physical appearance',
      );
      final body = longAnswers
          ? 'I talk plainly and I mean every word I say to you. ' * 9
          : 'I talk plainly. ';
      yield '$body${last ? lastAnswerMarker : ''}'.trim();
      return;
    }
    for (final e in textAnswers.entries) {
      if (p.contains(e.key)) {
        yield e.value;
        return;
      }
    }
    if (p.contains('Write example dialogue exchanges')) {
      yield '<START>\n{{user}}: Hello\n{{char}}: The roads moved again, '
          'and I mapped every one of them twice.';
      return;
    }
    yield cardJson;
  }

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    toolChoices.add(params.toolChoice ?? '');
    toolSchemas.add(tools);
    prompts.add(params.prompt);
    final args = toolAnswers[params.toolChoice];
    if (args == null) return null;
    return LlmToolResponse(
      calls: [LlmToolCall(name: params.toolChoice!, arguments: Map.from(args))],
      text: '',
    );
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'marker-chargen-test';
}
