// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Clock beat bookkeeping. The story clock still advances and the time
// chip still stamps. Needs move from the scene eval — not a flat tax on
// every on-need each turn. Continue does not invent a second beat.

part of '../chat_service.dart';

extension ChatServiceBodyWear on ChatService {
  /// After the clock commits. Does not tax every on-need from the minutes —
  /// scene eval moves the bars. Continue is the same beat.
  void _wearBodiesAfterClock(_GenTurn t) {
    if (!_needsSimEnabled) return;
    if (t.mode == GenerationMode.continue_) return;
    _pendingRealismMetadata ??= {};
    _pendingRealismMetadata!['needs_time_wear'] = const <String, int>{};
  }

  /// 1:1 regen when Needs is on: prefer the send-time pre-turn vector,
  /// then the present-body stamp. Realism-off still has to rewind or
  /// the replay wears a second time (80 → 78 → 76).
  void _restoreNeedsBaselineForReplay(ChatMessage msg) {
    if (!_needsSimEnabled) return;
    final preTurn = msg.activeMetadata?['needs_pre_turn_vector'];
    if (preTurn is Map && preTurn.isNotEmpty) {
      _needsSimulation.restoreFromSnapshot({
        'vector': Map<String, int>.from(preTurn),
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
    if (_activeGroup == null) {
      _restoreLiveHostFromBodyMap(before);
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
    }
  }

  /// 1:1 host bars live on the scalar vector, not `_groupRealism`.
  void _restoreLiveHostFromBodyMap(Map<String, Map<String, int>> bodies) {
    if (bodies.isEmpty) return;
    final hostId = _activeCharacter != null
        ? _getCharacterIdFromCard(_activeCharacter!)
        : '';
    final snap =
        bodies[hostId] ?? (bodies.length == 1 ? bodies.values.first : null);
    if (snap == null || snap.isEmpty) return;
    _needsSimulation.restoreFromSnapshot({
      'vector': Map<String, int>.from(snap),
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

  /// A swipe shows the bodies that beat left behind. The speaker is restored
  /// from their own snapshot, which also includes the scene.
  void _restoreWornBodiesExceptSpeaker(ChatMessage msg, String speakerId) {
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
