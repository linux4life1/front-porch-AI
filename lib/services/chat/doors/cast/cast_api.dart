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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';

export 'package:front_porch_ai/services/chat/doors/cast/cast_controller.dart'
    show kDirectorCastFloorNote;

/// The cast's old names on [ChatService]. Every body only calls
/// [ChatService.castDoor]; the shell exports this library so callers keep
/// their imports.
extension ChatServiceCastApi on ChatService {
  // ── Roster, exits, Director Mode ──────────────────────────────────────

  /// Full members only (feelings, the four-member gate).
  List<CharacterCard> get fullGroupRoster => castDoor.roster.fullGroupRoster;
  bool get canRemoveCastMember => castDoor.roster.canRemoveCastMember;

  /// `/exit <name>` for a full member: narrated goodbye, deferred removal,
  /// UNDO until the user continues.
  Future<bool> exitGroupMember(
    CharacterCard member,
    GroupChatRepository groupRepo,
  ) => castDoor.roster.exitGroupMember(member, groupRepo);

  Future<void> promoteGuestToFull(CharacterCard member) =>
      castDoor.roster.promoteGuestToFull(member);

  Future<bool> stepUserOffStage() => castDoor.stage.stepUserOffStage();
  Future<bool> stepUserOnStage() => castDoor.stage.stepUserOnStage();
  String get directorGoal => castDoor.stage.directorGoal;
  Map<String, String> get directorWhispers => castDoor.stage.directorWhispers;
  List<({String id, String name, String text})> get directorWhisperRows =>
      castDoor.stage.directorWhisperRows;
  Future<void> setDirectorGoal(String text) =>
      castDoor.stage.setDirectorGoal(text);
  Future<void> setDirectorWhisper(String memberId, String text) =>
      castDoor.stage.setDirectorWhisper(memberId, text);

  /// The narrator is writing a beat (a turn in all but name).
  bool get isNarrating => castDoor.narrating;
  Future<bool> narrateScene(String hint) => castDoor.stage.narrateScene(hint);

  // ── Scene Guests ──────────────────────────────────────────────────────

  bool get autoChimeEnabled => castDoor.guests.autoChimeEnabled;
  set autoChimeEnabled(bool value) => castDoor.guests.autoChimeEnabled = value;

  String? get stoppedReplyNotice => castDoor.guests.stoppedReplyNotice;
  bool get canRetryStoppedReply => castDoor.guests.canRetryStoppedReply;
  void dismissStoppedReplyNotice() =>
      castDoor.guests.dismissStoppedReplyNotice();

  Future<void> speakGuestNow(CharacterCard guest) =>
      castDoor.guests.speakGuestNow(guest);
  Future<void> generateGuestTurn(CharacterCard guest) =>
      castDoor.guests.generateGuestTurn(guest);

  /// The persistent Scene Guests in this 1:1 scene (resolved cards).
  List<CharacterCard> get sceneGuestCards =>
      List.unmodifiable(castDoor.guests.state.cards);

  /// Initial filter for a pending `/join` picker, or null when none.
  String? get pendingGuestPickerFilter =>
      castDoor.guests.state.pendingPickerFilter;

  /// The pending picker adds a FULL member (group member / 1:1 to group)
  /// rather than a lite Scene Guest.
  bool get pendingGuestPickerFull => castDoor.guests.state.pendingPickerFull;

  /// Transient Scene Guest create/join status line (null when idle).
  String? get guestActivityStatus => castDoor.guests.state.activityStatus;
  bool get guestActivityIsError => castDoor.guests.state.activityIsError;

  /// A Scene Guest is being created or entered (input is disabled).
  bool get isGuestBusy => castDoor.guests.state.busy;

  /// A guest card image path the UI should evict (then call
  /// [consumeGuestAvatarEvict]); null when there is nothing to refresh.
  String? get guestAvatarEvictPath => castDoor.guests.state.avatarEvictPath;
  void consumeGuestAvatarEvict() =>
      castDoor.guests.state.avatarEvictPath = null;

  /// Name to show in the UNDO SnackBar (null = nothing to offer).
  String? get exitUndoOfferName => castDoor.guests.state.exitUndoOfferName;

  /// Who the open `/exit` undo would bring back, until it closes. Unlike
  /// [exitUndoOfferName] nothing consumes it, so the web shows its own UNDO.
  String? get exitUndoName => castDoor.guests.state.exitUndoName;

  /// The open undo is the user's own step out to direct.
  bool get exitUndoIsUserStep => castDoor.guests.state.exitUndoUserStep;

  /// Consume the one-shot UNDO offer; the undo stays available through
  /// [undoLastExit] until invalidated.
  void consumeExitUndoOffer() => castDoor.guests.state.exitUndoOfferName = null;

  /// The detected-cast candidate the popup shows (null = nothing pending).
  DetectedCharacter? get pendingGuestDetection =>
      castDoor.guests.state.pendingDetection;

  void armSceneGuestExitUndo(CharacterCard guest) =>
      castDoor.guests.armExitUndo(guest);
  Future<void> undoLastExit() => castDoor.joins.undoLastExit();
  List<CharacterCard> get joinableGuestCharacters =>
      castDoor.joins.joinableGuestCharacters;
  List<CharacterCard> get joinableGroupCharacters =>
      castDoor.joins.joinableGroupCharacters;
  Future<void> joinSceneGuest(CharacterCard card) =>
      castDoor.joins.joinSceneGuest(card);
  Future<void> joinFull(CharacterCard card) => castDoor.joins.joinFull(card);
  Future<void> promoteSceneToFull() => castDoor.joins.promoteSceneToFull();
  void dismissGuestPicker() => castDoor.joins.dismissGuestPicker();
  Future<void> acceptDetectedGuest() => castDoor.joins.acceptDetectedGuest();
  void dismissDetectedGuest() => castDoor.joins.dismissDetectedGuest();

  // ── Greetings, Away, idle turns ───────────────────────────────────────

  /// Cycle the opening bubble through the alternate greetings.
  Future<void> cycleGreeting(int direction) =>
      castDoor.greetings.cycleGreeting(direction);

  /// Where a group member is right now (the turn picker's read); null
  /// outside a group or for an id not in the roster.
  PresenceWhere? groupMemberPresence(String memberId) =>
      castDoor.away.groupMemberPresence(memberId);

  /// The user's own Away / Back for one group member.
  Future<bool> setGroupMemberAway(String memberId, {required bool away}) =>
      castDoor.away.setGroupMemberAway(memberId, away: away);

  void pauseDynamicResponses() => castDoor.idle.pauseDynamicResponses();
  void resumeDynamicResponses() => castDoor.idle.resumeDynamicResponses();
  @visibleForTesting
  void debugFireIdleTimerForTest() => castDoor.idle.debugFireIdleTimerForTest();
}
