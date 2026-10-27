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
// One beat's wear on the bodies, for the Needs pass (needs_pass.dart owns
// the gate and the stamps; this file only moves bars). The 1:1 host wears
// on the scalar vector, a group wears every member with a stored body, and
// with the clock off the speaker ticks a fixed step per reply. A night the
// cast slept through wakes every body rested, not only the one who speaks.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/needs_wear.dart';
import 'package:front_porch_ai/services/chat/realism_scope.dart';

/// One beat's wear: what the speaker lost, and every body before and
/// after, with the fractions each carried in.
class BeatWear {
  const BeatWear({
    required this.speakerTaken,
    required this.before,
    required this.after,
    required this.carryBefore,
  });

  static const none = BeatWear(
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

class NeedsBeatWear {
  const NeedsBeatWear(this._scope);

  final RealismScope _scope;

  NeedsSimulation get _needsSimulation => _scope.needs();
  String _idFor(CharacterCard c) => _scope.characterIdFor(c);

  /// Where a body that lived the skip lands, for [ext]'s character.
  Map<String, int> _lived(
    Map<String, int> current,
    FrontPorchExtensions? ext,
  ) => livedSkipBars(
    current: current,
    everyday: NeedsSimulation.baselinesFromExtensions(ext),
    on: needsThatAreOn(NeedsSimulation.needKeys, ext?.needsOff ?? const []),
    enjoysLowHygiene: ext?.enjoysLowHygiene ?? false,
  );

  /// A night slept through ([rested]) wakes [current] rested for [ext].
  Map<String, int> _rested(
    Map<String, int> current,
    FrontPorchExtensions? ext,
  ) => restedBars(
    current: current,
    everyday: NeedsSimulation.baselinesFromExtensions(ext),
    on: needsThatAreOn(NeedsSimulation.needKeys, ext?.needsOff ?? const []),
  );

  /// The speaker's scalars after a rested night: what waking took (negative
  /// for a gain) added to what the night's wear took.
  Map<String, int> _restSpeaker(
    Map<String, int> taken,
    FrontPorchExtensions? ext,
  ) {
    final woke = _needsSimulation.applyLivedSkip(
      _rested(_needsSimulation.vector, ext),
      keepCarry: true,
    );
    return {
      for (final need in {...taken.keys, ...woke.keys})
        need: (taken[need] ?? 0) + (woke[need] ?? 0),
    };
  }

  /// The 1:1 host lives on the scalar vector. [rested]: the cast slept
  /// through the beat, so the host wakes rested after the night's wear.
  BeatWear host(
    int minutes, {
    required bool offScreen,
    required bool lived,
    bool rested = false,
  }) {
    final card = _scope.activeCharacter();
    final ext = card?.frontPorchExtensions;
    final hostId = card != null ? _idFor(card) : '';
    final before = Map<String, int>.from(_needsSimulation.vector);
    if (before.isEmpty) return BeatWear.none;
    final carryBefore = Map<String, double>.from(_needsSimulation.wearCarry);
    final Map<String, int> taken;
    if (lived) {
      taken = _needsSimulation.applyLivedSkip(_lived(before, ext));
    } else {
      final wear = needsWearForSpan(
        minutes: minutes,
        pace: BodyPace.parse(ext?.needsPace),
        on: needsThatAreOn(NeedsSimulation.needKeys, ext?.needsOff ?? const []),
        carry: carryBefore,
      );
      final worn = _needsSimulation.applyTimeWear(
        points: wear.points,
        carry: wear.carry,
        offScreen: offScreen,
      );
      taken = rested ? _restSpeaker(worn, ext) : worn;
    }
    return BeatWear(
      speakerTaken: taken,
      before: {hostId: before},
      after: {hostId: Map<String, int>.from(_needsSimulation.vector)},
      carryBefore: {hostId: carryBefore},
    );
  }

  /// The clock-off beat: the speaker's body alone, a fixed step per reply,
  /// the carry left as it was for when the clock comes back. Version 1
  /// ticked the speaker, not the room, so the room is left alone here too.
  BeatWear tickSpeaker() {
    final group = _scope.activeGroup();
    final card = group == null
        ? _scope.activeCharacter()
        : _scope
              .groupCharacters()
              .where((c) => _idFor(c) == _scope.groups.currentSpeakerId())
              .firstOrNull;
    if (card == null) return BeatWear.none;
    final id = _idFor(card);
    final on = needsThatAreOn(
      needsTickPerReply.keys.toList(),
      card.frontPorchExtensions?.needsOff ?? const [],
    );
    final points = {for (final need in on) need: needsTickPerReply[need]!};
    if (group == null) {
      final before = Map<String, int>.from(_needsSimulation.vector);
      if (before.isEmpty) return BeatWear.none;
      final carry = Map<String, double>.from(_needsSimulation.wearCarry);
      final taken = _needsSimulation.applyTimeWear(
        points: points,
        carry: carry,
        offScreen: false,
      );
      return BeatWear(
        speakerTaken: taken,
        before: {id: before},
        after: {id: Map<String, int>.from(_needsSimulation.vector)},
        carryBefore: {id: carry},
      );
    }
    final stored = _scope.groups.needsOf(id);
    if (stored.isEmpty) return BeatWear.none;
    final carry = Map<String, double>.from(
      _scope.groups.memberForWrite(id).needsWearCarry,
    );
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
    _scope.groups.setNeeds(id, worn);
    final taken = _needsSimulation.applyTimeWear(
      points: points,
      carry: carry,
      offScreen: false,
    );
    return BeatWear(
      speakerTaken: taken,
      before: {id: Map<String, int>.from(stored)},
      after: {id: worn},
      carryBefore: {id: carry},
    );
  }

  /// Every member with a stored body wears, at their own pace, on stage or
  /// away: time passes for the whole cast. The speaker's scalars (loaded
  /// for this turn) wear too, so the eval reads worn bars and the post-gen
  /// save writes them back.
  BeatWear group(
    int minutes, {
    required bool offScreen,
    required bool lived,
    bool rested = false,
  }) {
    final speakerId = _scope.groups.currentSpeakerId();
    final before = <String, Map<String, int>>{};
    final after = <String, Map<String, int>>{};
    final carryBefore = <String, Map<String, double>>{};
    var speakerTaken = const <String, int>{};
    for (final card in _scope.groupCharacters()) {
      final id = _idFor(card);
      final stored = _scope.groups.needsOf(id);
      if (stored.isEmpty) continue;
      final ext = card.frontPorchExtensions;
      final member = _scope.groups.memberForWrite(id);
      final carried = Map<String, double>.from(member.needsWearCarry);
      before[id] = Map<String, int>.from(stored);
      carryBefore[id] = carried;
      if (lived) {
        final bars = _lived(stored, ext);
        _scope.groups.setNeeds(id, bars);
        member.needsWearCarry = const <String, double>{};
        after[id] = bars;
        if (id == speakerId) {
          speakerTaken = _needsSimulation.applyLivedSkip(bars);
        }
        continue;
      }
      final wear = needsWearForSpan(
        minutes: minutes,
        pace: BodyPace.parse(ext?.needsPace),
        on: needsThatAreOn(NeedsSimulation.needKeys, ext?.needsOff ?? const []),
        carry: carried,
      );
      var worn = Map<String, int>.from(stored);
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
      if (rested) worn = _rested(worn, ext);
      _scope.groups.setNeeds(id, worn);
      member.needsWearCarry = wear.carry;
      after[id] = worn;
      if (id == speakerId) {
        final taken = _needsSimulation.applyTimeWear(
          points: wear.points,
          carry: wear.carry,
          offScreen: offScreen,
        );
        speakerTaken = rested ? _restSpeaker(taken, ext) : taken;
      }
    }
    return BeatWear(
      speakerTaken: speakerTaken,
      before: before,
      after: after,
      carryBefore: carryBefore,
    );
  }
}
