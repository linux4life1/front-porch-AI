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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_deps.dart';
import 'package:front_porch_ai/services/chat/doors/controls/member_switches.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';

/// Chaos Mode per group member (PR 5b, docs/design/chaos-per-character.md).
///
/// The member's own switch/gauge/pending, read from their bag the way
/// `ControlsDoor.pocketsSwitchFor` reads theirs: the STORED value, card
/// default as the pre-seed fallback. In a group the sidebar's Chaos card
/// follows the focused member through these; generation never does — it
/// goes through the turn gate ([ChanceTime.chaosGateForTurn]) and the
/// injection, from the bag directly. In 1:1 every read answers from the
/// chat's scalars, unchanged.
class MemberChaos {
  MemberChaos(this._d, this._switches);

  final ControlsDeps _d;

  /// Member-switch writes have one owner ([MemberSwitches]: seed, mutate,
  /// commit) — injected by ControlsDoor alongside these deps.
  final MemberSwitches _switches;

  ChatSessionState get _session => _d.session;
  RealismGraph get _g => _d.graph();
  GroupChat? get _activeGroup => _session.activeGroup;

  bool switchFor(String memberId) {
    if (_activeGroup == null) return _g.chaos.chaosModeEnabled;
    final seeded = _g.groups.members[memberId]?.chaosSwitch;
    if (seeded != null) return seeded;
    for (final c in _session.groupCharacters) {
      if (_session.characterIdFor(c) == memberId) {
        return c.frontPorchExtensions?.chaosModeEnabled ?? false;
      }
    }
    return false;
  }

  bool nsfwFor(String memberId) => _activeGroup == null
      ? _g.chaos.chaosNsfwEnabled
      : _g.chaos.memberNsfw(_g.groups.members[memberId]);

  int pressureFor(String memberId) => _activeGroup == null
      ? _g.chaos.chaosPressure
      : _g.chaos.memberPressure(_g.groups.members[memberId]);

  int cooldownFor(String memberId) => _activeGroup == null
      ? _g.chaos.cooldownTurns
      : _g.chaos.memberCooldown(_g.groups.members[memberId]);

  bool hasPendingFor(String memberId) => _activeGroup == null
      ? _g.chaos.hasPendingChaosEvent
      : _g.chaos.memberHasPending(_g.groups.members[memberId]);

  String? pendingFor(String memberId) => _activeGroup == null
      ? _g.chaos.pendingChaosInjection
      : _g.chaos.memberPending(_g.groups.members[memberId]);

  /// Whether the member's wheel can carry adult events right now: their
  /// spicy switch AND the app-wide 18+ themes switch (one gate, shared).
  bool spicyFor(String memberId) => _activeGroup == null
      ? _g.chaos.spicyActive
      : _g.chaos.memberSpicyActive(_g.groups.members[memberId]);

  /// Every full cast member's chaos state, for the cast-bar badge on both
  /// surfaces: on/off per member without selecting each one.
  List<({String memberId, String name, bool enabled})> castDigest() {
    if (_activeGroup == null) return const [];
    return [
      for (final c in _session.groupCharacters)
        if (!c.isLite && _session.characterIdFor(c).isNotEmpty)
          (
            memberId: _session.characterIdFor(c),
            name: c.name,
            enabled: switchFor(_session.characterIdFor(c)),
          ),
    ];
  }

  Future<void> setSwitch(String memberId, bool on) async {
    await _switches.setChaos(memberId, on);
  }

  Future<void> setNsfw(String memberId, bool on) async {
    await _switches.setChaosNsfw(memberId, on);
  }
}
