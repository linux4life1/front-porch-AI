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

// Starts Away at the door (docs/design/group-initial-presence.md): the
// chat-creation seeder for the card's `ext.startsAway` switch. Called when
// a group chat is CREATED — fresh entry into a group, and a new chat
// inside one — never on a restore. The hold is the same latch the user's
// hand-set Away keeps, so only their Back (or an @Name) lifts it; it
// seeds whether or not the Realism Engine is on, and the member row is
// never rewritten, so every later chat can seed again.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

/// Seed each member's runtime Away hold from the card's Starts Away switch.
///
/// Consume-at-create: read once, when the chat is made; a restore re-reads
/// the saved chat and never re-seeds. The write order matches the manual
/// Away write in away_pulse_runner.dart — `awayHeld` first, `withUser`
/// second — because the `withUser` setter refuses to enable a held member,
/// so the order is load-bearing. Members whose ext says nothing (or that
/// has no ext) write nothing.
void seedMemberStartsAway(
  Iterable<CharacterCard> members,
  GroupRealismStore store, {
  required String Function(CharacterCard) idOf,
}) {
  for (final member in members) {
    if (!(member.frontPorchExtensions?.startsAway ?? false)) continue;
    final slot = store.memberForWrite(idOf(member));
    slot.awayHeld = true;
    slot.withUser = false;
  }
}
