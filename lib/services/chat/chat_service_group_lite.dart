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
/// which test/hygiene/needs_gate_ratchet_test.dart pins to this file.
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
