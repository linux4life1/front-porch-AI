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

part of '../chat_service.dart';

/// Turn admission for `_generateResponse`: the checks between raising
/// `_isGenerating` and the turn's own try/finally.
extension ChatServiceGenerationEntry on ChatService {
  /// The speakers to run the turn with, or null when it may not run: the
  /// backend is down, or a Continue whose speaker has left or is unclear.
  ///
  /// Every refusal (and a throw) leaves through the one `finally`, which
  /// ends the turn that never ran. A refusal that only returned left the
  /// flag up: Send then did nothing and a chat switch waited forever.
  Future<({CharacterCard? guest, CharacterCard? force})?> _admitTurn(
    GenerationMode mode,
    CharacterCard? guestSpeaker,
    CharacterCard? forceSpeaker,
  ) async {
    var admitted = false;
    try {
      if (await _abortIfBackendDown()) return null;
      // Continue is regen's sibling for WHO is speaking. Infer guest / group
      // member from the bubble; refuse rather than guess.
      if (mode == GenerationMode.continue_ && _messages.isNotEmpty) {
        final last = _messages.last;
        guestSpeaker ??= _sceneGuestForMessage(last);
        if (guestSpeaker == null && _isGuestAuthoredMessage(last)) {
          _setGuestStatus(
            'Can’t continue "${last.sender}" — they have left the scene.',
            isError: true,
          );
          return null;
        }
        if (guestSpeaker == null && _activeGroup != null) {
          forceSpeaker ??= _resolveGroupSpeakerForMessage(last);
          if (forceSpeaker == null) {
            _setGuestStatus(
              'Can’t continue "${last.sender}" — who said it is ambiguous.',
              isError: true,
            );
            return null;
          }
        }
      }
      admitted = true;
      return (guest: guestSpeaker, force: forceSpeaker);
    } finally {
      if (!admitted) {
        // No turn will run — terminate BOTH live streams. The sentence
        // stream has no error sentinel: `call_overlay` closes its controller
        // on '__DONE__' alone, and `TtsService.speakStreaming` blocks in
        // `await for` until that close, so a silent bail freezes a voice call
        // on "Thinking…" with the mic never re-armed. The phone's chat ends
        // its pending reply on the token sentinel.
        _tokenBroadcast.add('__ERROR__');
        _sentenceBroadcast.add('__DONE__');
        _isGenerating = false;
        notifyListeners();
      }
    }
  }
}
