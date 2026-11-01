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

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// The promise ledger: the post-reply commitment pass and the diary's
/// manual "Mark kept / broken".
class PromiseLedger {
  PromiseLedger(this._e);

  final TurnEngine _e;

  TurnDeps get _d => _e.deps;
  ChatSessionState get _session => _d.session;
  RealismGraph get _g => _d.doors.graph();
  SessionStore get _sessions => _d.doors.sessions();
  StorageService get _storageService => _d.services.storage;
  UserPersonaService get _userPersonaService => _d.services.personas;
  String _getCharacterIdFromCard(CharacterCard card) =>
      _session.characterIdFor(card);

  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  GroupRealismStore get _groupStore => _g.groups;
  SessionHistoryWindow get _history => _sessions.history;
  PromiseDebtService get _promiseDebtService => _g.promiseDebt;
  RealismDance get _realismDance => _g.dance;
  Future<void> _saveChat({bool replaceAll = false}) =>
      _sessions.save(replaceAll: replaceAll);
  TimeService get _timeService => _g.time;

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
    if (_e.isTurnBusy) return false;
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
  void maybeRunPromiseDebtPass() {
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
