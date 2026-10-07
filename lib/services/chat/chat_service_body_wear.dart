// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Clock beat bookkeeping. After the clock commits, every present body
// wears the beat's story minutes at fixed rates (needs_wear.dart); the
// scene eval then scores events on top. Continue does not invent a second
// beat, and a clock that is off records no minutes, so nothing wears.

part of '../chat_service.dart';

extension ChatServiceBodyWear on ChatService {
  /// After the clock commits: wear every present body for the beat's
  /// minutes at that character's pace, with the skip floors off-screen and
  /// the one-warning-turn stop on-screen. What the speaker lost goes to the
  /// post-gen pending map (`needs_time_wear`, scratch the chip step reads);
  /// every present body before and after, with the fraction each carried
  /// in, is stamped on the reply itself, because the pending map never
  /// reaches the message and regen and delete read the message.
  void _wearBodiesAfterClock(_GenTurn t) {
    if (!_needsSimEnabled) return;
    if (t.mode == GenerationMode.continue_) return;
    _pendingRealismMetadata ??= {};
    final minutes = _timeService.bodyWearMinutes;
    final offScreen = _timeService.bodyBeatOffScreen;
    var beat = _BeatWear.none;
    if (minutes > 0) {
      beat = _activeGroup == null
          ? _wearHost(minutes, offScreen: offScreen)
          : _wearGroup(minutes, offScreen: offScreen);
    }
    if (beat.before.isNotEmpty) {
      // Mutate the attached slot in place: the legacy `metadata` field
      // shares that map, and replacing the slot would leave it behind
      // without the clock stamps written after this (clock_trust_stamp).
      final slot = t.streamTarget.activeMetadata;
      final meta = slot ?? <String, dynamic>{};
      meta[kNeedsPreWearByMember] = beat.before;
      meta[kNeedsWornByMember] = beat.after;
      meta[kNeedsPreWearCarryByMember] = beat.carryBefore;
      if (slot == null) t.streamTarget.activeMetadata = meta;
    }
    _pendingRealismMetadata!['needs_time_wear'] = {
      for (final e in beat.speakerTaken.entries) e.key: -e.value,
    };
  }

  /// The 1:1 host lives on the scalar vector.
  _BeatWear _wearHost(int minutes, {required bool offScreen}) {
    final card = _activeCharacter;
    final ext = card?.frontPorchExtensions;
    final hostId = card != null ? _getCharacterIdFromCard(card) : '';
    final before = Map<String, int>.from(_needsSimulation.vector);
    if (before.isEmpty) return _BeatWear.none;
    final carryBefore = Map<String, double>.from(_needsSimulation.wearCarry);
    final wear = needsWearForSpan(
      minutes: minutes,
      pace: BodyPace.parse(ext?.needsPace),
      on: needsThatAreOn(NeedsSimulation.needKeys, ext?.needsOff ?? const []),
      carry: carryBefore,
    );
    final taken = _needsSimulation.applyTimeWear(
      points: wear.points,
      carry: wear.carry,
      offScreen: offScreen,
    );
    return _BeatWear(
      speakerTaken: taken,
      before: {hostId: before},
      after: {hostId: Map<String, int>.from(_needsSimulation.vector)},
      carryBefore: {hostId: carryBefore},
    );
  }

  /// Every member with a stored body wears, at their own pace. The speaker's
  /// scalars (loaded for this turn) wear too, so the eval reads worn bars and
  /// the post-gen save writes them back.
  _BeatWear _wearGroup(int minutes, {required bool offScreen}) {
    final speakerId = _getCurrentSpeakerIdForRealism();
    final before = <String, Map<String, int>>{};
    final after = <String, Map<String, int>>{};
    final carryBefore = <String, Map<String, double>>{};
    var speakerTaken = const <String, int>{};
    for (final card in _groupCharacters) {
      final id = _getCharacterIdFromCard(card);
      final stored = _getGroupNeeds(id);
      if (stored.isEmpty) continue;
      final ext = card.frontPorchExtensions;
      final member = _memberForWrite(id);
      final carried = Map<String, double>.from(member.needsWearCarry);
      final wear = needsWearForSpan(
        minutes: minutes,
        pace: BodyPace.parse(ext?.needsPace),
        on: needsThatAreOn(NeedsSimulation.needKeys, ext?.needsOff ?? const []),
        carry: carried,
      );
      before[id] = Map<String, int>.from(stored);
      carryBefore[id] = carried;
      final worn = Map<String, int>.from(stored);
      for (final e in wear.points.entries) {
        final current = worn[e.key];
        if (current == null) continue;
        worn[e.key] = wornBar(
          need: e.key,
          current: current,
          drop: e.value,
          offScreen: offScreen,
        );
      }
      _setGroupNeeds(id, worn);
      member.needsWearCarry = wear.carry;
      after[id] = worn;
      if (id == speakerId) {
        speakerTaken = _needsSimulation.applyTimeWear(
          points: wear.points,
          carry: wear.carry,
          offScreen: offScreen,
        );
      }
    }
    return _BeatWear(
      speakerTaken: speakerTaken,
      before: before,
      after: after,
      carryBefore: carryBefore,
    );
  }

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

/// One beat's wear: what the speaker lost, and every present body before
/// and after, with the fractions each carried in.
class _BeatWear {
  const _BeatWear({
    required this.speakerTaken,
    required this.before,
    required this.after,
    required this.carryBefore,
  });

  static const none = _BeatWear(
    speakerTaken: {},
    before: {},
    after: {},
    carryBefore: {},
  );

  final Map<String, int> speakerTaken;
  final Map<String, Map<String, int>> before;
  final Map<String, Map<String, int>> after;
  final Map<String, Map<String, double>> carryBefore;
}
