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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// A single speaker in a chat, regardless of whether the conversation is a
/// single-character chat, a 1:1 chat augmented with Scene Guests (Lite NPCs),
/// or a full group.
///
/// This is the unifying primitive behind the single chat UI: every chat owns an
/// ordered list of participants (the "cast"). `cast[0]` is the **host** (the
/// primary, always realism-bearing character); every other participant is an
/// additional speaker that may be realism-bearing (a full member) or a lite NPC.
///
/// It is a thin, read-only view over the existing [CharacterCard] — it adds no
/// new persistence. Identity and tier are derived from the card itself
/// (`groupMemberStoreId` / `isLite`) and, for a 1:1 Scene Guest, from that
/// role, so a participant carries no state of its own;
/// per-participant realism/needs continue to live in the chat service stores.
class ChatParticipant {
  /// The card backing this participant (host card, group member card, or a
  /// resolved Scene Guest card).
  final CharacterCard card;

  /// True for the primary/host speaker (`cast[0]`). A group has no distinct host
  /// (every member is a non-host participant); a 1:1 / NPC chat always has one.
  final bool isHost;

  /// True for a Scene Guest present in a 1:1. Guest-ness there comes from
  /// the role, not the card: a library character brought in with `/join`
  /// keeps its own full-tier card, yet its turns run as a guest's.
  final bool isSceneGuest;

  const ChatParticipant({
    required this.card,
    required this.isHost,
    this.isSceneGuest = false,
  });

  /// Per-participant state key. Matches `_getCharacterIdFromCard`:
  /// group members / guests use [groupMemberStoreId] (UUID-first);
  /// a 1:1 host stays on [CharacterCard.stableGroupId].
  String get id => isHost ? card.stableGroupId : groupMemberStoreId(card);

  String get name => card.name;

  /// Whether this participant participates in the Realism/Needs engine. Lite
  /// NPCs (Scene Guests) are parity-safe by construction and carry no state.
  bool get realismEnabled => !isLite;

  /// True for a lite NPC: a 1:1 Scene Guest, or a group member on a lite card.
  /// Matches the engine, which runs a turn as a guest's on the same rule.
  bool get isLite => isSceneGuest || card.isLite;
}
