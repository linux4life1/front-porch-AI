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

import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Nano-GPT dumps CoT as normal text. Same porch as chat think chips.
bool waifuLooksLikeThinkingDump(String raw) {
  final t = raw.trimLeft().toLowerCase();
  if (t.isEmpty) return false;
  if (t.startsWith('<think')) return true;
  if (t.startsWith('<|channel') || t.startsWith('<channel')) return true;
  if (t.startsWith('thought\n') || t.startsWith('thought\r')) return true;
  if (t.startsWith('<reasoning') || t.startsWith('<thinking')) return true;
  if (reasoningMarkersMayBePresent(raw) && t.startsWith('◁think')) return true;
  if (t.startsWith('the user')) return true;
  if (t.startsWith('let me ')) return true;
  if (t.startsWith("i'll read") || t.startsWith('i will read')) return true;
  if (t.startsWith('looking at my')) return true;
  if (t.startsWith('however, i') || t.startsWith('wait, i')) return true;
  if (t.startsWith('i need to check') || t.startsWith('i should ')) {
    return true;
  }
  if (t.startsWith('this is asking') || t.startsWith('this falls under')) {
    return true;
  }
  if (t.startsWith('the request is')) return true;
  if (t.contains('i have the todo list')) return true;
  if (t.contains('the todos are:')) return true;
  return false;
}

bool waifuThinkingNoise(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return true;
  return t == 'thought' || t == 'thinking' || t == '...' || t == '…';
}

/// Victory speech, quotes, markdown — not CoT.
bool waifuLooksLikeSpoken(String raw) {
  final t = raw.trimLeft();
  if (t.isEmpty) return false;
  if (t.startsWith('"') || t.startsWith('*') || t.startsWith('#')) return true;
  if (t.startsWith('YES') || t.startsWith('Done')) return true;
  if (t.contains('Mission Accomplished')) return true;
  return false;
}

int? waifuSpokenLineOffset(String raw) {
  if (waifuLooksLikeSpoken(raw)) return 0;
  var start = 0;
  while (true) {
    final nl = raw.indexOf('\n', start);
    if (nl < 0) return null;
    final lineStart = nl + 1;
    if (waifuLooksLikeSpoken(raw.substring(lineStart))) return lineStart;
    start = lineStart;
  }
}

/// Planning dump vs the in-character porch line.
({String think, String speak}) waifuSplitAssistantBody(String raw) {
  if (raw.trim().isEmpty) return (think: '', speak: '');
  if (waifuLooksLikeSpoken(raw) && !waifuLooksLikeThinkingDump(raw)) {
    return (think: '', speak: raw);
  }
  if (!waifuLooksLikeThinkingDump(raw)) {
    return (think: '', speak: raw);
  }
  final cut = waifuSpokenLineOffset(raw);
  if (cut == null) return (think: raw, speak: '');
  if (cut == 0) return (think: '', speak: raw);
  return (think: raw.substring(0, cut), speak: raw.substring(cut));
}

/// Routes OpenCode text into Thought vs the spoken bubble.
class WaifuThinkGate {
  bool inContentDump = false;

  void resetTurn() => inContentDump = false;

  void noteTool({required bool pending}) {
    if (!pending) inContentDump = false;
  }

  WaifuMessage applyDelta(
    WaifuMessage cur,
    String delta, {
    required bool thinking,
  }) {
    if (delta.isEmpty) return cur;
    if (thinking && waifuThinkingNoise(delta)) return cur;
    if (waifuLooksLikeSpoken(delta)) {
      inContentDump = false;
      return cur.copyWith(text: '${cur.text}$delta');
    }
    if (thinking) {
      var next = '${cur.reasoning}$delta';
      if (cur.reasoning.isNotEmpty &&
          (delta.startsWith(cur.reasoning) ||
              cur.reasoning.startsWith(delta))) {
        next = delta.length >= cur.reasoning.length ? delta : cur.reasoning;
      }
      if (waifuThinkingNoise(next)) return cur;
      return cur.copyWith(
        reasoning: next,
        thinkingStartMs:
            cur.thinkingStartMs ?? DateTime.now().millisecondsSinceEpoch,
      );
    }
    final probe = '${cur.text}$delta';
    final dump =
        inContentDump ||
        waifuLooksLikeThinkingDump(delta) ||
        waifuLooksLikeThinkingDump(probe);
    if (!dump) return cur.copyWith(text: '${cur.text}$delta');
    inContentDump = true;
    final split = waifuSplitAssistantBody('${cur.text}$delta');
    if (split.speak.trim().isNotEmpty) inContentDump = false;
    return cur.copyWith(
      reasoning: '${cur.reasoning}${split.think}',
      text: split.speak,
      thinkingStartMs:
          cur.thinkingStartMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  WaifuMessage salvage(WaifuMessage cur) {
    final split = waifuSplitAssistantBody(cur.text);
    if (split.think.isEmpty) return cur;
    inContentDump = split.speak.trim().isEmpty;
    return cur.copyWith(
      reasoning: '${cur.reasoning}${split.think}',
      text: split.speak,
    );
  }
}
