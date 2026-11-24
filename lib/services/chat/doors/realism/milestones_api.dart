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

import 'package:front_porch_ai/database/database.dart' show GrowthMomentData;
import 'package:front_porch_ai/services/chat/growth_milestones.dart';
import 'package:front_porch_ai/services/chat_service.dart';

/// Boons & Bogies milestones (docs/design/boons-and-bogies.md §7) — the
/// names the desktop card, the Moments list and the web facade call. One
/// state ([MilestoneSurface]) behind both surfaces.
extension ChatServiceMilestones on ChatService {
  // `milestoneShowing` is a shell forwarder (the golden fakes answer it);
  // everything below is read only when it is non-null.

  /// True when [ChatService.milestoneShowing] replays a decided moment (no buttons).
  bool get milestoneReplaying => realism.milestoneSurface.replaying;

  /// Accept or Reject a pending moment, from the card or from Moments.
  Future<MilestoneOutcome> answerMilestone(String id, {required bool accept}) =>
      realism.milestoneSurface.answer(id, accept: accept);

  /// Reopen a moment from Moments.
  Future<void> replayMilestone(String id) =>
      realism.milestoneSurface.replay(id);

  /// Close the card unanswered; a pending moment waits in Moments.
  void dismissMilestone() => realism.milestoneSurface.dismiss();

  /// One owner's moments in this chat, newest first (the Moments list).
  Future<List<GrowthMomentData>> milestonesForOwner(String ownerId) async {
    final session = currentSessionId;
    if (session == null) return const [];
    return realism.growthMilestones.momentsFor(session, characterId: ownerId);
  }

  /// The display name for a moment's owner — the card names the member in
  /// a group. Empty when the owner has left the cast.
  String milestoneOwnerName(String characterId) {
    final active = activeCharacter;
    if (active != null && characterIdFor(active) == characterId) {
      return active.name;
    }
    for (final c in groupCharacters) {
      if (characterIdFor(c) == characterId) return c.name;
    }
    return '';
  }
}
