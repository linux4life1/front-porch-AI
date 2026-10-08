// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Needs pass: the one place Needs run from, behind one gate.
//
// Disabled means disabled. [_needsActive] is the gate (the Realism engine,
// this chat's Needs switch, the global Needs switch read live), and every
// way Needs run reads it: the pre-turn stamp, the prompt lines and the
// judge (wired to it in chat_service_wiring_*), the clock's wear, the chip
// under the reply, Reprocess Needs. Off, none of them run and nothing of
// Needs is written. What this file does not gate on [_needsActive] is
// state and rewinds: the bars seeded from a card or a session (the
// chat's stored switch), and regen / delete undoing a stamp a reply
// already carries, which came from wear that happened.
// test/hygiene/needs_gate_ratchet_test.dart keeps new Needs code here.
//
// The wear: after the clock commits, every present body wears the beat's
// story minutes at fixed rates (needs_wear.dart); the scene eval then
// scores events on top. With the clock off the reply is the beat: the
// speaker's hunger, bladder and energy tick a fixed step (version 1's
// per-turn tick, the maintainer's ruling of 2026-10-08), so the body still
// moves between events. Continue does not invent a second beat. The
// rewinds of these stamps live in chat_service_needs_rewinds.dart.

part of '../chat_service.dart';

extension ChatServiceNeedsPass on ChatService {
  /// After the clock commits: wear every present body for the beat's
  /// minutes at that character's pace, with the skip floors off-screen and
  /// the one-warning-turn stop on-screen. What the speaker lost goes to the
  /// post-gen pending map (`needs_time_wear`, scratch the chip step reads);
  /// every present body before and after, with the fraction each carried
  /// in, is stamped on the reply itself, because the pending map never
  /// reaches the message and regen and delete read the message.
  /// Needs are moving for this chat: the per-chat switch, the global one
  /// read live (as objectivesActive does, so "off" takes effect on the next
  /// turn rather than the next reopen), and the Realism engine, which Needs
  /// require (the Porch Life tab says so). Before v2 the only way a need
  /// moved was the needs judge, behind the engine; the clock's wear must
  /// not get past that gate, or a reply with the engine off shows
  /// "Bladder −1" (a user's report on v1.5.0).
  bool get _needsActive =>
      _realismEnabled &&
      _needsSimEnabled &&
      _storageService.realismSettings.needsSimDefault;

  /// The pre-turn stamp: the body as it is before this reply, with the
  /// carried fraction, on the pending map, so regen and the chip rewind to
  /// the turn's base. 1:1 stamps the live vector; a group stamps the
  /// speaker's own bars (or the card's baselines on a first turn) and that
  /// member's carry, and loads the speaker into the scalars. Returns the
  /// vector stamped, or null when nothing was.
  Map<String, int>? _needsStampPreTurn({CharacterCard? groupSpeaker}) {
    if (!_needsActive) return null;
    if (groupSpeaker == null) {
      if (_needsSimulation.vector.isEmpty) return null;
      final preTurnVector = Map<String, int>.from(_needsSimulation.vector);
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['needs_pre_turn_vector'] = preTurnVector;
      // The carried fraction rewinds with the bars, so a regen charges the
      // beat exactly once more, not from a reset carry.
      _pendingRealismMetadata![kNeedsPreTurnCarry] = Map<String, double>.from(
        _needsSimulation.wearCarry,
      );
      return preTurnVector;
    }
    final charId = _getCharacterIdFromCard(groupSpeaker);
    final currentForSpeaker = _getGroupNeeds(charId);
    final preTurn = currentForSpeaker.isNotEmpty
        ? Map<String, int>.from(currentForSpeaker)
        : NeedsSimulation.baselinesFromExtensions(
            groupSpeaker.frontPorchExtensions,
          );
    _pendingRealismMetadata ??= {};
    _pendingRealismMetadata!['needs_pre_turn_vector'] = preTurn;
    _pendingRealismMetadata![kNeedsPreTurnCarry] = Map<String, double>.from(
      _memberForWrite(charId).needsWearCarry,
    );
    _loadGroupRealismIntoScalars(charId);
    return preTurn;
  }

  void _wearBodiesAfterClock(_GenTurn t) {
    if (!_needsActive) return;
    if (t.mode == GenerationMode.continue_) return;
    _pendingRealismMetadata ??= {};
    _pendingRealismMetadata!['needs_time_wear'] = const <String, int>{};
    _wearBeatOn(t.streamTarget);
  }

  /// Wears whatever minutes the clock has not yet charged, taking them so
  /// they cannot be charged twice, and records the result on [target]. A
  /// second call in the same turn (a named-time correction read from the
  /// reply) keeps the first call's "before" and extends its "after" and
  /// the chip's time part. With the clock off the reply itself is the
  /// beat: the speaker ticks [needsTickPerReply], through the same stamps,
  /// so regen, swipe and delete rewind it the same way.
  void _wearBeatOn(ChatMessage target) {
    if (!_needsActive) return;
    final _BeatWear beat;
    if (_clockRunning) {
      final minutes = _timeService.takeBodyWearMinutes();
      if (minutes <= 0) return;
      final offScreen = _timeService.bodyBeatOffScreen;
      beat = _activeGroup == null
          ? _wearHost(minutes, offScreen: offScreen)
          : _wearGroup(minutes, offScreen: offScreen);
    } else {
      beat = _tickSpeaker();
    }
    if (beat.before.isNotEmpty) {
      // Mutate the attached slot in place: the legacy `metadata` field
      // shares that map, and replacing the slot would leave it behind
      // without the clock stamps written after this (clock_trust_stamp).
      final slot = target.activeMetadata;
      final meta = slot ?? <String, dynamic>{};
      meta.putIfAbsent(kNeedsPreWearByMember, () => beat.before);
      meta.putIfAbsent(kNeedsPreWearCarryByMember, () => beat.carryBefore);
      meta[kNeedsWornByMember] = beat.after;
      if (slot == null) target.activeMetadata = meta;
    }
    _pendingRealismMetadata ??= {};
    final wear = Map<String, int>.from(
      (_pendingRealismMetadata!['needs_time_wear'] as Map?)
              ?.cast<String, int>() ??
          const <String, int>{},
    );
    for (final e in beat.speakerTaken.entries) {
      wear[e.key] = (wear[e.key] ?? 0) - e.value;
    }
    _pendingRealismMetadata!['needs_time_wear'] = wear;
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

  /// The clock-off beat: the speaker's body alone, a fixed step per reply,
  /// the carry left as it was for when the clock comes back. Version 1
  /// ticked the speaker, not the room, so the room is left alone here too.
  _BeatWear _tickSpeaker() {
    final card = _activeGroup == null
        ? _activeCharacter
        : _groupCharacters
              .where(
                (c) =>
                    _getCharacterIdFromCard(c) ==
                    _getCurrentSpeakerIdForRealism(),
              )
              .firstOrNull;
    if (card == null) return _BeatWear.none;
    final id = _getCharacterIdFromCard(card);
    final on = needsThatAreOn(
      needsTickPerReply.keys.toList(),
      card.frontPorchExtensions?.needsOff ?? const [],
    );
    final points = {for (final need in on) need: needsTickPerReply[need]!};
    if (_activeGroup == null) {
      final before = Map<String, int>.from(_needsSimulation.vector);
      if (before.isEmpty) return _BeatWear.none;
      final carry = Map<String, double>.from(_needsSimulation.wearCarry);
      final taken = _needsSimulation.applyTimeWear(
        points: points,
        carry: carry,
        offScreen: false,
      );
      return _BeatWear(
        speakerTaken: taken,
        before: {id: before},
        after: {id: Map<String, int>.from(_needsSimulation.vector)},
        carryBefore: {id: carry},
      );
    }
    final stored = _getGroupNeeds(id);
    if (stored.isEmpty) return _BeatWear.none;
    final carry = Map<String, double>.from(_memberForWrite(id).needsWearCarry);
    final worn = Map<String, int>.from(stored);
    for (final e in points.entries) {
      final current = worn[e.key];
      if (current == null) continue;
      worn[e.key] = wornBar(
        need: e.key,
        current: current,
        drop: e.value,
        offScreen: false,
      );
    }
    _setGroupNeeds(id, worn);
    final taken = _needsSimulation.applyTimeWear(
      points: points,
      carry: carry,
      offScreen: false,
    );
    return _BeatWear(
      speakerTaken: taken,
      before: {id: Map<String, int>.from(stored)},
      after: {id: worn},
      carryBefore: {id: carry},
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

  Map<String, int> _coerceNeedsVector(dynamic src) {
    if (src == null) return const {};
    if (src is Map<String, int>) return Map<String, int>.from(src);
    if (src is Map) {
      final out = <String, int>{};
      src.forEach((k, v) {
        final key = k.toString();
        if (v is num) {
          out[key] = v.toInt();
        } else if (v is int) {
          out[key] = v;
        }
      });
      return out;
    }
    return const {};
  }

  /// Compute + attach this message's needs-delta chips (`needs_deltas`) from the
  /// speaker's pre-turn baseline to their post-turn (decay + impact) needs.
  ///
  /// Called from `_generateResponse` so EVERY generated turn gets chips — 1:1
  /// host, group first responder, group auto-advance (`triggerNextCharacter`),
  /// and `/speak` alike. The old block lived only in `sendMessage`, so any group
  /// speaker after the first (who reaches `_generateResponse` by another door)
  /// showed no needs chips even though their needs were simulated correctly.
  ///
  /// Baseline is the message's own `needs_pre_turn_vector` — stamped per-speaker
  /// (1:1 in `sendMessage` pre-tick; group in the realism dance pre-decay) — with
  /// the `realism_state` snapshot's needs vector as a fallback. No-op when there
  /// is no baseline or no net change (`message_bubble` hides zero-delta needs).
  ///
  /// Deliberately a pure in-memory mutator with NO save of its own. It used to
  /// end in `_saveChat()`, and because it is the LAST thing the post-generation
  /// block does, that made it the accidental persist for the whole phase — one
  /// that never ran when Needs was off, silently costing the spatial stance
  /// (and anything else written after the phase's first save) its trip to
  /// disk. The persist now lives at the end of the block in
  /// `chat_service_generation_postgen.dart`, where it covers every pass rather
  /// than one feature's slice.
  void _attachNeedsDeltaChipToLastMessage() {
    if (!_needsActive || _messages.isEmpty) return;
    var preVec = _coerceNeedsVector(
      _messages.last.activeMetadata?['needs_pre_turn_vector'],
    );
    if (preVec.isEmpty) {
      preVec = _coerceNeedsVector(
        (_messages.last.activeMetadata?['realism_state']
            as Map<String, dynamic>?)?['needs']?['vector'],
      );
    }
    if (preVec.isEmpty) return;
    final needsDeltas = _needsSimulation.computeNeedsDeltasWithReasons(preVec);
    final senderCard = (_activeGroup != null && !_observerMode)
        ? resolveGroupSpeakerForMessage(_groupCharacters, _messages.last) ??
              _activeCharacter
        : _activeCharacter;
    needsDeltas.removeWhere(
      (key, _) => !visibleNeedsFor({key: 1}, senderCard).containsKey(key),
    );
    final wear = _pendingRealismMetadata?['needs_time_wear'];
    final passed = _timeService.bodyTimeLabel;
    if (wear is Map && passed != null && passed.isNotEmpty) {
      for (final entry in needsDeltas.entries) {
        final row = entry.value;
        if (row is! Map) continue;
        final worn = wear[entry.key];
        final delta = row['delta'];
        if (worn is! int || worn >= 0 || delta is! int || delta >= 0) continue;
        final scene = row['reason'];
        row['reason'] =
            (scene is String && scene.isNotEmpty && scene != 'Natural decay')
            ? '$passed · $scene'
            : passed;
      }
    }
    final meta = Map<String, dynamic>.from(
      _messages.last.activeMetadata ?? const {},
    );
    if (needsDeltas.isEmpty) {
      // Write the swipe slot. A short no-action turn must still prove
      // Needs ran — bars stay put, this chip is the receipt.
      meta[kNeedsUnaffectedMeta] = true;
      meta.remove('needs_deltas');
      _messages.last.activeMetadata = meta;
      debugPrint(
        '[Realism:Needs] Chip: no needs affected for ${_messages.last.sender}',
      );
      return;
    }
    meta.remove(kNeedsUnaffectedMeta);
    meta['needs_deltas'] = needsDeltas;
    _messages.last.activeMetadata = meta;
    debugPrint(
      '[Realism:Needs] Chip: ${needsDeltas.length} need delta(s) attached for '
      '${_messages.last.sender}',
    );
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
