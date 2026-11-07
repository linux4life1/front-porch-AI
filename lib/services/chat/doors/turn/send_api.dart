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

/// The send spine's old public names (bodies in [SendSpine] and its
/// leaves). `isGenerating` and `isTurnBusy`, which the golden fake
/// overrides, stay on the shell as forwarders.
extension ChatServiceSend on ChatService {
  /// Why a message cannot be sent now while the speed test holds the app's
  /// KoboldCpp, or null (body in [SendGates.sendRefusal]).
  String? sendRefusal(String text, {bool withImage = false}) =>
      sendSpine.gates.sendRefusal(text, withImage: withImage);

  /// Why [sendMessage] would drop a message right now, or null when it would
  /// go: the one predicate the composer, the web relay and the send share
  /// (body in [SendGates.busyReason]).
  String? get sendBusyReason => sendSpine.gates.busyReason;

  /// Send the user's line, with an optional photo (body in
  /// [SendSpine.sendMessage]).
  Future<void> sendMessage(String text, {Uint8List? imageBytes}) =>
      sendSpine.sendMessage(text, imageBytes: imageBytes);
}

/// The "Did time pass?" gate a send parks on.
extension ChatServiceSendGates on ChatService {
  /// Typed send is queued behind post-gen evals. Composer is empty; no bubble
  /// yet. UI shows a holding banner so the wait does not look like a lost send.
  bool get isSendWaitingOnSettle => sendSpine.isSendWaitingOnSettle;

  /// The "Did time pass?" question the send is waiting on, or null. The
  /// desktop dialog and the web sheet show it while it is non-null.
  PendingSkip? get pendingSkip => sendSpine.gates.pendingSkip;

  /// The player's answer to [pendingSkip]: a skip, [SkipVerdict.none] for
  /// "no skip", or null to keep the reader's guess.
  void answerSkip(SkipVerdict? verdict) => sendSpine.gates.answerSkip(verdict);

  /// Whether a web client is connected to answer [pendingSkip].
  set skipConfirmWebAsker(bool Function() connected) =>
      sendSpine.gates.skipConfirmWebAsker = connected;
}

/// Group speaker picking, the web/mobile Chance Time reveal surface and the
/// Journal recap controls (bodies in [GroupSpeakers], [ChanceReveal] and
/// [RecapControls]).
extension ChatServiceTurnFlow on ChatService {
  /// Trigger the next character to speak in group mode.
  Future<void> triggerNextCharacter() =>
      sendSpine.speakers.triggerNextCharacter();

  /// Manually select which character speaks next in group mode.
  void setNextCharacter(CharacterCard character) =>
      sendSpine.speakers.setNextCharacter(character);

  /// True when auto-trigger fires. UI reads then calls consumeChanceTimeTrigger().
  bool get chanceTimePendingTrigger =>
      sendSpine.chanceReveal.chanceTimePendingTrigger;

  /// True when a chaos event is queued for the next response (blocks manual spin + auto-trigger).
  bool get hasPendingChaosEvent => sendSpine.chanceReveal.hasPendingChaosEvent;

  /// Called by the overlay once it has opened. Clears the auto-trigger flag.
  void consumeChanceTimeTrigger() =>
      sendSpine.chanceReveal.consumeChanceTimeTrigger();

  /// True from the moment a Chance Time parks [sendMessage] until it is
  /// accepted (the web reveal modal's durable signal).
  bool get isAwaitingChanceTime => sendSpine.chanceReveal.isAwaitingChanceTime;

  /// Manual SPIN NOW. Parks a pre-picked event until accept.
  bool requestManualChanceTime() =>
      sendSpine.chanceReveal.requestManualChanceTime();

  /// The speaker a Chance Time event is attributed to, shared by the desktop
  /// wheel overlay and the web accept path.
  String get chanceTimeSpeakerName =>
      sendSpine.chanceReveal.chanceTimeSpeakerName;

  /// The pre-picked pending event with its placeholders resolved, for the web
  /// reveal modal. Null when nothing is parked.
  String? get webChanceTimeDisplay =>
      sendSpine.chanceReveal.webChanceTimeDisplay;

  /// Web/mobile "Accept Your Fate" (body in
  /// [ChanceReveal.acceptPendingChanceTime]).
  Future<void> acceptPendingChanceTime() =>
      sendSpine.chanceReveal.acceptPendingChanceTime();

  /// Manually set the recap text.
  void setSummary(String text) => sendSpine.recap.setSummary(text);

  /// Pause or resume the automatic Journal maintenance pass.
  void setSummaryPaused(bool paused) =>
      sendSpine.recap.setSummaryPaused(paused);

  /// Force an immediate Journal maintenance pass (cards + recap), bypassing
  /// the interval. Backs the sidebar/web "Regenerate" button.
  Future<void> forceSummaryUpdate() => sendSpine.recap.forceSummaryUpdate();
}
