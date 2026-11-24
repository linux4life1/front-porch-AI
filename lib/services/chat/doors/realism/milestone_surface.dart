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
import 'package:front_porch_ai/database/database.dart' show GrowthMomentData;
import 'package:front_porch_ai/services/chat/growth_milestones.dart';

/// The milestone card on screen (docs/design/boons-and-bogies.md §7) — one
/// state both surfaces read: the desktop opens its dialog from [showing],
/// the web snapshot sends it, and either one's answer goes through
/// [answer].
///
/// A moment pops only after a reply has finished streaming ([check] is
/// called at the end of post-gen and after a Growth pass applies, and does
/// nothing while a reply is owed), at most one per budget window
/// ([GrowthMilestones.nextToShow]). [replay] reopens a decided moment from
/// Moments with its celebration; it asks nothing.
class MilestoneSurface {
  MilestoneSurface({
    required this.milestones,
    required this.sessionId,
    required this.userMessageCount,
    required this.popupsOn,
    required this.replyOwed,
    required this.onDecided,
    required this.notify,
  });

  final GrowthMilestones milestones;
  final String? Function() sessionId;
  final int Function() userMessageCount;
  final bool Function() popupsOn;

  /// True while a reply is still to come: the last message is the user's,
  /// or a turn, its judges, or an objective step is running. "Inside a
  /// turn" is more than one flag — the pre-reply judges run before
  /// generation rises, and a card must never open over a reply.
  final bool Function() replyOwed;

  /// After an Accept or Reject: the rings changed, re-read the growth cache.
  final Future<void> Function() onDecided;
  final VoidCallback notify;

  GrowthMomentData? _showing;
  bool _replaying = false;

  /// Moves whenever the moment list may have changed (a check after a
  /// reply or a pass, an answer, a replay): the Moments list on both
  /// surfaces re-reads when it differs from the one it drew.
  int revision = 0;

  /// The card to show, or null — never a card from another chat.
  GrowthMomentData? get showing {
    final m = _showing;
    if (m == null || m.sessionId != sessionId()) return null;
    return m;
  }

  /// True when [showing] is a replay of a decided moment (no Accept/Reject).
  bool get replaying => showing != null && _replaying;

  /// Pop the next moment if the budget allows. Safe to call any time; from
  /// the end of a reply's post-gen pass [afterReply] (that call IS the
  /// moment the reply finished, while the settle lease is still held).
  Future<void> check({bool afterReply = false}) async {
    revision++; // a pass or a roll may have queued a moment
    if (showing != null || (!afterReply && replyOwed())) return;
    final s = sessionId();
    if (s == null) return;
    final count = userMessageCount();
    final next = await milestones.nextToShow(
      s,
      userMessages: count,
      popupsOn: popupsOn(),
    );
    if (next == null || showing != null || sessionId() != s) return;
    await milestones.markShown(next.id, count);
    _showing = next;
    _replaying = false;
    notify();
  }

  /// The card's Accept or Reject (or a pending moment's, from Moments).
  /// A bogey over the cap stays on screen — the user is told why.
  Future<MilestoneOutcome> answer(String id, {required bool accept}) async {
    final outcome = await milestones.decide(id, accept: accept);
    if (outcome != MilestoneOutcome.bogeyCapFull && _showing?.id == id) {
      _showing = null;
    }
    revision++;
    await onDecided();
    notify();
    return outcome;
  }

  /// Reopen a moment from Moments: a pending one asks again, a decided one
  /// plays its celebration only.
  Future<void> replay(String id) async {
    final s = sessionId();
    if (s == null) return;
    GrowthMomentData? found;
    for (final m in await milestones.momentsFor(s)) {
      if (m.id == id) found = m;
    }
    if (found == null) return;
    await milestones.markSeen(id);
    _showing = found;
    _replaying = found.status != 'pending';
    revision++;
    notify();
  }

  /// A timeline rewrite dropped these pending moments
  /// ([GrowthMilestones.invalidatePendingFrom]): take down a card showing
  /// one, and let Moments re-read.
  void forget(List<String> ids) {
    if (ids.isEmpty) return;
    if (ids.contains(_showing?.id)) {
      _showing = null;
      _replaying = false;
    }
    revision++;
    notify();
  }

  /// Close the card without answering: a pending moment waits in Moments.
  void dismiss() {
    if (_showing == null) return;
    _showing = null;
    _replaying = false;
    notify();
  }
}
