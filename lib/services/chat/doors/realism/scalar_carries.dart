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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';

/// The Realism scalars a cast changing shape carries: back into a 1:1 when
/// a group collapses to one member, and onto the host member when a 1:1
/// becomes a group. The rest of both moves is the cast door's CastCollapse.
/// test/hygiene/realism_gate_ratchet_test.dart pins the places here that
/// read and write the chat's own Realism switch through a cast change.
class ScalarCarries {
  ScalarCarries(this._g);

  final RealismGraph _g;

  SessionStore get _sessions => _g.deps.doors.sessions();

  /// The chat's own Realism switch, which a cast change carries.
  bool get _realismChatSwitch => _g.controls.chatRealism;
  set _realismChatSwitch(bool on) => _g.controls.setChatRealism(on);

  /// The chat's stored Needs switch, carried with it.
  bool get _needsSimEnabled => _g.controls.needsSimEnabled;
  set _needsSimEnabled(bool on) => _g.controls.needsSimEnabled = on;

  RealismDance get _realismDance => _g.dance;
  RealismSnapshot get _realismSnapshot => _g.snapshot;
  GroupRealismStore get _groupStore => _g.groups;
  Map<String, GroupMemberRealism> get _groupRealism => _g.groups.members;
  ChaosModeService get _chaosModeService => _g.chaos;
  NsfwService get _nsfwService => _g.nsfw;
  RelationshipService get _relationshipService => _g.relationship;
  MoodRegisters get _mood => _g.mood;
  StoryClockWriter get _clockWriter => _g.clockWriter;
  NeedsSimulation get _needsSimulation => _g.needs;
  set _pockets(Pockets? record) => _g.hostPockets = record;
  set _authorNote(String v) => _sessions.authorNote = v;
  set _authorNoteStrength(int v) => _sessions.authorNoteStrength = v;
  Map<String, String> get _groupAuthorNotes =>
      _sessions.groupConfig.authorNotes;
  Map<String, int> get _groupAuthorNoteStrengths =>
      _sessions.groupConfig.authorNoteStrengths;
  void setPocketsFor(String characterId, Pockets p) =>
      _g.setPocketsFor(characterId, p);

  /// While still in group mode, capture the survivor's full state to carry
  /// back to the 1:1: the realism snapshot (gated on realism being on) PLUS
  /// the enable-flags, author note, pockets and chaos (carried regardless of
  /// realism). The returned call writes them into the 1:1 after it opens
  /// (opening the 1:1 reset them).
  void Function() captureSurvivor(String soleId) {
    final bool wasRealismOn = _realismChatSwitch;
    final bool wasNeedsOn = _needsSimEnabled;
    Map<String, dynamic>? snapshot;
    if (wasRealismOn) {
      _realismDance.loadIntoScalars(
        soleId,
      ); // loads the survivor's per-char nsfw flag too
      snapshot = _realismSnapshot.capture();
    }
    // The 1:1 chat keeps the switch the group chat showed for the survivor:
    // the group chat's own AND hers. A member's stored flag is a legacy
    // register no gate reads.
    final bool soleNsfwEnabled = _groupStore.afterglowOnFor(soleId);
    // Same reasoning for their Pockets record, and read here for the same reason:
    // step 4 re-enters as a 1:1, which clears the group slots. Carried regardless
    // of realism because Pockets does not depend on it — the pass is gated on
    // pocketsEnabled alone, so a survivor can be holding their keys with the
    // engine off. Dropping this is how a collapse would empty their hands.
    final Pockets? solePockets = _groupRealism[soleId]?.pockets;
    final bool soleChaosEnabled = _chaosModeService.chaosModeEnabled;
    final int soleChaosPressure = _chaosModeService.chaosPressure;
    final bool soleChaosNsfw = _chaosModeService.chaosNsfwEnabled;
    final String soleAuthorNote = _groupAuthorNotes[soleId] ?? '';
    final int soleAuthorStrength = _groupAuthorNoteStrengths[soleId] ?? 4;

    return () {
      // Seed, never setNsfwCooldownEnabled: its "off" zeroes Lust. First, so
      // the restore below reads the switch the 1:1 keeps.
      _nsfwService.seedFromV2OrExt(nsfwCooldownEnabled: soleNsfwEnabled);
      if (wasRealismOn && snapshot != null) {
        _realismChatSwitch = true;
        _needsSimEnabled = wasNeedsOn;
        _relationshipService.restoreFromMessageState(snapshot);
        _mood.restoreFromStamp(snapshot);
        _nsfwService.restoreNsfwFromMessageState(snapshot);
        _clockWriter.syncLoadedSlotClocks();
        if (wasNeedsOn) {
          final needs = snapshot['needs'];
          if (needs is Map && needs['vector'] is Map) {
            _needsSimulation.restoreFromSnapshot({
              'vector': Map<String, int>.from(needs['vector'] as Map),
            });
          } else {
            _needsSimulation.initializeFresh();
          }
        } else {
          _needsSimulation.clearVector();
        }
      }

      // Enable-flags + author note (persisted by the save that follows) — carry
      // regardless of realism so the NSFW toggle, passage-of-time, chaos, and the
      // note are not reset to defaults on collapse.
      _pockets = solePockets;
      _chaosModeService.loadScalars(
        modeEnabled: soleChaosEnabled,
        pressure: soleChaosPressure,
        nsfwEnabled: soleChaosNsfw,
      );
      _authorNote = soleAuthorNote;
      _authorNoteStrength = soleAuthorStrength;
    };
  }

  /// Carry captured 1:1 [state] onto the host member [hostId]: realism
  /// values only if realism was on; flags, Afterglow, chaos, pockets and the
  /// author note regardless.
  void carryHostScalars(String hostId, Map<String, dynamic> state) {
    final realismOn = state['realismOn'] as bool? ?? false;
    final needsEnabled = state['needsSimEnabled'] as bool? ?? false;
    _needsSimEnabled = needsEnabled;

    // Realism VALUES (gated on realism being on at fork time): relationship +
    // emotion + nsfw + time via the regenerate restore path, then the canonical
    // group-slot write for the host member.
    if (realismOn) {
      _realismChatSwitch = true;
      _relationshipService.restoreFromMessageState(state);
      _mood.restoreFromStamp(state);
      _nsfwService.restoreNsfwFromMessageState(state);
      _clockWriter.syncLoadedSlotClocks();
      if (needsEnabled) {
        final needs = state['needs'];
        if (needs is Map && needs['vector'] is Map) {
          _needsSimulation.restoreFromSnapshot({
            'vector': Map<String, int>.from(needs['vector'] as Map),
          });
        } else {
          _needsSimulation.initializeFresh();
        }
      } else {
        _needsSimulation.clearVector();
      }
      _realismDance.saveScalarsIntoGroup(hostId);
    }

    // Enable-flags (independent of realism; persist via the session columns in
    // both modes) + author note + evolution + objectives carry REGARDLESS.
    // The host's own Afterglow flag also goes on the host MEMBER, realism or
    // not: in a group the chat-level register is per-speaker state, so a value
    // left only there is gone after the first group reply.
    final hostNsfw = state['nsfwCooldownEnabled'] as bool? ?? false;
    _nsfwService.seedFromV2OrExt(nsfwCooldownEnabled: hostNsfw);
    _groupStore.memberForWrite(hostId).nsfwCooldownEnabled = hostNsfw;
    // The group chat takes the 1:1 chat's Afterglow switch.
    _groupStore.afterglowOn = hostNsfw;
    _chaosModeService.loadScalars(
      modeEnabled: state['chaosModeEnabled'] as bool? ?? false,
      pressure: state['chaosPressure'] as int? ?? 0,
      nsfwEnabled: state['chaosNsfwEnabled'] as bool?,
    );

    // Live pockets, regardless of realism — collapse writes the host record
    // from the survivor's; this is the inverse. setActiveGroup cleared the
    // 1:1 record; plant the captured kit on the host member.
    final pocketsJson = state['pockets'];
    if (pocketsJson is Map) {
      setPocketsFor(
        hostId,
        Pockets.fromJson(Map<String, dynamic>.from(pocketsJson)),
      );
    }

    // Author note -> the host member's per-character group note (serialized into
    // group_realism_state by the save).
    final note = state['authorNote'] as String? ?? '';
    if (note.isNotEmpty) {
      _groupAuthorNotes[hostId] = note;
      _groupAuthorNoteStrengths[hostId] =
          state['authorNoteStrength'] as int? ?? 4;
    }
  }
}
