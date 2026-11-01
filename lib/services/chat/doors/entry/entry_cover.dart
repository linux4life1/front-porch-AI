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

import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';

import 'entry_deps.dart';

/// What every entry does around the switch: the chat page's loading cover,
/// and the wait for a finishing turn to settle before rows are re-read.
class EntryCover {
  EntryCover(this._d);

  final EntryDeps _d;

  SessionStore get _store => _d.sessions();

  /// Raise the ChatPage overlay before any await so a navigate-first open
  /// never paints the previous transcript. No-op when a caller (home tap,
  /// startFreshChatWith) already owns the flag for a multi-step load.
  void beginSessionLoad() {
    if (_store.isLoadingSession) return;
    _store.isLoadingSession = true;
    _d.notify();
  }

  /// Drop the overlay. Safe to call when the flag is already false.
  void endSessionLoad() {
    if (!_store.isLoadingSession) return;
    _store.isLoadingSession = false;
    _d.notify();
  }

  /// Wait (bounded) for a finishing turn's settling section to complete.
  ///
  /// `_cancelAndWaitForGeneration` stops the STREAM, but the post-gen work —
  /// evals, chip attach, `_saveChat` — runs after `_isGenerating` drops.
  /// Entering a session/character/group mid-settle rehydrates from rows the
  /// persist hasn't written yet (the reloaded reply came back chip-less, so
  /// deleting it refunded nothing — the app_smoke Windows CI catch) while
  /// the finalization keeps writing onto the REPLACED list. Bounded so a
  /// wedged backend degrades to the old racy behaviour instead of hanging
  /// the UI (`_cancelAndWaitForGeneration`'s doc forbids broadening its own
  /// unbounded spin for exactly that reason).
  Future<void> waitForTurnToSettle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    // A send parked on "Did time pass?" has written only its line; the
    // switch cancels the question and the send stops on the chat change.
    while (_d.services.turn().isTurnBusy &&
        !_d.hooks.skipAsked() &&
        DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    // Persist is not `_isTurnBusy`: `_isPostGenerating` drops in
    // `_generateResponse`'s finally, and fire-and-forget `_saveChat()` calls
    // can still be on `_saveChain`. A reload that does not wait here hydrates
    // the pre-turn row and a later write can then persist that shorter list.
    await _store.saveChain;
  }
}
