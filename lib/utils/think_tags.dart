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
