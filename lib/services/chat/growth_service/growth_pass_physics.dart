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

import '../growth_link_overcome.dart';
import '../growth_milestones.dart';
import '../growth_ops.dart';
import '../growth_review.dart';
import '../growth_store.dart';

/// One owner's ring physics for one Growth pass, applied at pass time in
/// both modes (the JournalStore.coolCards precedent — a later discarded
/// review does not undo physics).
///
/// - Rings the pass actively engaged ([ops] reinforcing or revising them)
///   do not fade; nor do [held] ones (a too-soon reinforce the interval
///   refused, or an opted-out owner's frozen boons and bogies).
/// - Every other non-established ordinary ring steps down.
/// - Bogeys never fade on silence ("not offered" holds — §3 absence
///   amendment). Only the [copes] the pass cited wear one down a step
///   (two while the linked boon is Master — phase 7).
/// - A Master-linked flaw the cope wore to nothing has its Overcome offered
///   through [milestones] (`LinkedOvercome`), citing the cope's messages.
///
/// [copes] maps each coped ring id to its in-window messages. The caller
/// skips this on a rewound re-check, which has no new messages.
Future<void> applyGrowthPassPhysics(
  GrowthStore store,
  String sessionId,
  String ownerId, {
  required List<GrowthProposedOp> ops,
  required Set<String> held,
  required Map<String, List<int>> copes,
  GrowthMilestones? milestones,
}) async {
  final engaged = <String>{
    for (final op in ops)
      if (op.action == GrowthOpAction.reinforce ||
          op.action == GrowthOpAction.revise)
        ?op.ringId,
    ...held,
  };
  await store.fadeUnreinforced(sessionId, ownerId, engaged);
  final touched = await store.bogeys.cope(
    sessionId,
    ownerId,
    copes.keys.toSet(),
  );
  if (milestones != null && touched.isNotEmpty) {
    await LinkedOvercome.offer(milestones, touched, copes);
  }
}
