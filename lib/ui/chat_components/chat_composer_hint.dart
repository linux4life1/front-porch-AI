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

/// User-facing chat-composer placeholder strings (the repo has no ARB/l10n
/// codegen — named constants here are the existing pattern).
const kNoApiConnectionHint = 'No API connection';
const kTypeAMessageHint = 'Type a message...';
const kDirectTheSceneHint = 'Direct the scene...';

/// Placeholder for the chat input. Connection state wins: a down backend
/// must never leave the normal "type a message" hint in place, and a
/// recovered connection must never leave the error hint stale.
///
/// [apiReady] is the *connection* flag ([LLMProvider.composerConnectionReady])
/// — configured / process up. Local GGUF-ready is not this (swaps would
/// flash the input). A one-off HTTP 500 on a live backend is not this.
String chatComposerHint({required bool apiReady, required bool observerMode}) {
  if (!apiReady) return kNoApiConnectionHint;
  if (observerMode) return kDirectTheSceneHint;
  return kTypeAMessageHint;
}
