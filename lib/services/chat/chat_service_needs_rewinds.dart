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
// stamps a reply carries (chat_service_needs_pass.dart writes them). State,
// not runs: a stamp came from wear that happened, so these read the chat's
// stored Needs switch, not the live gate, and a chat whose Needs are off
// still rewinds what an earlier turn wore.

part of '../chat_service.dart';

extension ChatServiceNeedsRewinds on ChatService {
  /// 1:1 regen when Needs is on: prefer the send-time pre-turn vector,
  /// then the present-body stamp. Realism-off still has to rewind or
  /// the replay wears a second time (80 → 78 → 76).
  void _restoreNeedsBaselineForReplay(ChatMessage msg) {
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
    _restorePresentBodiesForReplay(msg);
  }

  /// Regen loads every present body from the pre-wear snapshot, then the
  /// replayed reply wears them once.
  void _restorePresentBodiesForReplay(ChatMessage msg) {
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
      if (carry != null) _memberForWrite(entry.key).needsWearCarry = carry;
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
  Map<String, Map<String, int>> _capturePresentNeedsBeforeDelete(
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
  void _restoreWornBodiesExceptSpeaker(ChatMessage msg, String speakerId) {
    _restoreRefractoryAfterBeat(msg, speakerId);
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
}
