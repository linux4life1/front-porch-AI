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
import 'package:front_porch_ai/services/chat/pressure_roll.dart';

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

  /// The last scene verdict, for the gate: true when the judge read
  /// `strong`. A strong scene holds the roll.
  bool Function()? sceneIsStrong;

  /// Ruling 18: the owner's participation switch, wired by the door.
  bool Function(String)? bbEnabledFor;

  /// The Porch Life global, wired by the door.
  bool Function()? globalEnabled;

  /// The turn gate: may a bogey roll at all for [ownerId] right now?
  ///
  /// - Boons & Bogies off globally or for this member: no.
  /// - The emotional judge did not run (one-shot / no Realism): closed —
  ///   no roll on an unknown scene. [sceneIsStrong] reads the last known
  ///   verdict; unwired means the judge is not running.
  /// - A strong scene: hold. A muted grief scene reads moderate and may
  ///   fire; that is a known v1 limit (spec §6).
  /// - A bogey already parked and undelivered: no second roll.
  bool mayRollFor(String ownerId, List<GrowthRingData> activeRings) {
    if (!(globalEnabled?.call() ?? false)) return false;
    if (!(bbEnabledFor?.call(ownerId) ?? true)) return false;
    if (!(judgeRuns?.call() ?? false)) return false;
    if (sceneIsStrong?.call() ?? false) return false;
    return !activeRings.any(
      (r) => r.category == 'bogey' && r.bogeyPending != null,
    );
  }

  /// One reply: tick every active bogey of [ownerId], persist the gauges,
  /// and park the one that fires. Returns the fired ring (null = quiet).
  /// Continue never reaches here — the caller does not roll on Continue.
  Future<GrowthRingData?> rollTurn(String ownerId) async {
    final session = _d.session.currentSessionId;
    if (session == null) return null;
    final rings = BogeyRoll.rollable(
      _g.growthStore.activeRingsFor(session, ownerId),
    );
    if (rings.isEmpty || !mayRollFor(ownerId, rings)) return null;

    final ticks = <GrowthRingTick>[];
    for (final ring in rings) {
      final t = BogeyRoll.tick(
        pressure: ring.bogeyPressure,
        cooldown: ring.bogeyCooldown,
        random: _random,
      );
      ticks.add((ring: ring, tick: t));
      await _g.growthStore.recordBogeyGauge(
        ring,
        pressure: t.pressure,
        cooldown: t.cooldown,
      );
    }
    final fired = BogeyRoll.pickFired(
      [for (final t in ticks) t.ring],
      [for (final t in ticks) t.tick],
      _random,
    );
    // The prompt reads rings from the desk's cache; a parked nudge and the
    // new gauges must be visible to it before this reply is built.
    await _g.growthDesk.refreshCache();
    if (fired == null) {
      await _d.saveChat();
      return null;
    }
    await _g.growthStore.parkBogey(
      fired,
      text: BogeyRoll.injectionText(fired, _nameFor(ownerId)),
    );
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
        await _g.growthStore.clearDeliveredBogey(ring);
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

/// One bogey's gauge movement in [BogeyRolls.rollTurn]'s local list.
typedef GrowthRingTick = ({GrowthRingData ring, PressureRollTick tick});
