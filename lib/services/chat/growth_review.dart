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

import 'package:front_porch_ai/database/database.dart';

import 'growth_boons_bogies.dart';
import 'growth_ops.dart';
import 'growth_physics.dart';
import 'growth_store.dart';

/// Default for callers that predate Boons & Bogies (tests, fakes): off.
bool boonsBogiesOff() => false;

/// Default for callers that predate ruling 18 (tests, fakes): every owner
/// participates, exactly as before the per-member switch existed.
bool bbEnabledAlways(String id) => true;

/// Growth Rings — proposals + the ONE applier
/// (docs/design/boons-and-bogies.md; the journal_review.dart pattern).
///
/// The growth pass resolves every parsed [GrowthOp] into a
/// [GrowthProposedOp] — handles become ring ids — at pass time, while the
/// ring snapshot is live. [GrowthReview.applyOwnerProposals] is then the
/// single write path for BOTH modes: normal mode applies immediately;
/// review-first (default OFF — the character grows autonomously unless the
/// user opts in) parks the batch here, and [apply]/[discard] settle it.
///
/// A parked batch is in-memory and strictly session-guarded: switching chats
/// orphans it harmlessly (no writes, no cursor moves). If it's lost (app
/// restart), the cursor never moved, so the same window is simply
/// re-proposed later — no data loss possible.
class GrowthProposedOp {
  final GrowthOpAction action;

  /// Resolved target ring id (reinforce/revise/retire) — resolved at pass
  /// time so later user edits in the timeline can't shift 1-based handles.
  final String? ringId;

  /// The target ring's text at proposal time (review UI display).
  final String? oldContent;

  /// New content (add/revise).
  final String text;
  final String category;
  final List<int> sourcePositions;

  /// Starting strength for adds (distilled starter rings seed higher —
  /// GrowthPhysics.kDistillSeedStrength).
  final double seedStrength;

  /// Review checkbox state; every op ships accepted.
  bool accepted = true;

  GrowthProposedOp({
    required this.action,
    this.ringId,
    this.oldContent,
    this.text = '',
    this.category = 'trait',
    this.sourcePositions = const [],
    this.seedStrength = GrowthPhysics.kNewRingStrength,
  });
}

class GrowthOwnerProposals {
  final String ownerId;
  final String ownerName;
  final List<GrowthProposedOp> ops;

  /// True when this owner's pass ran in distill mode (legacy blob shown):
  /// raises the add cap to the distill allowance and archives the blob after
  /// a successful apply (design §8).
  final bool distilled;

  /// The owner's own Boons & Bogies switch (ruling 18). Off: a new skill
  /// lands as a plain skill, never a boon, even with the feature on.
  final bool boonsBogies;

  GrowthOwnerProposals({
    required this.ownerId,
    required this.ownerName,
    required this.ops,
    this.distilled = false,
    this.boonsBogies = true,
  });
}

class GrowthReviewBatch {
  final String sessionId;

  /// Where the pass cursor lands once this batch is settled.
  final int cursorTarget;
  final List<GrowthOwnerProposals> owners;

  GrowthReviewBatch({
    required this.sessionId,
    required this.cursorTarget,
    required this.owners,
  });

  int get totalProposals => owners.fold(0, (n, o) => n + o.ops.length);
}

class GrowthReview {
  final GrowthStore store;
  final String? Function() getSessionId;
  final bool Function() getIsGroup;

  /// Whether Boons & Bogies is on. Off leaves new skills untagged (ordinary
  /// rings) and the prompt never asks for bogeys; already-tagged rings keep
  /// their physics either way (off is never destructive).
  final bool Function() getBoonsBogiesEnabled;

  /// Re-syncs the injection cache after any apply (both modes).
  final Future<void> Function() onApplied;
  final VoidCallback onNotify;

  GrowthReview({
    required this.store,
    required this.getSessionId,
    required this.getIsGroup,
    this.getBoonsBogiesEnabled = boonsBogiesOff,
    required this.onApplied,
    required this.onNotify,
  });

  GrowthReviewBatch? _pending;
  GrowthReviewBatch? get pending => _pending;

  bool hasPendingFor(String? sessionId) =>
      _pending != null && sessionId != null && _pending!.sessionId == sessionId;

  /// Park a batch for user review (review-first mode). Replaces any previous
  /// batch — a force pass proposes fresh.
  void park(GrowthReviewBatch batch) {
    _pending = batch;
    onNotify();
  }

  /// The single write path for one owner's proposals — used immediately by
  /// the growth pass in normal mode and by [apply] in review mode.
  /// Unaccepted ops are skipped; ops whose target ring vanished (user
  /// deleted it meanwhile) are skipped silently. The add cap is enforced
  /// HERE so no transport or mode can flood the timeline.
  Future<({int added, int reinforced, int revised, int retired})>
  applyOwnerProposals(String sessionId, GrowthOwnerProposals owner) async {
    final rings = await store.ringsFor(sessionId, owner.ownerId);
    final byId = {for (final r in rings) r.id: r};
    final addCap = owner.distilled
        ? kDistillApplyCap
        : GrowthPhysics.kMaxNewRingsPerPass;
    final boonsBogiesOn = getBoonsBogiesEnabled() && owner.boonsBogies;
    // One advance per ring per pass: a pass that reinforces the same boon
    // twice counts once (docs/design/boons-and-bogies.md §3.2).
    final advancedThisPass = <String>{};
    var activeBogeys = rings
        .where((r) => !r.retired && BoonsBogies.isBogey(r))
        .length;
    var adds = 0;
    var reinforced = 0;
    var revised = 0;
    var retired = 0;
    for (final op in owner.ops) {
      if (!op.accepted) continue;
      switch (op.action) {
        case GrowthOpAction.add:
          if (adds >= addCap) {
            debugPrint(
              '[Growth] add cap ($addCap) reached — dropping: ${op.text}',
            );
            continue;
          }
          // The three-bogey cap is shared with card-seeded flaws. An add
          // over the cap is dropped, not trimmed — existing flaws are the
          // user's story.
          if (op.category == BoonsBogies.kCategoryBogey &&
              activeBogeys >= BoonsBogies.kMaxActiveBogies) {
            debugPrint(
              '[Growth] bogey cap (${BoonsBogies.kMaxActiveBogies}) reached '
              '— dropping: ${op.text}',
            );
            continue;
          }
          adds++;
          if (op.category == BoonsBogies.kCategoryBogey) activeBogeys++;
          await store.addRing(
            sessionId: sessionId,
            characterId: owner.ownerId,
            content: op.text,
            category: op.category,
            sourcePositions: op.sourcePositions,
            strength: op.seedStrength,
            metadata: switch (op.category) {
              // A new skill is a boon when the feature is on; a bogey is
              // always tagged so the panel and the roll agree on the kind.
              'skill' when boonsBogiesOn => BoonsBogies.boonMetadata(),
              BoonsBogies.kCategoryBogey => BoonsBogies.bogeyMetadata(),
              _ => null,
            },
          );
          break;
        case GrowthOpAction.reinforce:
          final ring = byId[op.ringId];
          if (ring == null || ring.retired) continue;
          if (BoonsBogies.isBoon(ring)) {
            // One step per ring per pass: a pass that reinforces the same
            // boon twice counts (and advances) once.
            if (advancedThisPass.contains(ring.id)) continue;
            await store.reinforceBoon(
              ring,
              advanceCount: BoonsBogies.nextBoonAdvance(ring.advanceCount),
              metadata: BoonsBogies.metadataWithUndo(
                ring,
                at: op.sourcePositions.isEmpty ? 0 : op.sourcePositions.last,
              ),
              sourcePositions: op.sourcePositions,
            );
            advancedThisPass.add(ring.id);
          } else if (BoonsBogies.isBogey(ring)) {
            // A second reinforce for the same bogey in one pass adds no
            // evidence — the roll is the only other writer.
            if (advancedThisPass.contains(ring.id)) continue;
            await store.reinforceBogey(
              ring,
              advanceCount: BoonsBogies.nextBogeyAdvance(ring.advanceCount),
              metadata: BoonsBogies.metadataWithUndo(
                ring,
                at: op.sourcePositions.isEmpty ? 0 : op.sourcePositions.last,
              ),
              sourcePositions: op.sourcePositions,
            );
            advancedThisPass.add(ring.id);
          } else {
            await store.reinforceRing(
              ring,
              sourcePositions: op.sourcePositions,
            );
          }
          reinforced++;
          break;
        case GrowthOpAction.revise:
          final ring = byId[op.ringId];
          if (ring == null) continue;
          await store.reviseRing(
            ring,
            content: op.text,
            metadata: BoonsBogies.isBoonOrBogey(ring)
                ? BoonsBogies.metadataWithUndo(ring)
                : null,
          );
          revised++;
          break;
        case GrowthOpAction.retire:
          if (op.ringId == null) continue;
          final ring = byId[op.ringId];
          if (ring == null) continue;
          // A bogey is only retired by the accepted overcome milestone
          // (§3.2) — a model "outgrown" retire would silently take a flaw
          // away, which is the one thing the approval rule exists to stop.
          if (BoonsBogies.isBogey(ring)) continue;
          await store.retireRing(op.ringId!);
          retired++;
          break;
      }
    }
    if (owner.distilled && adds > 0) {
      // Distill keeps injecting the blob until starter rings actually land.
      // Review-first Apply with every add unchecked must not throw it away.
      await store.archiveLegacyBlob(
        sessionId,
        owner.ownerId,
        isGroup: getIsGroup(),
      );
    }
    return (
      added: adds,
      reinforced: reinforced,
      revised: revised,
      retired: retired,
    );
  }

  /// Restore one boon/bogey ring from its stored one-step snapshot (the
  /// reply chip and the panel row). Content still moves through this class,
  /// not the UI, so the single-write-path invariant holds. False when the
  /// ring or its snapshot is gone (a second tap, or a chat switch).
  Future<bool> undoBoonBogey(
    String sessionId,
    String characterId,
    String ringId,
  ) async {
    final rings = await store.ringsFor(sessionId, characterId);
    GrowthRingData? target;
    for (final ring in rings) {
      if (ring.id == ringId) {
        target = ring;
        break;
      }
    }
    if (target == null) return false;
    final undo = BoonsBogies.undoOf(target);
    if (undo == null) return false;
    await store.restoreUndo(target, undo);
    await onApplied();
    onNotify();
    debugPrint('[Growth] ↶ Undo applied to ${target.content}');
    return true;
  }

  /// Commit the pending batch: accepted ops, cursor past the reviewed
  /// window. A batch from another chat is dropped without writing anything.
  Future<void> apply() async {
    final batch = _pending;
    if (batch == null) return;
    if (getSessionId() != batch.sessionId) {
      _pending = null;
      onNotify();
      return;
    }
    // Keep _pending SET during the writes so hasPendingFor() still blocks a
    // competing auto-pass (no reprocess → no duplicate rings). Advance the
    // (DB-backed) cursor + clear _pending only AFTER every write succeeds, so a
    // write failure preserves the batch for retry instead of silently
    // abandoning accepted rings (the earlier "advance first" version fixed the
    // race but introduced that loss).
    for (final owner in batch.owners) {
      await applyOwnerProposals(batch.sessionId, owner);
    }
    await store.setCursor(batch.sessionId, batch.cursorTarget);
    _pending = null;
    await onApplied();
    onNotify();
    debugPrint(
      '[Growth] ✓ Review applied (${batch.totalProposals} proposal(s))',
    );
  }

  /// Dismiss without writing: the window counts as handled (cursor advances)
  /// so it isn't re-proposed forever.
  Future<void> discard() async {
    final batch = _pending;
    _pending = null;
    if (batch == null) return;
    if (getSessionId() == batch.sessionId) {
      await store.setCursor(batch.sessionId, batch.cursorTarget);
    }
    onNotify();
    debugPrint('[Growth] ✗ Review discarded');
  }

  /// Drop a parked batch without advancing the cursor — timeline rewrite
  /// made the proposals cite discarded plot. Next pass re-reads the new tip.
  void abandon() {
    if (_pending == null) return;
    _pending = null;
    onNotify();
  }
}

/// Add cap when the pass ran in distill mode (kDistillMaxRings starter rings
/// from the legacy blob + the normal per-pass allowance from the window).
const int kDistillApplyCap = 8;
