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

import 'dart:math';

import 'package:front_porch_ai/database/database.dart' show GrowthRingData;
import 'package:front_porch_ai/services/chat/bogey_roll.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_deps.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';

/// The turn-side half of bogey rolls (docs/design/boons-and-bogies.md §6):
/// the scene gate, one roll per reply for the speaker only, and the parked
/// nudge regen/swipe re-inject.
///
/// The math is [BogeyRoll] (pure); this class owns the gates and the store
/// writes. Chance Time's own gate and parking stay in [ChanceTime] — the
/// two never share a pending slot.
class BogeyRolls {
  BogeyRolls(this._d, {Random? random}) : _random = random ?? Random();

  final ControlsDeps _d;
  final Random _random;

  RealismGraph get _g => _d.graph();

  /// The emotional judge runs this turn (Realism on). False = unknown scene,
  /// gate closed (spec §6: no roll on a scene the judge did not read).
  bool Function()? judgeRuns;

  /// The emotional judge's own intensity for this user turn's message, as
  /// it answered — before mood physics holds or eases it. Cleared when the
  /// turn owes its roll ([oweRoll]), written by the judge, read by the gate.
  String _sceneRead = '';

  /// The judge path's hook (wired through [RealismEvals.noteSceneRead]).
  void noteSceneRead(String intensity) =>
      _sceneRead = intensity.trim().toLowerCase();

  /// Ruling 18: the owner's participation switch, wired by the door.
  bool Function(String)? bbEnabledFor;

  /// The Porch Life chain (Growth Rings → Boons & Bogies → Bogey rolls).
  bool Function()? globalEnabled;

  /// The turn gate: may a bogey roll at all for [ownerId] right now?
  ///
  /// - Any switch in the Porch Life chain off, or this member's: no.
  /// - Realism off, or no intensity read for THIS message (a judge that
  ///   failed, a lite speaker): closed — no roll on an unknown scene. The
  ///   one-shot call reads intensity too, so one-shot turns are known.
  /// - A strong read: hold. A muted grief scene reads moderate and may
  ///   fire; that is a known v1 limit (spec §6).
  /// - A bogey already parked and undelivered: no second roll.
  bool mayRollFor(String ownerId, List<GrowthRingData> activeRings) {
    if (!(globalEnabled?.call() ?? false)) return false;
    if (!(bbEnabledFor?.call(ownerId) ?? true)) return false;
    if (!(judgeRuns?.call() ?? false)) return false;
    if (_sceneRead.isEmpty || _sceneRead == 'strong') return false;
    return !activeRings.any(
      (r) => r.category == 'bogey' && r.bogeyPending != null,
    );
  }

  /// The owner a fresh user turn owes its one roll to (§6), or null. The
  /// send path sets it before the emotional judge runs; [settleOwed] rolls
  /// it after, so the scene gate reads THIS message's verdict instead of
  /// the previous one's. Regen, swipe and Continue never owe a roll.
  String? _owedFor;

  /// The send path's verdict for this user turn: [ownerId] is owed a roll,
  /// or null when nobody is (Chance Time fired, a guest was addressed).
  /// Always called, so a roll a cancelled turn never settled cannot leak
  /// into the next one.
  void oweRoll(String? ownerId) {
    _owedFor = (ownerId == null || ownerId.isEmpty) ? null : ownerId;
    _sceneRead = ''; // this message has not been read yet
  }

  /// The turn engine, after the speaker's judges and before the prompt is
  /// built: roll once if [speakerId] is the owner this turn owes. A reply
  /// by anyone else (a guest first) leaves the roll owed to a later reply
  /// of the same turn.
  Future<GrowthRingData?> settleOwed(String speakerId) async {
    final owner = _owedFor;
    if (owner == null || owner != speakerId) return null;
    _owedFor = null;
    return rollTurn(owner);
  }

  /// One reply: tick every active bogey of [ownerId] through
  /// [BogeyRoll.reply], persist the gauges, and fire the one it picks
  /// (nudge parked, count advanced, cooldown started). Returns the fired
  /// ring (null = quiet).
  Future<GrowthRingData?> rollTurn(String ownerId) async {
    final session = _d.session.currentSessionId;
    if (session == null) return null;
    final owned = _g.growthStore.activeRingsFor(session, ownerId);
    final rings = BogeyRoll.rollable(owned);
    if (rings.isEmpty || !mayRollFor(ownerId, rings)) return null;

    // Phase 7: each tier of a bogey's linked boon holds it back.
    final reply = BogeyRoll.replyForRings(rings, owned, _random);
    final bogeys = _g.growthStore.bogeys;
    final index = reply.fired;
    for (var i = 0; i < rings.length; i++) {
      if (i == index) continue;
      await bogeys.recordGauge(
        rings[i],
        pressure: reply.after[i].pressure,
        cooldown: reply.after[i].cooldown,
      );
    }
    GrowthRingData? fired;
    if (index != null) {
      fired = rings[index];
      // The twelfth fire asks (ruling 8); the count itself stays one short.
      await _g.growthMilestones.proposeMasterIfCrossing(fired);
      await bogeys.fire(
        fired,
        text: BogeyRoll.injectionText(fired, _nameFor(ownerId)),
        cooldown: reply.after[index].cooldown,
        advance: BogeyRoll.advanceAfterFire(fired.advanceCount),
      );
    }
    // The prompt reads rings from the desk's cache; a parked nudge and the
    // new gauges must be visible to it before this reply is built.
    await _g.growthDesk.refreshCache();
    await _d.saveChat();
    return fired;
  }

  /// The owner's display name, for the nudge's sentence frame.
  String _nameFor(String id) {
    final active = _d.session.activeCharacter;
    if (active != null && _d.session.characterIdFor(active) == id) {
      return active.name;
    }
    for (final c in _d.session.groupCharacters) {
      if (_d.session.characterIdFor(c) == id) return c.name;
    }
    return 'the character';
  }

  /// The next user turn: every delivered bogey nudge of [ownerId] clears,
  /// so the flaw can be rolled again later. Undelivered parks survive.
  Future<void> clearDeliveredFor(String ownerId) async {
    final session = _d.session.currentSessionId;
    if (session == null) return;
    for (final ring in _g.growthStore.activeRingsFor(session, ownerId)) {
      if (ring.category == 'bogey' && ring.bogeyDelivered) {
        await _g.growthStore.bogeys.clearDelivered(ring);
      }
    }
  }

  /// The chat-wide user-turn clear (the chaos twin): the host's and every
  /// member's delivered nudges.
  Future<void> clearDeliveredAll() async {
    final ids = <String>{};
    final active = _d.session.activeCharacter;
    if (active != null) ids.add(_d.session.characterIdFor(active));
    for (final c in _d.session.groupCharacters) {
      ids.add(_d.session.characterIdFor(c));
    }
    for (final id in ids) {
      if (id.isEmpty) continue;
      await clearDeliveredFor(id);
    }
  }
}
