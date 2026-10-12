// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Eval-canon extract: think-strip, JSON scalars, the recent-exchange
// window, and the needs-impact call that consumes them. Fire / retry /
// cancel stay on LlmEvalEngine. Do not fold StoryJson.stripThinkTags or
// char_macro.stripThinkBlocks — those are different contracts.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/reasoning_markers.dart';

/// The last few turns as `sender: text`, the shape every eval that needs scene
/// context uses.
///
/// Extracted because it was being written out by hand in three places and the
/// copies had already drifted into a bug. When Afterglow's climax check was
/// split out of the needs eval it inherited the reply and NOT this, so a climax
/// the user narrated became invisible to it and E2E went red on three platforms.
/// The Pockets pass had the same narrow view for the same reason.
///
/// Three turns is the window the needs eval has always used: enough to carry
/// the user's message and the reply it prompted, short enough that an eval
/// prompt stays an eval prompt.
/// Pre-gen judges score the USER. After Next Character the live list ends
/// on another NPC's reply — cut there so bond/mood/arousal cannot move off
/// that speech. Trust was already prompt-gated to the user; this is the
/// same rule in code. Post-gen (climax/pockets/posture) keep [recentExchange].
List<ChatMessage> messagesThroughLastUser(List<ChatMessage> msgs) {
  final i = msgs.lastIndexWhere((m) => m.isUser);
  return i < 0 ? msgs : msgs.sublist(0, i + 1);
}

String recentExchangeThroughLastUser(List<ChatMessage> msgs, {int take = 3}) =>
    recentExchange(messagesThroughLastUser(msgs), take: take);

String recentExchange(List<ChatMessage> msgs, {int take = 3}) {
  final n = msgs.length < take ? msgs.length : take;
  return msgs.reversed
      .take(n)
      .toList()
      .reversed
      // promptText, not displayText, since 2026-08-10: the two differ only
      // for photo messages, where promptText carries the "[shared a photo:
      // caption]" marker — and the realism judges already read promptText,
      // so needs/climax/pockets were the only evals blind to a photo the
      // exchange was about (eval review Tier-3 hygiene).
      .map((m) => '${m.sender}: ${clampEvalMessage(m.promptText)}')
      .join('\n');
}

/// Per-message ceiling for EVAL windows (chars, ≈1k tokens). Verbose models
/// write 20k+ character replies, and with no ceiling every judge window
/// ballooned to the size of a short story: the maintainer's own EvalTraffic
/// line showed four ~50k-char eval prompts in ONE turn — 48k tokens and 50
/// seconds of LLM time to score a single exchange, with the objective check
/// spending 50k chars on an 18-char answer. Evals judge the exchange; they
/// do not need to re-read the novella.
const int kEvalMessageCharCap = 4000;

/// The marker a clamped message carries in place of its middle. A visible
/// sentence, not an ellipsis: the judges must know text was omitted rather
/// than believe the reply jump-cut.
const String kEvalClampMarker =
    '[… middle of a very long message omitted for this evaluation …]';

/// Clamp ONE message's contribution to an eval window: text at or under
/// [kEvalMessageCharCap] passes through byte-identical (the overwhelming
/// majority — so short-message prompts, and every existing test fixture,
/// are unchanged); longer text keeps its head and tail around
/// [kEvalClampMarker]. Head-heavy on purpose — a reply's opening carries
/// the reaction to the user (what the judges score) and its tail carries
/// where the scene landed (what the reply-readers need). Pure and
/// deterministic, so a regen sees the identical window (the regen-parity
/// rule: identical inputs must produce identical eval prompts).
String clampEvalMessage(String text) {
  if (text.length <= kEvalMessageCharCap) return text;
  final head = (kEvalMessageCharCap * 2) ~/ 3;
  final tail = kEvalMessageCharCap - head;
  return '${text.substring(0, head)}\n$kEvalClampMarker\n'
      '${text.substring(text.length - tail)}';
}

/// Eval-lane think-strip. Completes, unclosed prefix, and orphan close.
/// User-prose stripThinkTags and chargen stripThinkBlocks stay separate.
String stripEvalThinkBlocks(String text) {
  String cleaned = canonicalizeReasoning(
    text,
  ).replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();
  final unclosed = cleaned.indexOf('<think>');
  if (unclosed >= 0) {
    cleaned = cleaned.substring(0, unclosed).trim();
  }
  // Third leak shape (utils/think_tags.dart names all three): a bare orphan
  // `</think>` whose opening tag the transport/chat template consumed, so
  // everything BEFORE it is reasoning. Unlike the user-prose strip — which
  // only drops the tag, because wiping prose would blank a legit message —
  // the eval lane must drop that reasoning: every extractor below is a
  // firstMatch over the whole string, so leaving it in hands the parse the
  // model's DRAFT numbers instead of its final JSON. Kept only when
  // something follows; otherwise callers' existing raw fallback applies.
  final orphan = cleaned.lastIndexOf('</think>');
  if (orphan >= 0) {
    final after = cleaned.substring(orphan + '</think>'.length).trim();
    if (after.isNotEmpty) cleaned = after;
  }
  return cleaned;
}
