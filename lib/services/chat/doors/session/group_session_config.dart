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

/// A group chat's per-member settings that ride the session's
/// `group_realism_state` blob: Author's Notes, system prompts and the RAG
/// knobs. Keyed by stable member id. The session store loads and saves
/// them with the chat; Group Settings and the prompt read them live.
class GroupSessionConfig {
  /// Per-character Author's Notes for group chats (independent of the
  /// chat-level note). Keyed by stable charId.
  Map<String, String> authorNotes = {};
  Map<String, int> authorNoteStrengths = {};

  /// Per-character system prompts scoped to the *current group only*,
  /// independent of each character's card prompt. When present and
  /// non-empty for the speaking character they take full precedence.
  Map<String, String> characterSystemPrompts = {};

  // RAG settings for the active group.
  bool ragEnabled = true;
  int retrievalCount = 4;
  double memoryBudgetPercent = 10.0;
  Map<String, double> characterRAGPriorities = {};
}
