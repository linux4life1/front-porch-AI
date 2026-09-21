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

bool waifuThinkingNoise(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return true;
  return t == 'thought' || t == 'thinking' || t == '...' || t == '…';
}

/// Coding pass text is Thought. Only the voice plugin pass is speech.
bool waifuDeltaGoesToThought({
  required bool voicePass,
  required bool thinking,
}) => thinking || !voicePass;

/// Append OpenCode deltas. No dump regex — phase decides the channel.
class WaifuThinkGate {
  WaifuMessage applyDelta(
    WaifuMessage cur,
    String delta, {
    required bool thinking,
  }) {
    if (delta.isEmpty) return cur;
    if (thinking && waifuThinkingNoise(delta)) return cur;
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
    return cur.copyWith(text: '${cur.text}$delta');
  }
}
