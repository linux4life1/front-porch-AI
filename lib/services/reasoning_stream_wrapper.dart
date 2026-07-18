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

/// Wraps an OpenAI-style split reasoning stream (`reasoning_content` /
/// `reasoning` deltas separate from `content` deltas) back into the inline
/// `<think>…</think>` framing the rest of the app understands — the single
/// format both the desktop bubble ("Thought for Xs") and the web UI
/// ("💭 Thoughts") already parse out of the content token stream.
///
/// This is the one shared implementation for BOTH OpenAI-chat transports:
/// [streamOpenAiChat] (local KoboldCpp, once launched with `--jinja` so the
/// model's template splits its thinking into `reasoning_content`) and
/// OpenRouterService (remote / oMLX). Keeping it in one place is why the two
/// differently-shaped SSE loops can't drift apart.
///
/// It is a tiny, pure state machine (no I/O): feed it each reasoning delta via
/// [onReasoning] and each content delta via [onContent], call [finish] once at
/// end of stream, and yield whatever non-empty string each call returns.
///
/// [wrap] is supplied by the caller because the two transports decide
/// "is thinking wanted?" differently (Kobold uses `reasoningEnabled &&
/// reasoningMaxTokens != 0`; OpenRouter uses bare `reasoningEnabled` and relies
/// on its own request-side suppression object). When [wrap] is false, reasoning
/// deltas are DISCARDED rather than shown — so an off toggle (or the Continue /
/// eval suppress path) never leaks stray reasoning into the visible reply,
/// matching the long-standing SillyTavern-style behavior.
class ReasoningTagWrapper {
  ReasoningTagWrapper({required this.wrap});

  /// Whether reasoning should be surfaced (wrapped in `<think>…</think>`) or
  /// discarded entirely.
  final bool wrap;

  /// True while a `<think>` block is open (emitted, not yet closed).
  bool _open = false;

  /// Handle a `reasoning`/`reasoning_content` delta. Returns the text to yield
  /// (empty string = yield nothing): opens a `<think>` block on the first
  /// reasoning delta (or re-opens one if a prior block was already closed by
  /// content — so late/interleaved reasoning is never leaked as visible reply
  /// text), and passes subsequent deltas of the open block through raw.
  /// Discards entirely when [wrap] is off.
  String onReasoning(String delta) {
    if (!wrap || delta.isEmpty) return '';
    if (_open) return delta;
    _open = true;
    return '<think>$delta';
  }

  /// Handle a regular `content` delta. Returns the text to yield, first closing
  /// an open reasoning block with `</think>\n` so the reply renders after it.
  String onContent(String delta) {
    if (delta.isEmpty) return '';
    if (_open) {
      _open = false;
      return '</think>\n$delta';
    }
    return delta;
  }

  /// Call once when the stream ends. Returns `</think>\n` if a reasoning block
  /// is still open (reasoning-only response), else empty. Idempotent.
  String finish() {
    if (_open) {
      _open = false;
      return '</think>\n';
    }
    return '';
  }
}
