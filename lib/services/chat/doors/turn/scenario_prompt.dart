// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/llm_eval_engine/eval_window.dart'
    show stripEvalThinkBlocks;
import 'package:front_porch_ai/utils/output_sanitizer_regex.dart';
import 'package:front_porch_ai/utils/think_tags.dart';

const scenarioRole =
    'Facilitate the scenario as an offstage narrator. The card title names '
    'the experience, not a person. Do not give it a body or dialogue. '
    'Address the player directly as you. Respond with '
    'what changes in the world or what the player can observe. The player '
    'alone authors their actions, words, thoughts and feelings. Never add '
    'an action they did not say they took, even to lead into your reply. '
    'A player who calls out has not also moved. Attribute NPC speech or actions '
    'clearly. Use readable prose or the card’s requested text format. '
    'When the setting is open, ask for a missing premise or begin with the '
    'premise the player just supplied.';

const scenarioLookupUnavailable =
    'Lookups are unavailable for Scenario replies.';

const scenarioGroupRole =
    ' Other named chat participants have their own turns. Leave their words '
    'and decisions to them, too.';

const scenarioReplyCue =
    '\n[Write one facilitator reply, with the world or NPCs reacting first. '
    'Keep the player where they are unless they said they moved. Leave their '
    'next move open. Start directly with the prose.]';

String scenarioContinueCue(String partial) =>
    '\n[Extend only the unfinished facilitator reply below. Keep its style '
    'and leave the player’s next move to them. Return only new text.]\n$partial';

final _cardMacro = RegExp(
  r'\{\{\s*([^{}]+?)\s*\}\}|\{(user|char|character)\}',
  caseSensitive: false,
);

/// These names and authored fields are data. Expansion neither recurses nor
/// receives the macro callbacks that read/write stored character state.
String resolveScenarioText(
  String text,
  ScenarioCardSnapshot scenario, {
  required String cardName,
  required String playerName,
  required String setting,
}) => text.replaceAllMapped(
  _cardMacro,
  (match) => switch ((match[1] ?? match[2])?.toLowerCase()) {
    'user' => playerName,
    'char' || 'character' => cardName,
    'description' => scenario.description,
    'personality' => scenario.personality,
    'scenario' => setting,
    _ => '',
  },
);

List<String> scenarioStops(List<String> configured) => [
  for (final stop in configured.toSet())
    if (stop.isNotEmpty &&
        !const {
          '\nUser:',
          '\n###',
          '\nScenario:',
          '\nSystem:',
          '\n(Note:',
          '\n[Note:',
          '\n{Note:',
        }.contains(stop))
      stop,
];

final _scenarioThinkTag = RegExp(r'</?think>', caseSensitive: false);

String scenarioContinuationProse(String text) => stripEvalThinkBlocks(
  text.replaceAllMapped(_scenarioThinkTag, (match) => match[0]!.toLowerCase()),
);

final _scenarioThought = RegExp(
  r'<think>[\s\S]*?</think>',
  caseSensitive: false,
);

/// The author's rules can rewrite the prose, including literal markup.
/// Keep canonical reasoning spans outside the editable input to the rules.
String sanitizeScenarioReply(String text, List<OutputSanitizerRule> rules) {
  final tagged = closeOpenThink(text);
  final body = stripThinkTags(tagged);
  if (body.isEmpty) return tagged;
  final sanitized = sanitizeOutput(body, rules);
  if (sanitized.trim().isEmpty) return tagged;

  final thoughts = _scenarioThought.allMatches(tagged).map((m) => m[0]!);
  return [...thoughts, sanitized].join('\n');
}

/// Hold just a plausible stop prefix across chunks so the client, renderer,
/// and voice stream all see the same accepted text.
class ScenarioReplyStream {
  ScenarioReplyStream(this.stops);

  final List<String> stops;
  int _sent = 0;

  String _speechTail = '';
  bool _speakingThought = false;

  /// [text] is a new accepted fragment. Keep split thought markers out of
  /// the sentence buffer so its boundaries can't expose reasoning to speech.
  String speechText(String text, {bool done = false}) {
    final pending = _speechTail + text;
    _speechTail = '';
    final lower = pending.toLowerCase();
    final spoken = StringBuffer();
    var start = 0;
    while (start < pending.length) {
      final tag = _speakingThought ? '</think>' : '<think>';
      final end = lower.indexOf(tag, start);
      if (end >= 0) {
        if (!_speakingThought) spoken.write(pending.substring(start, end));
        _speakingThought = !_speakingThought;
        start = end + tag.length;
        continue;
      }
      var stableEnd = pending.length;
      if (!done) {
        final maxPartial = (tag.length - 1).clamp(0, stableEnd - start);
        for (var length = maxPartial; length > 0; length--) {
          if (!lower.endsWith(tag.substring(0, length))) continue;
          stableEnd -= length;
          _speechTail = pending.substring(stableEnd);
          break;
        }
      }
      if (!_speakingThought) spoken.write(pending.substring(start, stableEnd));
      break;
    }
    return spoken.toString();
  }

  String take(String text, {bool done = false}) {
    var held = 0;
    if (!done) {
      for (final stop in stops) {
        var size = (stop.length - 1).clamp(0, text.length);
        while (size > held) {
          if (text.endsWith(stop.substring(0, size))) {
            held = size;
            break;
          }
          size--;
        }
      }
    }
    final end = text.length - held;
    if (_sent >= end) return '';
    final next = text.substring(_sent, end);
    _sent = end;
    return next;
  }
}
