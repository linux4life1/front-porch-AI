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

/// Approach A′ soft members on the turn path. Roster, promote and the soft
/// member's entrance are [CastController] (doors/cast/cast_controller.dart).
/// What stays: the two checks that take the library-private turn record
/// `_GenTurn` (the turn engine's, WP10b), and the promoted member's bars,
/// which test/hygiene/needs_gate_ratchet_test.dart pins to this file. The
/// entry door (doors/entry/) is wired below, beside the group roster names
/// other parts still reach it by.
extension ChatServiceGroupLite on ChatService {
  /// 1:1 guest turn **or** a soft group member speaking. Do not set
  /// `guestSpeaker` for the latter — that skip would drop Away / pick.
  bool _isLiteTurn(_GenTurn t) =>
      t.guestSpeaker != null || _speakerIsSoft(t.speakingCharacter);

  /// After the clock commits; body in [AfterglowPass.tickAfterClock]. A lite
  /// beat (guest or soft member) has no speaker refractory to open.
  void _tickRefractoryAfterClock(_GenTurn t) => _afterglow.tickAfterClock(
    t.mode,
    speakerIdOf: () =>
        _isLiteTurn(t) ? null : _getCharacterIdFromCard(t.speakingCharacter),
    reply: () => t.streamTarget,
  );

  /// A soft member who becomes full gets a full member's bars (only when
  /// the chat keeps Needs state and they have none yet).
  void _seedPromotedNeeds(String mid, FrontPorchExtensions? cleared) {
    if (_needsSimEnabled &&
        mid.isNotEmpty &&
        _groupStore.needsOf(mid).isEmpty) {
      _groupStore.setNeeds(
        mid,
        NeedsSimulation.baselinesFromExtensions(cleared),
      );
    }
  }
}

/// Builds the entry door. Each hook is debt (see [EntryShellHooks]); the
/// shared hooks are the session store's own ([_sessionHooks]).
extension ChatServiceEntryWiring on ChatService {
  EntryDoor _buildEntryDoor() => EntryDoor(
    EntryDeps(
      session: _session,
      sessions: () => sessionStore,
      services: EntryServices(
        db: () => _db,
        storage: _storageService,
        personas: _userPersonaService,
        worlds: _worldRepository,
        macros: _macroResolver,
        characters: () => _characterRepository,
        llmProvider: () => _llmProvider,
        realism: _realismScope,
        snapshot: () => _realismSnapshot,
        mood: () => _mood,
        chaos: () => _chaosModeService,
        needsPass: () => _needsPass,
        expression: () => _expressionService,
        lorebook: () => _lorebookScanner,
        clockWriter: () => _clockWriter,
        growthDesk: () => _growthDesk,
        birthdays: () => _birthdaySync,
        cast: () => castDoor,
        objectives: () => objectivesDoor,
        media: () => mediaDoor,
        sceneMoves: _sceneMoves,
      ),
      hooks: EntryShellHooks(
        isTurnBusy: () => _isTurnBusy,
        bumpGenerationEpoch: () => _generationEpoch++,
        generate: () => _generateResponse(GenerationMode.normal),
        skipAsked: () => _skipAsked,
        upcomingSpeaker: () => _upcomingGroupSpeaker,
        refreshEnjoysLowHygiene: refreshEnjoysLowHygieneFromActiveCharacter,
        persistMemberExtensions: (id) =>
            persistGroupMemberExtensions(memberId: id),
        chatPlaceSlots: () => _chatPlaceSlots,
      ),
      shared: _sessionHooks(),
      notify: notifyListeners,
    ),
  );
}

/// The entry door's state and behaviour under the names the rest of this
/// library still uses. Each line is debt its caller's package retires by
/// calling [ChatService.entryDoor] itself (WP9a to WP10c).
extension _ChatServiceEntryNames on ChatService {
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  bool get _observerMode => entryDoor.director.observerMode;
  bool get _directing => entryDoor.director.directing;
  bool get _autoPlayActive => entryDoor.director.autoPlayActive;
  bool get _shouldTrackInterCharacterRelationships =>
      entryDoor.reads.shouldTrackInterCharacterRelationships;
  bool get _entrancesInFlight => entryDoor.entrancesInFlight;
  AutoChatBudget get _autoChatBudget => entryDoor.autoChat;
  GroupChatRepository? get _groupChatRepository => entryDoor.groupRepository;
  set _groupChatRepository(GroupChatRepository? repo) =>
      entryDoor.groupRepository = repo;

  Future<void> _waitForTurnToSettle() => entryDoor.cover.waitForTurnToSettle();
  Future<void> _autoPlayNext() => entryDoor.director.autoPlayNext();
  bool _autoChatPausesAfter(ChatMessage reply) =>
      entryDoor.director.autoChatPausesAfter(reply);
}
