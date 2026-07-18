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
import 'package:front_porch_ai/utils/character_id.dart';

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
/// (`stableGroupId` / `isLite`), so a participant carries no state of its own;
/// per-participant realism/needs continue to live in the chat service stores.
class ChatParticipant {
  /// The card backing this participant (host card, group member card, or a
  /// resolved Scene Guest card).
  final CharacterCard card;

  /// True for the primary/host speaker (`cast[0]`). A group has no distinct host
  /// (every member is a non-host participant); a 1:1 / NPC chat always has one.
  final bool isHost;

  const ChatParticipant({required this.card, required this.isHost});

  /// Stable identifier used as the per-participant state key. Matches the key
  /// the chat service already uses (`_getCharacterIdFromCard`).
  String get id => card.stableGroupId;

  String get name => card.name;

  /// Whether this participant participates in the Realism/Needs engine. Lite
  /// NPCs (Scene Guests) are parity-safe by construction and carry no state.
  bool get realismEnabled => !card.isLite;

  /// True for a lite NPC (Scene Guest).
  bool get isLite => card.isLite;
}
