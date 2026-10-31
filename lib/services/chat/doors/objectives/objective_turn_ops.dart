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

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart'
    show AppDatabaseMemoryQueries, ObjectivesCompanion;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';

/// Objective turn ops: regen rollback (mirrors the realism delta-revert).
///
/// Objective mutations attributable to a turn (eval-proposed creations with
/// their demotion/eviction side effects, check-driven task completions and
/// quest retirements) are recorded here and ride the pending realism
/// metadata's `objective_turn_ops`, so they attach to the bot message the
/// turn produced through the flush/reset machinery the realism metadata
/// already uses. Regen inverts them (reversed, by objective id, so 1:1 and
/// group behave identically) before replaying the evals, which may then
/// re-propose for the new turn. Nothing user-initiated ever records: the
/// panel's set, toggle and clear have no recording path, and the
/// check-driven writes are gated on [armed], which only the turn-path check
/// arms, so a manual "Check now" runs the same check unrecorded and regen
/// can never undo a user action.
///
/// Known follow-up (deliberate, reviewed): swiping BACK to a rejected swipe
/// does not re-apply its inverted ops (a faithful 'created' re-apply is
/// impossible from this log: auto task-gen fills tasks after the metadata
/// flush). Accepting an old swipe and continuing self-heals at the next
/// turn's check/eval; until then the panel shows the newest swipe's state.
class ObjectiveTurnOps {
  ObjectiveTurnOps(this._door, this._d);

  final ObjectivesDoor _door;
  final ObjectiveDeps _d;

  /// Armed only while the TURN-path completion check runs (a try/finally):
  /// check-driven mutations record turn ops only when armed, so the UI's
  /// manual "Check now" never records.
  bool armed = false;

  /// The reply the post-reply clock pass belongs to, set only around that
  /// pass. Planner writes made there (a new today quest, a finished one's
  /// card) record onto THIS reply, so deleting or regenerating it undoes them.
  ChatMessage? reply;

  /// A turn's own objective work is running: the pre-reply completion
  /// check, or the post-reply clock pass. User actions (Check now, the
  /// today X, a clock nudge) run outside both and never record.
  bool get inTurn => armed || reply != null;

  /// Append one turn op to the pending realism metadata (created on demand;
  /// leaves always start from getPendingRealismMetadata(), so the list
  /// survives their read-mutate-set pattern).
  void record(Map<String, dynamic> op) {
    // Post-reply pass: the reply already exists and the pending metadata
    // has been handed over, so the op goes straight onto the reply.
    final r = reply;
    final Map<String, dynamic> target = r != null
        ? (r.activeMetadata ??= <String, dynamic>{})
        : _d.hooks.pendingMetadata();
    final list = (target['objective_turn_ops'] ??= <dynamic>[]) as List;
    list.add(op);
  }

  /// Receipt for a Journal card the turn writes: the reply being written
  /// (pre-reply check) or just written (post-reply pass). Deleting,
  /// regenerating or editing that reply then takes the card with it.
  /// Outside a turn the card cites nothing.
  List<int> cite() {
    final base = _d.hooks.historyBase();
    final messages = _d.session.messages;
    final r = reply;
    if (r != null) {
      final i = messages.lastIndexWhere((m) => identical(m, r));
      return i < 0 ? const [] : [persistMessagePosition(base: base, index: i)];
    }
    if (armed) {
      return [persistMessagePosition(base: base, index: messages.length)];
    }
    return const [];
  }

  /// Invert the rejected message's recorded objective ops (reverse order):
  /// created → deleted, tasks_changed → pre-mutation JSON restored,
  /// deactivated/evicted → reactivated, demoted → primary restored, today →
  /// the held today line put back. Blind id-addressed updates: a row
  /// deleted since (e.g. chat cleanup) no-ops.
  Future<void> revert(ChatMessage rejectedMsg) async {
    final raw = rejectedMsg.activeMetadata?['objective_turn_ops'];
    if (raw is! List || raw.isEmpty) return;
    for (final entry in raw.reversed) {
      if (entry is! Map) continue;
      if (entry['op'] == 'today') {
        await _d.hooks.revertToday(entry);
        continue;
      }
      if (entry['op'] == 'mood') {
        // A group member's mood a goal moved; the speaker's own stamp is
        // restored by the regen itself.
        final charId = entry['charId'] as String?;
        final prev = entry['prev'];
        if (charId != null && prev is Map) {
          _d.mood().writeMemberFromStamp(charId, prev);
        }
        continue;
      }
      final id = entry['id'] as String?;
      if (id == null || id.isEmpty) continue;
      try {
        await _invert(entry, id);
      } catch (e) {
        debugPrint('[Objective] Regen revert op failed (${entry['op']}): $e');
      }
    }
    debugPrint(
      '[Objective] Regen reverted ${raw.length} turn op(s) from rejected message',
    );
    // Refresh the in-memory list the UI/injection reads. In group mode the
    // turn manager has already been forced back to the rejected speaker, so
    // the speaker loader targets the right member.
    if (_d.session.activeGroup != null) {
      await _door.loadObjectivesForCurrentSpeaker();
    } else {
      await _door.loadActiveObjectives();
    }
  }

  Future<void> _invert(Map<dynamic, dynamic> entry, String id) async {
    final db = _d.db;
    switch (entry['op']) {
      case 'created':
        await db.deleteObjective(id);
      case 'tasks_changed':
        final prev = entry['prev'];
        if (prev is String) {
          await db.updateObjective(
            ObjectivesCompanion(id: drift.Value(id), tasks: drift.Value(prev)),
          );
        }
      case 'deactivated' || 'evicted':
        // A sync retirement also stamped status and ended_at; put the
        // status it had back (ops written before v58 carry no key).
        final restoresStatus = entry.containsKey('prevStatus');
        await db.updateObjective(
          ObjectivesCompanion(
            id: drift.Value(id),
            active: const drift.Value(true),
            status: restoresStatus
                ? drift.Value(entry['prevStatus'] as String?)
                : const drift.Value.absent(),
            endedAt: restoresStatus
                ? const drift.Value(null)
                : const drift.Value.absent(),
          ),
        );
      case 'status':
        await db.updateObjective(
          ObjectivesCompanion(
            id: drift.Value(id),
            status: drift.Value(entry['prev'] as String?),
          ),
        );
      case 'demoted':
        // Reconciliation guard (review finding): if the user promoted a
        // DIFFERENT objective to primary between the turn and this regen,
        // blindly restoring this one would leave two active primaries.
        // The user's later choice wins — skip the restore then.
        final charId = entry['charId'] as String?;
        var otherPrimaryExists = false;
        if (charId != null && charId.isNotEmpty) {
          final current = await db.getObjectivesForCharacter(
            charId,
            chatId: _d.session.currentSessionId,
          );
          otherPrimaryExists = current.any(
            (o) => o.active && o.isPrimary && o.id != id,
          );
        }
        if (!otherPrimaryExists) {
          await db.updateObjective(
            ObjectivesCompanion(
              id: drift.Value(id),
              isPrimary: const drift.Value(true),
            ),
          );
        }
    }
  }
}
