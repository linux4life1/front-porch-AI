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
      if (mode == GenerationMode.continue_ && _session.messages.isNotEmpty) {
        final last = _session.messages.last;
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

/// The promise ledger: the post-reply commitment pass and the diary's
/// manual "Mark kept / broken".
extension ChatServicePromiseLedger on ChatService {
  /// Manual "Mark kept / broken" from the diary's Promises tab (desktop) and
  /// the web Promises panel. Same applier as automatic detection — the
  /// trust/bond effects apply too, restoring what a missed detection should
  /// have done.
  Future<bool> resolvePromiseManually({
    required String characterId,
    required String cardId,
    required bool kept,
  }) async {
    final sessionId = _session.currentSessionId;
    if (sessionId == null) return false;
    // Never mid-turn: the scalar dance below would fight the active
    // speaker's own load/save.
    if (_isTurnBusy) return false;
    // Group parity: the service's trust/bond callbacks land on whichever
    // member's scalars are LOADED. Manual resolution can come from any
    // member's diary at any time, so run the same load → apply → save
    // dance the post-gen checks use, scoped to that member.
    final isGroupMember =
        _activeGroup != null &&
        _groupCharacters.any((c) => _getCharacterIdFromCard(c) == characterId);
    if (isGroupMember) _realismDance.loadIntoScalars(characterId);
    final ok = await _promiseDebtService.resolveManually(
      sessionId: sessionId,
      characterId: characterId,
      cardId: cardId,
      kept: kept,
      storyDay: _timeService.dayCount,
      storyClock: _timeService.storyClockIso,
    );
    if (isGroupMember) _realismDance.saveScalarsIntoGroup(characterId);
    if (ok) await _saveChat();
    return ok;
  }

  /// Train B — promise/debt ledger pass (fire-and-forget). Detects new
  /// commitments or kept/broken resolutions for the current speaker's diary.
  /// Gated on the Journal and its own switch, NOT on the Realism Engine. It
  /// used to require realism, but nothing here consumes realism state: the pass
  /// reads the recent exchange text and writes a journal card. The story day
  /// and clock it stamps are nullable and nothing reads them back, so a frozen
  /// clock costs nothing. The Journal genuinely is required — a commitment IS a
  /// journal card — and the separate switch exists because this is one extra
  /// model call per reply, which a user who turned realism off to save calls
  /// deserves to opt into rather than inherit.
  void _maybeRunPromiseDebtPass() {
    if (!_storageService.realismSettings.promiseLedgerEnabled) return;
    if (!_storageService.memorySettings.journalEnabled) return;
    final sessionId = _session.currentSessionId;
    if (sessionId == null) return;
    final charId = _groupStore.currentSpeakerId();
    if (charId.isEmpty) return;

    String characterName = _session.activeCharacter?.name ?? 'the character';
    if (_activeGroup != null) {
      final card = _groupCharacters
          .where((c) => _getCharacterIdFromCard(c) == charId)
          .firstOrNull;
      if (card != null) characterName = card.name;
    }

    // 6, not the judges' 4: a promise often spans a couple of exchanges
    // (missed KEPT if it scrolls out — 2026-08-04). recentExchange is the
    // one window builder (clamp, photo markers, think-strip).
    final recent = recentExchange(_session.messages, take: 6);
    if (recent.trim().isEmpty) return;

    unawaited(
      _promiseDebtService.evaluateTurn(
        sessionId: sessionId,
        characterId: charId,
        characterName: characterName,
        userName: _userPersonaService.persona.name,
        recentExchange: recent,
        receiptPosition: persistTipCite(
          base: _history.basePosition,
          length: _session.messages.length,
        ).firstOrNull,
        storyDay: _timeService.dayCount,
        storyClock: _timeService.storyClockIso,
      ),
    );
  }
}
