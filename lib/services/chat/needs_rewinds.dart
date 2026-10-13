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
// The Needs rewinds: regen, swipe and delete putting bodies back to the
// stamps a reply carries (needs_pass.dart writes them). State, not runs: a
// stamp came from wear that happened, so these read the chat's stored Needs
// switch, not the live gate, and a chat whose Needs are off still rewinds
// what an earlier turn wore.

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/needs_wear.dart';
import 'package:front_porch_ai/services/chat/realism_scope.dart';

class NeedsRewinds {
  NeedsRewinds(this._scope, {required this.restoreRefractoryAfterBeat});

  final RealismScope _scope;

  /// A swipe's refractory receipt for every co-present body but [speakerId].
  final void Function(ChatMessage msg, String speakerId)
  restoreRefractoryAfterBeat;

  bool get _needsSimEnabled => _scope.needsSimEnabled();
  NeedsSimulation get _needsSimulation => _scope.needs();
  GroupChat? get _activeGroup => _scope.activeGroup();
  CharacterCard? get _activeCharacter => _scope.activeCharacter();
  String _getCharacterIdFromCard(CharacterCard c) => _scope.characterIdFor(c);
  String _getCurrentSpeakerIdForRealism() => _scope.groups.currentSpeakerId();
  Map<String, int> _getGroupNeeds(String id) => _scope.groups.needsOf(id);
  void _setGroupNeeds(String id, Map<String, int> needs) =>
      _scope.groups.setNeeds(id, needs);

  /// 1:1 regen when Needs is on: prefer the send-time pre-turn vector,
  /// then the present-body stamp. Realism-off still has to rewind or
  /// the replay wears a second time (80 → 78 → 76).
  void restoreBaselineForReplay(ChatMessage msg) {
    if (!_needsSimEnabled) return;
    final preTurn = msg.activeMetadata?['needs_pre_turn_vector'];
    if (preTurn is Map && preTurn.isNotEmpty) {
      final carry = msg.activeMetadata?[kNeedsPreTurnCarry];
      _needsSimulation.restoreFromSnapshot({
        'vector': Map<String, int>.from(preTurn),
        if (carry is Map) kNeedsWearCarryKey: carry,
      });
      return;
    }
    restorePresentBodiesForReplay(msg);
  }

  /// Regen loads every present body from the pre-wear snapshot, then the
  /// replayed reply wears them once.
  void restorePresentBodiesForReplay(ChatMessage msg) {
    final before = presentBodiesFromMeta(
      msg.activeMetadata?[kNeedsPreWearByMember],
    );
    if (before.isEmpty) return;
    final carries = presentCarriesFromMeta(
      msg.activeMetadata?[kNeedsPreWearCarryByMember],
    );
    if (_activeGroup == null) {
      _restoreLiveHostFromBodyMap(before, carries: carries);
      return;
    }
    final worn = <String, Map<String, int>>{};
    for (final id in before.keys) {
      final live = _getGroupNeeds(id);
      worn[id] = live.isNotEmpty
          ? Map<String, int>.from(live)
          : Map<String, int>.from(before[id]!);
    }
    final restored = presentBodiesForReplay(before: before, worn: worn);
    for (final entry in restored.entries) {
      _setGroupNeeds(entry.key, entry.value);
      final carry = carries[entry.key];
      if (carry != null) {
        _scope.groups.memberForWrite(entry.key).needsWearCarry = carry;
      }
    }
  }

  /// 1:1 host bars live on the scalar vector, not `_groupRealism`.
  void _restoreLiveHostFromBodyMap(
    Map<String, Map<String, int>> bodies, {
    Map<String, Map<String, double>> carries = const {},
  }) {
    if (bodies.isEmpty) return;
    final hostId = _activeCharacter != null
        ? _getCharacterIdFromCard(_activeCharacter!)
        : '';
    final snap =
        bodies[hostId] ?? (bodies.length == 1 ? bodies.values.first : null);
    if (snap == null || snap.isEmpty) return;
    final carry =
        carries[hostId] ?? (carries.length == 1 ? carries.values.first : null);
    _needsSimulation.restoreFromSnapshot({
      'vector': Map<String, int>.from(snap),
      kNeedsWearCarryKey: ?carry,
    });
  }

  /// Delete gives back this beat's wear to everyone except the speaker.
  /// [capturedBeforeRestore] is those bars before time-travel. The speaker
  /// is refunded from their chip, which already includes wear.
  void _refundPresentWearExcept(
    ChatMessage deleted,
    String? speakerId,
    Map<String, Map<String, int>> capturedBeforeRestore,
  ) {
    if (!_needsSimEnabled) return;
    final refunded = refundCoPresentWear(
      captured: capturedBeforeRestore,
      preWear: presentBodiesFromMeta(
        deleted.activeMetadata?[kNeedsPreWearByMember],
      ),
      worn: presentBodiesFromMeta(deleted.activeMetadata?[kNeedsWornByMember]),
      skipId: speakerId,
    );
    if (_activeGroup == null) {
      _restoreLiveHostFromBodyMap(refunded);
      return;
    }
    for (final entry in refunded.entries) {
      _setGroupNeeds(entry.key, entry.value);
    }
  }

  /// Live bars for everyone this reply wore, read before delete time-travel.
  Map<String, Map<String, int>> capturePresentBeforeDelete(
    ChatMessage deleted,
  ) {
    final ids = <String>{
      ...presentBodiesFromMeta(
        deleted.activeMetadata?[kNeedsPreWearByMember],
      ).keys,
      ...presentBodiesFromMeta(
        deleted.activeMetadata?[kNeedsWornByMember],
      ).keys,
    };
    final out = <String, Map<String, int>>{};
    for (final id in ids) {
      if (_activeGroup == null) {
        final live = _needsSimulation.vector;
        if (live.isEmpty) continue;
        out[id] = Map<String, int>.from(live);
        continue;
      }
      final live = _getGroupNeeds(id);
      if (live.isEmpty) continue;
      out[id] = Map<String, int>.from(live);
    }
    return out;
  }

  /// A swipe shows the bodies that beat left behind, refractory included. The
  /// speaker is restored from their own snapshot, which also includes the
  /// scene.
  void restoreWornBodiesExceptSpeaker(ChatMessage msg, String speakerId) {
    restoreRefractoryAfterBeat(msg, speakerId);
    final worn = presentBodiesFromMeta(msg.activeMetadata?[kNeedsWornByMember]);
    if (_activeGroup == null) {
      final hostOnly = <String, Map<String, int>>{
        for (final entry in worn.entries)
          if (entry.key != speakerId) entry.key: entry.value,
      };
      _restoreLiveHostFromBodyMap(hostOnly);
      return;
    }
    for (final entry in worn.entries) {
      if (entry.key == speakerId) continue;
      _setGroupNeeds(entry.key, Map<String, int>.from(entry.value));
    }
  }

  /// Give back what a deleted message spent.
  ///
  /// A message's chips (`needs_deltas`) ARE the record of what that turn did to
  /// the speaker's needs, so deleting it subtracts those deltas from the
  /// CURRENT scores. Deliberately arithmetic rather than time travel: a message
  /// buried twenty turns back rolls its cost off exactly like the newest one,
  /// which is what the realism snapshot ("restore the state stamped on the new
  /// last message") could never do — it only ever rewound the tail, so a reply
  /// that cost 20 hunger kept costing it forever once deleted.
  ///
  /// [liveBefore] is the speaker's needs captured BEFORE the delete path's
  /// realism time-travel ran. That restore rewinds the whole realism snapshot
  /// (bond/trust/emotion/time) and its needs half would otherwise fight this
  /// arithmetic, so needs are settled here and here only.
  ///
  /// 1:1/group parity: [groupSid] names the DELETED speaker, so a group refund
  /// lands in their own `_groupRealism` entry exactly as a 1:1 refund lands in
  /// the live vector.
  void revertForDeletedMessage(
    ChatMessage deleted,
    Map<String, int> liveBefore, {
    String? groupSid,
    Map<String, Map<String, int>> presentBeforeDelete = const {},
  }) {
    _refundPresentWearExcept(deleted, groupSid, presentBeforeDelete);
    if (!_needsSimEnabled || liveBefore.isEmpty) return;
    final raw = deleted.activeMetadata?['needs_deltas'];
    if (raw is! Map || raw.isEmpty) return;

    final refunded = Map<String, int>.from(liveBefore);
    var changed = false;
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final v = entry.value;
      // Chips are {delta, reason}; tolerate a bare number from older rows.
      final delta = (v is Map && v['delta'] is num)
          ? (v['delta'] as num).toInt()
          : (v is num ? v.toInt() : 0);
      if (delta == 0 || !refunded.containsKey(key)) continue;
      refunded[key] = (refunded[key]! - delta).clamp(0, 100);
      changed = true;
    }
    if (!changed) return;

    if (groupSid != null && groupSid.isNotEmpty) {
      _setGroupNeeds(groupSid, refunded);
      // Keep the live scalars in step when the refunded speaker is the one
      // currently loaded, or the sidebar keeps showing the stale figure.
      if (_getCurrentSpeakerIdForRealism() == groupSid) {
        _needsSimulation.restoreFromSnapshot({'vector': refunded});
      }
    } else {
      _needsSimulation.restoreFromSnapshot({'vector': refunded});
    }
    debugPrint(
      '[Realism:Needs] Deleted message refunded its deltas to '
      '${deleted.sender}${groupSid == null ? '' : ' ($groupSid)'}',
    );
  }
}
