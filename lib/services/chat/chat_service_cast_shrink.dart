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

/// The Realism scalars a cast changing shape carries: back into a 1:1 when
/// a group collapses to one member, and onto the host member when a 1:1
/// becomes a group. The rest of both moves is [CastCollapse]
/// (doors/cast/cast_collapse.dart). This part stays because
/// test/hygiene/realism_gate_ratchet_test.dart pins it to the three places
/// that read and write the chat's own Realism switch through a cast change.
extension ChatServiceCastShrink on ChatService {
  /// While still in group mode, capture the survivor's full state to carry
  /// back to the 1:1: the realism snapshot (gated on realism being on) PLUS
  /// the enable-flags, author note, pockets and chaos (carried regardless of
  /// realism). The returned call writes them into the 1:1 after it opens
  /// (opening the 1:1 reset them).
  void Function() _captureSurvivorScalars(String soleId) {
    final bool wasRealismOn = _realismChatSwitch;
    final bool wasNeedsOn = _needsSimEnabled;
    Map<String, dynamic>? snapshot;
    if (wasRealismOn) {
      _realismDance.loadIntoScalars(
        soleId,
      ); // loads the survivor's per-char nsfw flag too
      snapshot = _realismSnapshot.capture();
    }
    // The 1:1 chat keeps the switch the group chat showed for the survivor:
    // the group chat's own AND hers. A member's stored flag is a legacy
    // register no gate reads.
    final bool soleNsfwEnabled = _groupStore.afterglowOnFor(soleId);
    // Same reasoning for their Pockets record, and read here for the same reason:
    // step 4 re-enters as a 1:1, which clears _groupRealism. Carried regardless
    // of realism because Pockets does not depend on it — the pass is gated on
    // pocketsEnabled alone, so a survivor can be holding their keys with the
    // engine off. Dropping this is how a collapse would empty their hands.
    final Pockets? solePockets = _groupRealism[soleId]?.pockets;
    final bool soleChaosEnabled = _chaosModeService.chaosModeEnabled;
    final int soleChaosPressure = _chaosModeService.chaosPressure;
    final bool soleChaosNsfw = _chaosModeService.chaosNsfwEnabled;
    final String soleAuthorNote = _groupAuthorNotes[soleId] ?? '';
    final int soleAuthorStrength = _groupAuthorNoteStrengths[soleId] ?? 4;

    return () {
      // Seed, never setNsfwCooldownEnabled: its "off" zeroes Lust. First, so
      // the restore below reads the switch the 1:1 keeps.
      _nsfwService.seedFromV2OrExt(nsfwCooldownEnabled: soleNsfwEnabled);
      if (wasRealismOn && snapshot != null) {
        _realismChatSwitch = true;
        _needsSimEnabled = wasNeedsOn;
        _relationshipService.restoreFromMessageState(snapshot);
        _mood.restoreFromStamp(snapshot);
        _nsfwService.restoreNsfwFromMessageState(snapshot);
        _clockWriter.syncLoadedSlotClocks();
        if (wasNeedsOn) {
          final needs = snapshot['needs'];
          if (needs is Map && needs['vector'] is Map) {
            _needsSimulation.restoreFromSnapshot({
              'vector': Map<String, int>.from(needs['vector'] as Map),
            });
          } else {
            _needsSimulation.initializeFresh();
          }
        } else {
          _needsSimulation.clearVector();
        }
      }

      // Enable-flags + author note (persisted by _doSaveChat below) — carry
      // regardless of realism so the NSFW toggle, passage-of-time, chaos, and the
      // note are not reset to defaults on collapse.
      _pockets = solePockets;
      _chaosModeService.loadScalars(
        modeEnabled: soleChaosEnabled,
        pressure: soleChaosPressure,
        nsfwEnabled: soleChaosNsfw,
      );
      _authorNote = soleAuthorNote;
      _authorNoteStrength = soleAuthorStrength;
    };
  }

  /// Carry captured 1:1 [state] onto the host member [hostId]: realism
  /// values only if realism was on; flags, Afterglow, chaos, pockets and the
  /// author note regardless.
  void _carryHostScalarsIntoMember(String hostId, Map<String, dynamic> state) {
    final realismOn = state['realismOn'] as bool? ?? false;
    final needsEnabled = state['needsSimEnabled'] as bool? ?? false;
    _needsSimEnabled = needsEnabled;

    // Realism VALUES (gated on realism being on at fork time): relationship +
    // emotion + nsfw + time via the regenerate restore path, then the canonical
    // _groupRealism write for the host member.
    if (realismOn) {
      _realismChatSwitch = true;
      _relationshipService.restoreFromMessageState(state);
      _mood.restoreFromStamp(state);
      _nsfwService.restoreNsfwFromMessageState(state);
      _clockWriter.syncLoadedSlotClocks();
      if (needsEnabled) {
        final needs = state['needs'];
        if (needs is Map && needs['vector'] is Map) {
          _needsSimulation.restoreFromSnapshot({
            'vector': Map<String, int>.from(needs['vector'] as Map),
          });
        } else {
          _needsSimulation.initializeFresh();
        }
      } else {
        _needsSimulation.clearVector();
      }
      _realismDance.saveScalarsIntoGroup(hostId);
    }

    // Enable-flags (independent of realism; persist via _doSaveChat columns in
    // both modes) + author note + evolution + objectives carry REGARDLESS.
    // The host's own Afterglow flag also goes on the host MEMBER, realism or
    // not: in a group the chat-level register is per-speaker state, so a value
    // left only there is gone after the first group reply.
    final hostNsfw = state['nsfwCooldownEnabled'] as bool? ?? false;
    _nsfwService.seedFromV2OrExt(nsfwCooldownEnabled: hostNsfw);
    _groupStore.memberForWrite(hostId).nsfwCooldownEnabled = hostNsfw;
    // The group chat takes the 1:1 chat's Afterglow switch.
    _groupStore.afterglowOn = hostNsfw;
    _chaosModeService.loadScalars(
      modeEnabled: state['chaosModeEnabled'] as bool? ?? false,
      pressure: state['chaosPressure'] as int? ?? 0,
      nsfwEnabled: state['chaosNsfwEnabled'] as bool?,
    );

    // Live pockets, regardless of realism — collapse writes `_pockets =
    // solePockets`; this is the inverse. setActiveGroup cleared the 1:1
    // scalar; plant the captured kit on the host member.
    final pocketsJson = state['pockets'];
    if (pocketsJson is Map) {
      setPocketsFor(
        hostId,
        Pockets.fromJson(Map<String, dynamic>.from(pocketsJson)),
      );
    }

    // Author note -> the host member's per-character group note (serialized into
    // group_realism_state by _saveChat).
    final note = state['authorNote'] as String? ?? '';
    if (note.isNotEmpty) {
      _groupAuthorNotes[hostId] = note;
      _groupAuthorNoteStrengths[hostId] =
          state['authorNoteStrength'] as int? ?? 4;
    }
  }
}

/// The cast door's state and behaviour under the names the rest of this
/// library still uses. Each line is debt its caller's package retires by
/// calling [ChatService.castDoor] itself (WP5, WP7 to WP10).
extension _ChatServiceCastNames on ChatService {
  SceneGuestState get _sceneGuest => castDoor.guests.state;
  AwayPulseState get _awayPulse => castDoor.away.state;
  DirectorScene get _directorScene => castDoor.directorScene;
  bool get _narrating => castDoor.narrating;
  String? get _entranceDirective => castDoor.entranceDirective;
  set _entranceDirective(String? v) => castDoor.entranceDirective = v;
  set _stoppedReplyAnchor(ChatMessage? v) =>
      castDoor.guests.stoppedReplyAnchor = v;
  set _greetingIndex(int v) => castDoor.greetings.greetingIndex = v;
  int get _greetingIndex => castDoor.greetings.greetingIndex;
  bool get _greetingEvalPending => castDoor.baseline.greetingEvalPending;
  bool get _isProcessingGreeting => castDoor.baseline.isProcessingGreeting;
  set _isProcessingGreeting(bool v) =>
      castDoor.baseline.isProcessingGreeting = v;
  String? get _pendingIdleCue => castDoor.idle.pendingIdleCue;
  set _pendingIdleCue(String? v) => castDoor.idle.pendingIdleCue = v;
  bool get _autoResponseInProgress => castDoor.idle.autoResponseInProgress;
  set _hasCompletedExchange(bool v) => castDoor.idle.hasCompletedExchange = v;
  int get _consecutiveAutoResponses => castDoor.idle.consecutiveAutoResponses;
  set _consecutiveAutoResponses(int v) =>
      castDoor.idle.consecutiveAutoResponses = v;

  bool _sceneChanged(String? token) => castDoor.sceneChanged(token);
  void _setGuestStatus(
    String? msg, {
    bool isError = false,
    bool sticky = false,
  }) => castDoor.guests.setStatus(msg, isError: isError, sticky: sticky);
  void _noteStoppedReply({required bool replyKept}) =>
      castDoor.guests.noteStoppedReply(replyKept: replyKept);
  void _clearExitUndo() => castDoor.guests.clearExitUndo();
  bool _isGuestAuthoredMessage(ChatMessage m) =>
      castDoor.guests.isGuestAuthoredMessage(m);
  CharacterCard? _sceneGuestForMessage(ChatMessage m) =>
      castDoor.guests.sceneGuestForMessage(m);
  CharacterCard? _directAddressRoutedGuest(String promptText) =>
      castDoor.guests.directAddressRoutedGuest(promptText);
  Future<void> _resolveSceneGuestCards() =>
      castDoor.guests.resolveSceneGuestCards();
  Future<void> _addGuestWithStatus({
    required String displayName,
    CharacterCard? existing,
    Future<GuestMintResult> Function(void Function(String step) onStatus)? mint,
  }) => castDoor.guests.addGuestWithStatus(
    displayName: displayName,
    existing: existing,
    mint: mint,
  );
  Future<GuestMintResult> _mintSceneGuest(
    String name,
    String concept, {
    void Function(String step)? onStatus,
  }) => castDoor.joins.mintSceneGuest(name, concept, onStatus: onStatus);

  Future<void> _commitPendingMemberExit() =>
      castDoor.roster.commitPendingMemberExit();
  bool _speakerIsSoft(CharacterCard speaker) =>
      castDoor.roster.speakerIsSoft(speaker);
  Future<bool> _bridgeLongSkip({
    required DateTime from,
    required int skipped,
    required ChatMessage skipLine,
    required String? token,
  }) => castDoor.stage.bridgeLongSkip(
    from: from,
    skipped: skipped,
    skipLine: skipLine,
    token: token,
  );

  Future<void> _seedOpeningPosture() => castDoor.baseline.seedOpeningPosture();
  Future<void> _runPostGreetingEval() =>
      castDoor.baseline.runPostGreetingEval();
  Future<void> _runRetroactiveBaselineEval() =>
      castDoor.baseline.runRetroactiveBaselineEval();
  Future<void> _invalidateGreetingEval() =>
      castDoor.greetings.invalidateGreetingEval();
  String _buildFirstMessage(CharacterCard character, {String? greetingText}) =>
      castDoor.greetings.buildFirstMessage(
        character,
        greetingText: greetingText,
      );
  CharacterCard? _greetingOwnerCard() => castDoor.greetings.greetingOwnerCard();
  bool get _isOpeningGreetingChat => castDoor.greetings.isOpeningGreetingChat;
  Future<void> _applyGreetingOpeningSeed({
    required CharacterCard card,
    required int index,
    bool scheduleEval = true,
  }) => castDoor.greetings.applyGreetingOpeningSeed(
    card: card,
    index: index,
    scheduleEval: scheduleEval,
  );
  Future<void> _applyGroupCustomGreetingSeed(
    int index, {
    bool scheduleEval = true,
  }) => castDoor.greetings.applyGroupCustomGreetingSeed(
    index,
    scheduleEval: scheduleEval,
  );
  void _stampGreetingIndex(int index) =>
      castDoor.greetings.stampGreetingIndex(index);

  Future<void> _runAwayPulse({
    required String userText,
    required bool fromUserSend,
  }) => castDoor.away.runAwayPulse(
    userText: userText,
    fromUserSend: fromUserSend,
  );
  void _releaseHeldAway(CharacterCard card) =>
      castDoor.away.releaseHeldAway(card);
  void _resetIdleTimer() => castDoor.idle.resetIdleTimer();
  void _cancelIdleTimer() => castDoor.idle.cancelIdleTimer();
}
