// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Awake-time wear, after the clock commits. Continue does not wear.
// A night, a skip, or time away does not wear. Everyone present wears.
// The speaker's scene is applied later, on top.

part of '../chat_service.dart';

extension ChatServiceBodyWear on ChatService {
  BodyPace _paceOf(CharacterCard? card) =>
      BodyPace.parse(card?.frontPorchExtensions?.needsPace);

  int _awakeMinutesForTurn(_GenTurn t) => awakeMinutesForBeat(
    continues: t.mode == GenerationMode.continue_,
    clockRunning: _clockRunning,
    committedAwakeMinutes: _timeService.awakeWearMinutes,
  );

  /// Wear every present body for this beat, then reload the speaker so the
  /// scene eval sees the worn bars. Stashes the wear for the needs chip.
  void _wearBodiesAfterClock(_GenTurn t) {
    if (!_needsSimEnabled || !_realismEnabled) return;
    final minutes = _awakeMinutesForTurn(t);
    if (_activeGroup == null) {
      final host = _activeCharacter;
      final hostId = host != null ? _getCharacterIdFromCard(host) : '';
      final before = Map<String, int>.from(_needsSimulation.vector);
      final wear = awakeWearDeltas(
        minutes,
        _paceOf(host),
        needsThatAreOn(
          NeedsSimulation.needKeys,
          host?.frontPorchExtensions?.needsOff ?? const [],
        ),
      );
      _applyWearToLiveVector(wear);
      // Guest lite ticks wear the 1:1 host. Stamp the pre-wear bars so
      // regen/swipe/delete can restore them — host regen still uses
      // needs_pre_turn_vector + chips, so only guest turns need this receipt.
      if (t.guestSpeaker != null && hostId.isNotEmpty && before.isNotEmpty) {
        _stampPresentWear(
          t,
          {hostId: before},
          {hostId: Map<String, int>.from(_needsSimulation.vector)},
        );
      }
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['needs_time_wear'] = wear;
      return;
    }
    String? speakerId;
    final active = _activeCharacter;
    if (active != null) speakerId = _getCharacterIdFromCard(active);
    final before = <String, Map<String, int>>{};
    final paces = <String, BodyPace>{};
    final on = <String, List<String>>{};
    for (final card in _groupCharacters) {
      if (_groupSpeakerSkips(card) || isSoftGroupMember(card)) continue;
      final id = _getCharacterIdFromCard(card);
      final current = _getGroupNeeds(id);
      before[id] = current.isNotEmpty
          ? Map<String, int>.from(current)
          : NeedsSimulation.baselinesFromExtensions(card.frontPorchExtensions);
      paces[id] = _paceOf(card);
      on[id] = needsThatAreOn(
        NeedsSimulation.needKeys,
        card.frontPorchExtensions?.needsOff ?? const [],
      );
    }
    final worn = wearPresentBodies(
      before: before,
      minutes: minutes,
      paceOf: (id) => paces[id] ?? BodyPace.normal,
      needsOn: (id) => on[id] ?? const [],
    );
    for (final entry in worn.entries) {
      final prior = before[entry.key];
      if (prior != null && _sameNeedBars(prior, entry.value)) continue;
      _setGroupNeeds(entry.key, entry.value);
    }
    Map<String, int> speakerWear = const {};
    if (speakerId != null && before.containsKey(speakerId)) {
      speakerWear = awakeWearDeltas(
        minutes,
        paces[speakerId] ?? BodyPace.normal,
        on[speakerId] ?? const [],
      );
      _loadGroupRealismIntoScalars(speakerId);
      _needsSimulation.applyCatastropheIfNeeded(
        ignore: active?.frontPorchExtensions?.needsOff ?? const [],
      );
      _setGroupNeeds(speakerId, Map<String, int>.from(_needsSimulation.vector));
    }
    _stampPresentWear(t, before, worn);
    _pendingRealismMetadata ??= {};
    _pendingRealismMetadata!['needs_time_wear'] = speakerWear;
  }

  bool _sameNeedBars(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Keep the pre-wear snapshot from the first pass of this reply. Continue
  /// must not replace it, or a later regen would start from bars that were
  /// already worn.
  void _stampPresentWear(
    _GenTurn t,
    Map<String, Map<String, int>> before,
    Map<String, Map<String, int>> worn,
  ) {
    final meta = Map<String, dynamic>.from(
      t.streamTarget.activeMetadata ?? const {},
    );
    meta.putIfAbsent(kNeedsPreWearByMember, () {
      return {
        for (final entry in before.entries)
          entry.key: Map<String, int>.from(entry.value),
      };
    });
    meta[kNeedsWornByMember] = {
      for (final entry in worn.entries)
        entry.key: Map<String, int>.from(entry.value),
    };
    t.streamTarget.activeMetadata = meta;
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

  void _applyWearToLiveVector(Map<String, int> wear) {
    if (wear.isEmpty || _needsSimulation.vector.isEmpty) return;
    final next = Map<String, int>.from(_needsSimulation.vector);
    for (final entry in wear.entries) {
      final cur = next[entry.key] ?? 80;
      next[entry.key] = (cur + entry.value).clamp(0, 100);
    }
    _needsSimulation.restoreFromSnapshot({'vector': next});
    _needsSimulation.applyCatastropheIfNeeded(
      ignore: _activeCharacter?.frontPorchExtensions?.needsOff ?? const [],
    );
  }

  void _stampTimePassedChip(ChatMessage? target) {
    final label = _timeService.bodyTimeLabel;
    if (label == null || label.isEmpty || target == null) return;
    final existing = target.activeMetadata;
    if (existing != null &&
        (existing['time_skip_to'] as String? ?? '').isNotEmpty) {
      return;
    }
    if (existing != null) {
      existing['time_passed'] = label;
    } else {
      target.activeMetadata = {'time_passed': label};
    }
  }
}
