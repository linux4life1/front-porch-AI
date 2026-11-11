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
import 'package:front_porch_ai/services/chat/doors/controls/controls_deps.dart';
import 'package:front_porch_ai/services/chat/group_realism_store.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';

/// A group member's own Realism, Needs, Afterglow and Objectives switches
/// for THIS chat (docs/design/one-chat-ux.md PR 3), written the way
/// Pockets' are: the live switch rides the member's bag in the session, and
/// the member copy keeps only the default a NEW chat starts from.
///
/// Every gate reads the speaking member's switch ([GroupRealismStore]
/// `realismOnFor` and kin); this class is the write side. Off hides and
/// holds, never erases: a member's bars, Lust, goals and kit stay as they
/// were, and turning the switch back on finds them. A 1:1 chat has one
/// character and one switch, which stays where it was ([ControlsDoor]).
class MemberSwitches {
  MemberSwitches(this.deps);

  final ControlsDeps deps;

  GroupRealismStore get _groups => deps.graph().groups;

  /// The full members: a lite guest carries no Realism, Needs or Afterglow.
  Iterable<CharacterCard> get _members => [
    for (final c in deps.session.groupCharacters)
      if (!c.isLite) c,
  ];

  CharacterCard? _cardFor(String id) {
    for (final c in deps.session.groupCharacters) {
      if (deps.session.characterIdFor(c) == id) return c;
    }
    return null;
  }

  /// Write every switch a member has not been given in this chat yet, from
  /// what the chat held before they were per member: its own Realism,
  /// Needs and Objectives switches, and for Afterglow the group's old
  /// switch AND the flag on their card. A chat saved before them behaves as
  /// it did, and a flip made since survives a reopen (a switch already set
  /// is never rewritten). Called at entry, when a member joins or is
  /// promoted, and before a default is edited, so the default can never
  /// reach into a chat that is open.
  void seedMissing() {
    if (deps.session.activeGroup == null) return;
    for (final c in _members) {
      final id = deps.session.characterIdFor(c);
      if (id.isEmpty) continue;
      final bag = _groups.members[id];
      final realism = bag?.realismSwitch ?? _groups.realismOnFor(id);
      final needs = bag?.needsSwitch ?? _groups.needsOnFor(id);
      final objectives = bag?.objectivesSwitch ?? _groups.objectivesOnFor(id);
      final afterglow = _groups.afterglowOnFor(id);
      final own = _groups.memberForWrite(id);
      own.realismSwitch ??= realism;
      own.needsSwitch ??= needs;
      own.objectivesSwitch ??= objectives;
      own.afterglowSwitch ??= afterglow;
    }
  }

  /// Derive every full member's switches afresh from the chat's own, as
  /// [seedMissing] would for a member who had none: a 1:1 chat becoming a
  /// group lands its choices on the chat after the cast was seeded.
  void reseed() {
    if (deps.session.activeGroup == null) return;
    for (final c in _members) {
      final bag = _groups.members[deps.session.characterIdFor(c)];
      bag?.realismSwitch = null;
      bag?.needsSwitch = null;
      bag?.objectivesSwitch = null;
      bag?.afterglowSwitch = null;
    }
    seedMissing();
  }

  void _setRealism(String id, bool on) {
    _groups.memberForWrite(id).realismSwitch = on;
  }

  void _setNeeds(String id, bool on) {
    _groups.memberForWrite(id).needsSwitch = on;
    // Switching on mid-chat: the bars are only seeded at chat start, so a
    // member who started with Needs off has none. Seed them from the card,
    // as entry does, and never wipe on the way off.
    if (!on || _groups.needsOf(id).isNotEmpty) return;
    final card = _cardFor(id);
    if (card == null) return;
    _groups.setNeeds(
      id,
      NeedsSimulation.baselinesFromExtensions(card.frontPorchExtensions),
    );
  }

  void _setAfterglow(String id, bool on) {
    _groups.memberForWrite(id).afterglowSwitch = on;
  }

  void _setObjectives(String id, bool on) {
    _groups.memberForWrite(id).objectivesSwitch = on;
  }

  Future<void> _commit() async {
    // Paint first: a save that throws must not leave the switch flipped
    // against a stale panel (the Needs and Pockets rule).
    deps.notify();
    await deps.saveChat();
  }

  Future<void> setRealism(String id, bool on) async {
    seedMissing();
    _setRealism(id, on);
    await _commit();
  }

  Future<void> setNeeds(String id, bool on) async {
    seedMissing();
    _setNeeds(id, on);
    await _commit();
  }

  Future<void> setAfterglow(String id, bool on) async {
    seedMissing();
    _setAfterglow(id, on);
    await _commit();
  }

  Future<void> setObjectives(String id, bool on) async {
    seedMissing();
    _setObjectives(id, on);
    await _commit();
  }

  /// The chat-wide cards of Group Settings turn a switch on or off for the
  /// whole cast in one go; the sidebar's switches are the per-member ones.
  /// Null leaves a switch alone. The caller saves.
  void applyToAll({
    bool? realism,
    bool? needs,
    bool? afterglow,
    bool? objectives,
  }) {
    if (deps.session.activeGroup == null) return;
    seedMissing();
    for (final c in _members) {
      final id = deps.session.characterIdFor(c);
      if (id.isEmpty) continue;
      if (realism != null) _setRealism(id, realism);
      if (needs != null) _setNeeds(id, needs);
      if (afterglow != null) _setAfterglow(id, afterglow);
      if (objectives != null) _setObjectives(id, objectives);
    }
  }
}
