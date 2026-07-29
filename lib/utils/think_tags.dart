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

/// Strips reasoning-model think tags from user-visible prose (TTS input,
/// emotion classification, etc.).
///
/// Handles the three leak shapes seen in the wild: complete
/// `<think>...</think>` blocks, an unclosed `<think>` prefix running to the
/// end (mid-stream text), and a bare orphan `</think>` left behind when the
/// transport consumed the opening tag. For orphan closing tags only the tag
/// itself is removed — wiping preceding prose would blank a legit message on
/// a stray token.
///
/// Distinct from LlmEvalEngine.stripThinkBlocks, which is eval-plumbing with
/// its own budget semantics; this one is for message text shown/spoken to
/// the user.
String stripThinkTags(String text) {
  return text
      .replaceAll(
        RegExp(r'<think>.*?</think>', caseSensitive: false, dotAll: true),
        '',
      )
      .replaceAll(RegExp(r'<think>.*$', caseSensitive: false, dotAll: true), '')
      .replaceAll(RegExp(r'</think>\s*', caseSensitive: false), '')
      .trim();
}

/// Split of a stored message into editable [thinking] + [body] parts.
///
/// Thinking is the inner content of the first complete `<think>...</think>`
/// block (or the unclosed open-to-end prefix during mid-stream leftovers).
/// Body is everything outside that block. No tags appear in either field —
/// the editor UI should never show raw `<think>` markup to the user.
typedef MessageEditParts = ({String thinking, String body});

/// Pulls thinking and body out of a stored message string for the editor.
MessageEditParts splitMessageForEdit(String text) {
  final closed = RegExp(
    r'<think>([\s\S]*?)</think>\s*',
    caseSensitive: false,
  ).firstMatch(text);
  if (closed != null) {
    final thinking = (closed.group(1) ?? '').trim();
    final body = (text.substring(0, closed.start) + text.substring(closed.end));
    return (thinking: thinking, body: body);
  }
  final open = RegExp(
    r'<think>([\s\S]*)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (open != null) {
    final thinking = (open.group(1) ?? '').trim();
    final body = text.substring(0, open.start);
    return (thinking: thinking, body: body);
  }
  // Orphan closing tag only — strip the tag, keep surrounding prose as body.
  final orphanClose = RegExp(r'</think>\s*', caseSensitive: false);
  if (orphanClose.hasMatch(text)) {
    return (thinking: '', body: text.replaceAll(orphanClose, ''));
  }
  return (thinking: '', body: text);
}

/// Reassemble editor fields into the stored message format.
///
/// Empty thinking yields body alone (no empty think wrapper). Non-empty
/// thinking is wrapped as `<think>\n...\n</think>\n` before the body so the
/// existing bubble "Thought" chip and strip-for-display paths keep working.
String joinMessageEdit({required String thinking, required String body}) {
  final t = thinking.trim();
  if (t.isEmpty) return body;
  final prefix = '<think>\n$t\n</think>\n';
  return body.isEmpty ? prefix.trimRight() : '$prefix$body';
}
