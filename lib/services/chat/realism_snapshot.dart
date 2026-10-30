// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/mood_physics.dart';
import 'package:front_porch_ai/services/chat/mood_registers.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/needs_wear.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/pockets/pockets_record.dart';
import 'package:front_porch_ai/services/chat/realism_scope.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/story_clock_claims.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

/// Message-metadata key holding the spatial stance the turn STARTED from.
///
/// Posture is written AFTER generation (it reads the reply), so the message's
/// `realism_state` snapshot — captured before generation — gets its
/// `spatialStance` overwritten with where the reply LEFT them. That is correct
/// for every forward reader and destroys the only copy of the value a
/// REGENERATE has to put back, which is why this receipt exists. Written once
/// per message in [RealismSnapshot.restampPostGen], read once in the regen
/// revert; named here so the two can never drift apart on a typo.
///
/// Sibling of `needs_pre_turn_vector` and `pre_climax_arousal` — the same
/// contract for the two other post-generation writes.
const String kSpatialStancePreTurn = 'spatial_stance_pre_turn';

/// Pre-turn glance bit. The with-user pass is post-gen like posture, so
/// restamp overwrites `realism_state.withUser` with the reply's verdict.
/// Regen/swipe must put the turn's START back (audit P1.7).
const String kWithUserPreTurn = 'with_user_pre_turn';

/// The per-message `realism_state` snapshot: captured before generation and
/// re-stamped with the post-generation values once the reply's passes ran.
/// Every rewind (regen, swipe, delete time-travel) restores from it.
class RealismSnapshot {
  RealismSnapshot(
    this._scope, {
    required this.needsActive,
    required this.pocketsFor,
    required this.wearBeatOn,
  });

  final RealismScope _scope;

  /// `NeedsPass.active` — the one Needs gate.
  final bool Function() needsActive;

  /// The Pockets record for an id, null when Pockets is off.
  final Pockets? Function(String characterId) pocketsFor;

  /// `NeedsPass.wearBeatOn`: wears minutes the clock has not charged yet.
  final void Function(ChatMessage target) wearBeatOn;

  bool get _needsSimEnabled => _scope.needsSimEnabled();
  bool get _clockRunning => _scope.clockRunning();
  NeedsSimulation get _needsSimulation => _scope.needs();
  RelationshipService get _relationshipService => _scope.relationship();
  NsfwService get _nsfwService => _scope.nsfw();
  TimeService get _timeService => _scope.time();
  CharacterCard? get _activeCharacter => _scope.activeCharacter();
  late final MoodRegisters _mood = MoodRegisters(_scope);
  String _getCharacterIdFromCard(CharacterCard c) => _scope.characterIdFor(c);

  Map<String, dynamic> capture({Map<String, int>? preTurn}) {
    final state = {
      'affectionScore': _relationshipService.affectionScore,
      'relationshipTier': _relationshipService.relationshipTier,
      'longTermScore': _relationshipService.longTermScore,
      'longTermTier': _relationshipService.longTermTier,
      'turnsSinceLongTermCheck': _relationshipService.turnsSinceLongTermCheck,
      'shortTermDeltasSummary': _relationshipService.shortTermDeltasSummary,
      // The decay cadence + the group's hidden inter-character feelings. These
      // are the eval inputs that used to be missing from this snapshot, so a
      // group regen could not rewind them; see captureCadenceAndFeelings.
      // (They replaced 'moodDecayCounter', which was captured, persisted and
      // restored while no decay logic read it — the real counter was, and is,
      // RelationshipService's.)
      ..._relationshipService.captureCadenceAndFeelings(),
      // Label, intensity, cause and hold (docs/design/mood-with-bite.md).
      ..._mood.state.toStamp(),
      'timeOfDay': _timeService.timeOfDay,
      'dayCount': _timeService.dayCount,
      'startDayOfWeek': _timeService.startDayOfWeekAnchor,
      'storyClock': _timeService.storyClockIso,
      'storyStartDate': _timeService.storyStartDateIso,
      'arousalLevel': _nsfwService.stampArousal,
      ..._nsfwService.stampRefractory.toSnapshot(),
      'trustLevel': _relationshipService.trustLevel,
      'pendingTrustRepair': _relationshipService.pendingTrustRepair,
      'activeFixation': _relationshipService.activeFixation,
      'fixationLifespan': _relationshipService.fixationLifespan,
      'spatialStance': _relationshipService.spatialStance,
      'withUser': _relationshipService.withUser,
      // Pockets & Wardrobe rides the rewind contract like every other
      // per-turn scalar. Without this a regenerate re-runs the detection pass
      // on a NEW reply while the record still carries the discarded reply's
      // changes — they pick the keys up twice, or are left holding something
      // from a version of the scene that no longer exists. Found in review by
      // Grok, 2026-08-07, and required by the design doc in as many words.
      ...(() {
        final c = _activeCharacter;
        if (c == null) return const <String, dynamic>{};
        final p = pocketsFor(_getCharacterIdFromCard(c));
        return p == null ? const <String, dynamic>{} : {'pockets': p.toJson()};
      })(),
    };

    // Include needs snapshot when the simulation is active (clean port).
    // Note: 'enabled' is deliberately omitted from the per-message snapshot.
    // The enabled flag is authoritative from the character card / current session
    // (see setNeedsSimEnabled and ext seeding). Snapshots only carry the vector
    // for timeline continuity while the sim is on. This prevents historical
    // snapshots from resurrecting a stale enabled state after a mid-chat toggle-off.
    if (needsActive() && _needsSimulation.vector.isNotEmpty) {
      // Explicit <String, dynamic> for the needs snapshot so that 'deltas' (Map with
      // mixed int/String values from computeNeedsDeltasWithReasons) can be attached
      // without runtime generic value-type violation (the 'vector' entry statically
      // infers Map<String,int>, which would lock the literal's value type and reject
      // the deltas map on []=).
      final needsSnap = <String, dynamic>{
        'vector': Map<String, int>.from(_needsSimulation.vector),
        'hygiene_crisis_acked': _needsSimulation.hygieneCrisisAcked.toList(),
        kNeedsWearCarryKey: Map<String, double>.from(
          _needsSimulation.wearCarry,
        ),
      };
      state['needs'] = needsSnap;

      final needsDeltas = _needsSimulation.computeNeedsDeltasWithReasons(
        preTurn ?? const <String, int>{},
      );
      if (needsDeltas.isNotEmpty) {
        needsSnap['deltas'] = needsDeltas;
      }
    }

    return state;
  }

  /// Re-stamp the just-generated message's `realism_state` snapshot with the
  /// POST-generation values, so every consumer that restores a message's
  /// snapshot as a baseline (regenerating a later message, the regen merge's
  /// _restoreRealismStateForSpeaker, swipe navigation, delete time-travel)
  /// sees the turn's final state, not the pre-impact one.
  ///
  /// Two shipped bugs live here as warnings:
  ///  * NEEDS: the snapshot is captured during the pre-gen eval, before the
  ///    needs impact applies scene rewards — restoring it reverted them
  ///    ("Hygiene snaps back after regenerating the next message").
  ///  * NSFW (the "orgasm detection doesn't work" report, Violet Vance chat):
  ///    a climax fires in the post-gen checks — arousal to 0, refractory
  ///    started — AFTER the snapshot froze arousal at 100 / cooldown 0. The
  ///    1:1 regen merge then restored that stale snapshot and ERASED the
  ///    climax seconds after detection: the swipe's own metadata carried
  ///    climax_triggered=true while the session row still said 100/0/0.
  ///
  /// SPATIAL STANCE joined them on 2026-08-08, when the posture eval moved to
  /// the post-generation phase so it could read the reply. That moved a WRITE
  /// across the snapshot boundary: without this line every message would
  /// carry the position the character was in BEFORE their reply, and the regen
  /// revert (which rebuilds its baseline from the previous accepted message's
  /// snapshot) would hand the replacement turn a position one exchange stale
  /// — the exact teleport the move was made to stop, reintroduced through the
  /// rewind door. It is also what makes swiping between alternatives move the
  /// character to where THAT alternative left them.
  ///
  /// SPATIAL STANCE ALSO LEAVES A PRE-TURN RECEIPT HERE, and that is not
  /// bookkeeping — it is the other half of moving the write.
  ///
  /// The snapshot below is captured BEFORE generation, so up to the moment
  /// this method runs `rs['spatialStance']` still holds the position the turn
  /// STARTED from. Overwriting it with the post-reply position is right for
  /// everything that reads a snapshot forwards (the next turn's baseline,
  /// swipe navigation, delete time-travel) and fatal for the one thing that
  /// reads it backwards: a REGENERATE has to put the stance back to what it
  /// was before the reply it is discarding, and after the overwrite no record
  /// of that value existed anywhere.
  ///
  /// The regen revert normally papers over this by restoring the PREVIOUS
  /// accepted message's snapshot — whose post-reply stance is, by
  /// construction, this turn's pre-reply stance. But the FIRST reply of a
  /// chat has no previous accepted message: the greeting only carries a
  /// snapshot on the one entry path that runs the greeting baseline eval
  /// (1:1, `startNewChat`, card with NO frontPorchExtensions), which is
  /// neither the common card shape, nor a group, nor the ordinary
  /// open-a-character path. On every other opening the revert found nothing,
  /// left the discarded reply's position in place, and each reroll then
  /// grounded the next attempt in a position invented by the reply the user
  /// had just thrown away — drifting further every press.
  ///
  /// So the pre-reply value is preserved beside the snapshot before it is
  /// overwritten, in exactly the idiom `needs_pre_turn_vector` and
  /// `pre_climax_arousal` already use for the two other post-generation
  /// writes: the rejected message carries the receipt for its own rewind.
  /// `putIfAbsent` is what makes Continue safe — a continuation restamps the
  /// SAME message a second time, by which point the snapshot holds the
  /// post-reply position, and recording that would quietly redefine "before
  /// the turn" as "after it".
  ///
  /// metadata and swipeMetadata[i] share one map instance, so this in-place
  /// update sticks through the regen swipe merge and persists. 1:1 and group
  /// alike: the speaker's scalars are loaded when this runs. Guests carry no
  /// realism_state, so this no-ops for them.
  Future<void> restampPostGen(ChatMessage msg) async {
    if (msg.isUser) return;
    // They named a time ("six in the morning") that disagrees with the
    // pre-gen snap (new_day → 08:00). Fiction wins so the sidebar matches
    // the line you just read. Gated on a moving clock — a frozen clock
    // must not start chasing dialogue.
    if (_clockRunning) {
      final named = clockNamedInReply(msg.text, _timeService.clock);
      if (named != null) {
        await _timeService.applyReconciledClock(named);
        // The beat's minutes were worn before the judge ran; the correction
        // leaves only its own extra minutes to wear.
        wearBeatOn(msg);
      }
    }
    final meta = msg.activeMetadata;
    final rs = meta?['realism_state'];
    if (rs is! Map) return;
    if (_needsSimEnabled &&
        _needsSimulation.vector.isNotEmpty &&
        rs['needs'] is Map) {
      final needs = rs['needs'] as Map;
      needs['vector'] = Map<String, int>.from(_needsSimulation.vector);
      // The carry was captured pre-wear; a swipe restoring post-beat bars
      // with a pre-beat fraction would spend that fraction twice.
      needs[kNeedsWearCarryKey] = Map<String, double>.from(
        _needsSimulation.wearCarry,
      );
    }
    if (rs.containsKey('arousalLevel')) {
      rs['arousalLevel'] = _nsfwService.stampArousal;
      rs.addAll(_nsfwService.stampRefractory.toSnapshot());
    }
    if (rs.containsKey('spatialStance')) {
      meta!.putIfAbsent(
        kSpatialStancePreTurn,
        () => rs['spatialStance'] as String? ?? '',
      );
      rs['spatialStance'] = _relationshipService.spatialStance;
    }
    // Same shape as posture: only stamp when the snapshot carried the
    // key. Unconditional putIfAbsent(null) would wipe a previous-message
    // restore on regen of a pre-glance chat.
    if (rs.containsKey('withUser')) {
      meta!.putIfAbsent(kWithUserPreTurn, () => rs['withUser']);
      rs['withUser'] = _relationshipService.withUser;
    }
    // The day roll and the planner door move the mood AFTER the reply was
    // stamped (both run in the post-reply clock pass), so the reply's
    // snapshot carries the eased mood and a swipe back shows it, not the
    // one from before the clock moved.
    if (rs.containsKey(kMoodStampLabel)) {
      rs.addAll(_mood.state.toStamp());
    }
    // Pockets was captured pre-gen in [capture] and never
    // restamped, so swipe/delete restore put the PRE-ops kit back after a
    // successful pass (release audit 2026-08-11). Mirror needs/arousal:
    // the snapshot that rides the accepted message is post-turn truth.
    if (_activeCharacter != null) {
      final p = pocketsFor(_getCharacterIdFromCard(_activeCharacter!));
      if (p != null) {
        rs['pockets'] = p.toJson();
      }
    }
    rs['storyClock'] = _timeService.storyClockIso;
    rs['timeOfDay'] = _timeService.timeOfDay;
    rs['dayCount'] = _timeService.dayCount;
  }
}
