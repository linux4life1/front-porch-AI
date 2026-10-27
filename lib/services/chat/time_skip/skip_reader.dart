// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The skip reader: one small model call, before the reply, that reads the
// player's line and says whether it skips story time and how far. It
// replaced the phrase lists that guessed skips by pattern (#629: "slept
// eight hours and woke up" landed at 8 AM, five hours on). It runs only
// when the wide net (skip_net.dart) sees time words, and only answers;
// [SkipVerdict.landing] does the date math and the caller moves the clock.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_skip/skip_verdict.dart';

class SkipReader {
  const SkipReader({
    required this.fireLLMEval,
    required this.stripThinkBlocks,
    this.fireToolEval,
    this.probe,
    this.getBackendIdentity,
  });

  final Future<String?> Function(String prompt) fireLLMEval;
  final String Function(String text) stripThinkBlocks;
  final Object? fireToolEval;
  final ToolTransportProbe? probe;
  final String Function()? getBackendIdentity;

  /// What [line] skips, [SkipVerdict.none] when nothing, or null when the
  /// model gave no usable answer. [recent] is the scene just before it.
  Future<SkipVerdict?> read({
    required String line,
    required DateTime clock,
    String recent = '',
  }) async {
    String prompt({required bool toolsMode}) =>
        buildSkipReaderPrompt(line, clock, recent, toolsMode: toolsMode);
    final String? raw;
    try {
      raw = fireToolEval != null && probe != null
          ? await fireStructuredEval(
              probe: probe!,
              backendIdentity: getBackendIdentity?.call() ?? '',
              debugLabel: kSkipReaderTool,
              tools: kSkipReaderTools,
              buildPrompt: prompt,
              callToText: (resp) =>
                  realismToolCallToJson(kSkipReaderTool, resp.calls),
              fireToolEval: fireToolEval!,
              toolChoice: kSkipReaderTool,
              fireTextEval: (p, {onChunk}) => fireLLMEval(p),
            )
          : await fireLLMEval(prompt(toolsMode: false));
    } catch (e) {
      debugPrint('[Realism:Skip] reader failed: $e');
      return null;
    }
    if (raw == null) return null;
    final verdict = SkipVerdict.fromJsonText(stripThinkBlocks(raw));
    debugPrint('[Realism:Skip] "$line" → ${verdict ?? 'no answer'}');
    return verdict;
  }
}

/// The reader's question. Public so the live phrase test sends the same
/// words the app does.
String buildSkipReaderPrompt(
  String line,
  DateTime clock,
  String recent, {
  required bool toolsMode,
}) {
  final scene = recent.trim().isEmpty
      ? ''
      : 'The scene just before it:\n${recent.trim()}\n\n';
  final answer = toolsMode
      ? 'Report by calling the $kSkipReaderTool tool. Use ONLY the tool.'
      : 'Respond with ONLY valid JSON, no markdown, for example:\n'
            '{"skip": true, "minutes": 480, "until": "", "gap": "slept"}\n'
            '{"skip": false, "minutes": 0, "until": "", "gap": "none"}';
  return 'You keep the story clock for a roleplay. It is '
      '${StoryClock.clockPhrase(clock)}.\n\n'
      '${scene}The player just wrote:\n$line\n\n'
      'Does this line move the story forward past a stretch of time, '
      'skipping it? A skip is the line itself jumping ahead: "eight hours '
      'later", "we sleep through the night", "(OOC: skip to morning)", "two '
      'weeks pass", "the next day". These are NOT skips: talking about time '
      'or plans ("let\'s sleep", "see you tomorrow"), memories ("we met two '
      'weeks ago"), and actions that happen in the moment. Words inside '
      'double quotes are spoken by a character, never a skip.\n'
      '- minutes: the time skipped, counted (8 hours = 480, a day = 1440, '
      'two weeks = 20160). 0 when the line only says when it lands, like '
      '"until morning" or "the next morning".\n'
      '- until: where it lands if the line says so: dawn, morning, '
      'late_morning, afternoon, evening, night, or a 24-hour HH:MM. Empty '
      'when it does not say.\n'
      '- gap: "slept" when the characters slept through the skipped time, '
      '"other" for any other skip, "none" when there is no skip.\n\n'
      '$answer';
}
