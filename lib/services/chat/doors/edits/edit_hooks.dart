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

import 'package:front_porch_ai/models/models.dart';

// Debt: every hook below is state or behaviour another part of the chat
// service still owns. A hook goes when its owner becomes a door; the work
// package that retires it is named on each class.

/// The send spine's Try again on a trailing user line (WP10c). The turn
/// engine's own flags and calls are [EditDeps.engine].
class EditTurnHooks {
  const EditTurnHooks({required this.answerTrailingUserLine});

  /// Try again on a trailing user line (`_generateFromTrailingUserTurn`).
  final Future<void> Function({
    String? webQuery,
    String? wikiQuery,
    CharacterCard? forceSpeaker,
  })
  answerTrailingUserLine;
}

/// The Realism hooks the send spine still holds: its stamp-less rewind
/// (WP10c). The regen judge replay and delete's Needs baseline and Pockets
/// rewind are the turn engine's ([EditDeps.engine]).
class EditRealismHooks {
  const EditRealismHooks({
    required this.rewindToLastAcceptedReply,
    required this.restoreScoredRegisters,
  });

  /// 1:1 stamp-less rewind of the scored registers to the last reply.
  final bool Function() rewindToLastAcceptedReply;
  final void Function(Map<String, dynamic> stamp) restoreScoredRegisters;
}

/// Scene Guests, the group speaker pick and the opening greeting (WP6).
class EditCastHooks {
  const EditCastHooks({
    required this.guestBusy,
    required this.isGuestAuthored,
    required this.guestFor,
    required this.setStatus,
    required this.guestChimeIns,
    required this.pickPresentSpeaker,
    required this.greetingIndex,
    required this.setGreetingIndex,
    required this.greetingOwner,
    required this.firstMessage,
    required this.invalidateGreetingEval,
    required this.stampGreetingIndex,
    required this.isOpeningGreetingChat,
    required this.seedGroupGreeting,
    required this.seedGreeting,
  });

  /// A Scene Guest turn is running.
  final bool Function() guestBusy;

  /// [m] was written by a Scene Guest, present or gone.
  final bool Function(ChatMessage m) isGuestAuthored;

  /// The present guest who wrote [m], or null.
  final CharacterCard? Function(ChatMessage m) guestFor;

  /// The chat's one-line status notice.
  final void Function(String? text, {bool isError}) setStatus;

  /// Re-runs the guest chime gate against the new host reply.
  final Future<void> Function({required String userText}) guestChimeIns;

  /// A present group member, for a group impersonate nobody has answered.
  final CharacterCard Function() pickPresentSpeaker;

  /// The opening greet on screen.
  final int Function() greetingIndex;
  final void Function(int index) setGreetingIndex;

  /// Who owns the opening bubble (null for a custom group greeting).
  final CharacterCard? Function() greetingOwner;

  /// A card greet, macro-resolved as the opening bubble shows it.
  final String Function(CharacterCard card, {String? greetingText})
  firstMessage;

  /// Drops a stale greeting eval before the opening changes.
  final Future<void> Function() invalidateGreetingEval;
  final void Function(int index) stampGreetingIndex;

  /// The chat holds only its opening.
  final bool Function() isOpeningGreetingChat;

  /// Re-seeds a custom group greeting's Realism and Needs.
  final Future<void> Function(int index) seedGroupGreeting;

  /// Re-seeds a card greet's Realism and Needs.
  final Future<void> Function({required CharacterCard card, required int index})
  seedGreeting;
}
