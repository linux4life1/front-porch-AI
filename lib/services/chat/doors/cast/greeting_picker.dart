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

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';

/// The opening greeting: which one is showing, its macros, and the opening
/// Realism and Needs seed a greeting commit applies.
///
/// One body for 1:1 and group: the owner card's overlay is merged onto the
/// card (1:1) or that member's group baseline (group), then written into the
/// live scalars. Swiping back to greeting 0 re-applies the base; it does not
/// keep leftover mood from an angry alt.
class GreetingPicker {
  GreetingPicker(this._door, this._d);

  final CastDoor _door;
  final CastDeps _d;

  /// The alternate greeting showing as the opening bubble.
  int greetingIndex = 0;

  ChatSessionState get _session => _d.session;
  CastShellHooks get _h => _d.hooks;
  TurnEngine get _turn => _d.turn();
  RealismGraph get _graph => _d.graph();
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  RealismScope get _scope => _d.realism();
  RelationshipService get _relationshipService => _scope.relationship();
  TimeService get _timeService => _scope.time();
  NsfwService get _nsfwService => _scope.nsfw();
  GroupRealismStore get _groupStore => _scope.groups;
  MoodRegisters get _mood => _d.mood();
  RealismDance get _realismDance => _d.dance();
  RealismSnapshot get _realismSnapshot => _d.snapshot();
  StoryClockWriter get _clockWriter => _d.clockWriter();
  GreetingBaseline get _baseline => _door.baseline;

  /// Bump the greeting-eval generation and cancel any in-flight unauthored
  /// Read the Room, so a late apply cannot paint the previous opening onto a
  /// newly loaded first_mes (New Chat, switch, swipe, load, import, fork).
  Future<void> invalidateGreetingEval() async {
    _turn.greetingEval.bump();
    await _turn.stops.cancelRealismEval();
    _d.graph().evalStatus.cancelled = false;
    // A switch or new opening is not the user stopping a reply.
    _door.guests.stoppedReplyAnchor = null;
  }

  /// Cycle the first message through alternate greetings.
  /// Commit-once: the same `selectGreeting` path the picker uses.
  Future<void> cycleGreeting(int direction) async {
    if (_session.messages.isEmpty) return;
    final allGreetings = _h.openingAllGreetings();
    if (allGreetings.length <= 1) return;

    var next = (greetingIndex + direction) % allGreetings.length;
    if (next < 0) next += allGreetings.length;
    await _h.selectGreeting(next);
  }

  String buildFirstMessage(CharacterCard character, {String? greetingText}) {
    String msg = greetingText ?? character.firstMessage;
    return _d.macros.resolve(
      msg,
      MacroContext(
        userName: _d.personas.persona.name,
        characterName: character.name,
      ),
      section: 'firstMessage',
    );
  }

  /// First displayed member greet, as 1:1 [CharacterCard.allGreetings].
  /// Empty when the member has no usable opening (whitespace first_mes and
  /// no alts). Group open must not gate on [CharacterCard.firstMessage].
  String memberOpeningGreetingText(CharacterCard member) {
    final opening = member.allGreetings;
    if (opening.isEmpty) return '';
    return buildFirstMessage(member, greetingText: opening.first);
  }

  /// Who owns the opening bubble. Custom group greetings have no member id
  /// and therefore no alt-greet picker.
  CharacterCard? greetingOwnerCard() {
    if (_activeGroup == null) return _session.activeCharacter;
    if (_session.messages.isEmpty) {
      return _groupCharacters.isEmpty ? null : _groupCharacters.first;
    }
    final cid = _session.messages.first.characterId;
    if (cid == null || cid.isEmpty) return null;
    for (final c in _groupCharacters) {
      if (_d.characterIdFor(c) == cid) return c;
    }
    return null;
  }

  bool get isOpeningGreetingChat =>
      _session.messages.length == 1 && !_session.messages.first.isUser;

  /// Existing chat start. Null only for a new chat whose live is still
  /// today so creation can seed today once. A lived-in clock that already
  /// left today is never treated as unseeded.
  String? _keptPersistedStartIso() {
    final loaded = StoryClock.dateOnly(_timeService.startDate);
    final today = StoryClock.todayAnchor();
    if (loaded != today) return _timeService.storyStartDateIso;
    if (StoryClock.dateOnly(_timeService.clock) != today) {
      return StoryClock.serializeDate(
        StoryClock.dateOnly(
          _timeService.clock,
        ).subtract(Duration(days: _timeService.dayCount - 1)),
      );
    }
    return null;
  }

  GreetingOpeningBase _openingBaseFor(
    CharacterCard card, {
    required String? memberId,
  }) {
    final ext = card.frontPorchExtensions;
    final cardBase = ext?.openingBase ?? const GreetingOpeningBase();
    if (_activeGroup == null || memberId == null) return cardBase;

    final seeds = parseGroupRealismSeeds(
      _activeGroup!.defaultMemberRealismState,
    );
    final raw = seeds[memberId];
    final time = parseGroupTimeSeedOf(_activeGroup!);
    if (raw == null && time == null) return cardBase;

    Map<String, int> needsOf(String key, int fallback) {
      final n = raw?['needs'];
      if (n is Map && n[key] is num) return {key: (n[key] as num).toInt()};
      return {key: fallback};
    }

    int need(String key, int fallback) => needsOf(key, fallback)[key]!;

    final inv = raw?['pockets'] ?? raw?['inventory'];
    return GreetingOpeningBase(
      shortTermBond:
          (raw?['affection'] as num?)?.toInt() ?? cardBase.shortTermBond,
      longTermBond:
          (raw?['longTermScore'] as num?)?.toInt() ?? cardBase.longTermBond,
      trustLevel: (raw?['trust'] as num?)?.toInt() ?? cardBase.trustLevel,
      dayCount: time?.dayCount ?? cardBase.dayCount,
      timeOfDay: time?.timeOfDay ?? cardBase.timeOfDay,
      storyStartDate: time?.storyStartDate ?? cardBase.storyStartDate,
      storyStartTime: time?.storyStartTime ?? cardBase.storyStartTime,
      characterEmotion:
          (raw?['emotion'] as String?) ?? cardBase.characterEmotion,
      emotionIntensity:
          (raw?['emotionIntensity'] as String?) ?? cardBase.emotionIntensity,
      currentTask: cardBase.currentTask,
      needsBaselineHunger: need('hunger', cardBase.needsBaselineHunger),
      needsBaselineBladder: need('bladder', cardBase.needsBaselineBladder),
      needsBaselineEnergy: need('energy', cardBase.needsBaselineEnergy),
      needsBaselineSocial: need('social', cardBase.needsBaselineSocial),
      needsBaselineFun: need('fun', cardBase.needsBaselineFun),
      needsBaselineHygiene: need('hygiene', cardBase.needsBaselineHygiene),
      needsBaselineComfort: need('comfort', cardBase.needsBaselineComfort),
      inventory: inv is Map
          ? Map<String, dynamic>.from(inv)
          : cardBase.inventory,
    );
  }

  /// Re-seed live opening state from the card/group base plus this
  /// greeting's overlay. Call only while the chat is still greeting-only.
  Future<void> applyGreetingOpeningSeed({
    required CharacterCard card,
    required int index,
    bool scheduleEval = true,
  }) async {
    final ext = card.frontPorchExtensions;
    final firstMesEmpty = greetingFirstMesEmpty(card.firstMessage);
    final overlay = greetingOverlayAt(
      ext?.greetingSeeds ?? const [],
      index,
      firstMesEmpty: firstMesEmpty,
    );
    final memberId = _activeGroup == null ? null : _d.characterIdFor(card);
    final resolved = resolveGreetingOpening(
      _openingBaseFor(card, memberId: memberId),
      overlay,
    );

    _relationshipService.resetForFreshChat();
    _relationshipService.seedFromCardV2OrExt(
      shortTermBond: resolved.shortTermBond,
      longTermBond: resolved.longTermBond,
      trustLevel: resolved.trustLevel,
    );
    _mood.seed(resolved.characterEmotion, resolved.emotionIntensity);
    // Reload re-applies authored mood/needs. It must not invent a
    // Day-1 / today clock over a lived-in session row (HIGH-1).
    if (scheduleEval) {
      _timeService.seedFromV2OrExt(
        dayCount: resolved.dayCount,
        timeOfDay: resolved.timeOfDay,
        storyStartDate: resolved.storyStartDate ?? _keptPersistedStartIso(),
        storyStartTime: resolved.storyStartTime,
      );
      _graph.applySeededPassageOfTime();
    }
    _nsfwService.resetRuntimeArousalAndCooldown();

    _graph.seeds.greetingNeeds(resolved.needsBaselines);

    final greetingPocketsId = memberId ?? _d.characterIdFor(card);
    if (_graph.pocketsEnabledFor(greetingPocketsId)) {
      final pockets = Pockets.fromJson(resolved.inventory);
      if (pockets.isEmpty) {
        final fromCard = PocketsLedger.startingPocketsFor(card);
        if (fromCard.isEmpty) {
          if (_activeGroup == null) {
            _graph.hostPockets = null;
          } else {
            _groupStore.memberForWrite(greetingPocketsId).pockets = null;
          }
        } else {
          _graph.setPocketsFor(greetingPocketsId, fromCard);
        }
      } else {
        _graph.setPocketsFor(greetingPocketsId, pockets);
      }
    }

    _baseline.openingPostureSeededFor = null;
    if (_activeGroup != null && memberId != null) {
      _realismDance.saveScalarsIntoGroup(memberId);
    }

    final objectives = _d.objectives();
    objectives.activeObjectives = [];
    objectives.writer.importAuthoredTask(
      FrontPorchExtensions(currentTask: resolved.currentTask),
      target: card,
    );

    _stampOpening(index, scheduleEval: scheduleEval);

    if (!scheduleEval) return;
    final authored = greetingHasAuthoredSeed(
      hasCardExtensions: ext != null,
      seeds: ext?.greetingSeeds ?? const [],
      greetingIndex: index,
      firstMesEmpty: firstMesEmpty,
    );
    _readRoomOrSeedPosture(
      index,
      authored: authored,
      firstMesEmpty: firstMesEmpty,
    );
  }

  /// The opening bubble's greeting index, mood and (on a fresh commit) its
  /// realism snapshot and seed clock.
  void _stampOpening(int index, {required bool scheduleEval}) {
    if (_session.messages.isEmpty) return;
    _session.messages.first.activeMetadata ??= {};
    _session.messages.first.activeMetadata![kGreetingIndexMetadataKey] = index;
    final emotion = _scope.emotion();
    if (emotion.isNotEmpty) {
      _session.messages.first.activeMetadata!['emotion_label'] = emotion;
    }
    // Reload must not invent a greeting snap / dayCount. That leftover is
    // frozen (equals itself) and the dayCount rung then synthesises
    // afternoon instead of the session live clock (HIGH-1).
    if (scheduleEval) {
      _session.messages.first.activeMetadata!['realism_state'] =
          _realismSnapshot.capture();
      _clockWriter.writeSlotClock(
        _session.messages.isEmpty ? null : _session.messages.first,
        kind: SlotClockWrite.seed,
      );
    }
  }

  /// An unauthored greeting Reads the Room; an authored one seeds only the
  /// opening position.
  void _readRoomOrSeedPosture(
    int index, {
    required bool authored,
    required bool firstMesEmpty,
  }) {
    if (shouldReadRoomForGreeting(
          index,
          hasAuthoredSeed: authored,
          firstMesEmpty: firstMesEmpty,
        ) &&
        _graph.realismActiveThisMode) {
      unawaited(_baseline.runPostGreetingEval());
    } else if (_graph.realismActiveThisMode) {
      unawaited(_baseline.seedOpeningPosture().catchError((Object _) {}));
    }
  }

  void stampGreetingIndex(int index) {
    if (_session.messages.isEmpty) return;
    _session.messages.first.activeMetadata ??= {};
    _session.messages.first.activeMetadata![kGreetingIndexMetadataKey] = index;
  }

  void restoreGreetingIndex() {
    if (_session.messages.isEmpty) {
      greetingIndex = 0;
      return;
    }
    final resolved = _h.resolvedOpeningGreetings();
    greetingIndex = recoverGreetingIndex(
      resolvedGreetings: resolved,
      currentText: _session.messages.first.text,
      storedIndex:
          _session.messages.first.activeMetadata?[kGreetingIndexMetadataKey],
    );
  }

  /// Custom group first_message + alts: one overlay fans out to the story
  /// clock and every member's opening slot. Unauthored alts Read the Room
  /// like 1:1; an authored overlay (including `{}`) skips.
  Future<void> applyGroupCustomGreetingSeed(
    int index, {
    bool scheduleEval = true,
  }) async {
    final group = _activeGroup;
    if (group == null) return;
    final firstMesEmpty = greetingFirstMesEmpty(group.firstMessage);
    final overlay = greetingOverlayAt(
      group.greetingSeeds,
      index,
      firstMesEmpty: firstMesEmpty,
    );
    final time = parseGroupTimeSeedOf(group);
    final timeResolved = resolveGreetingOpening(
      GreetingOpeningBase(
        dayCount: time?.dayCount ?? 1,
        timeOfDay: time?.timeOfDay ?? 'morning',
        storyStartDate: time?.storyStartDate,
        storyStartTime: time?.storyStartTime,
      ),
      overlay,
    );
    if (scheduleEval) {
      _timeService.seedFromV2OrExt(
        dayCount: timeResolved.dayCount,
        timeOfDay: timeResolved.timeOfDay,
        storyStartDate: timeResolved.storyStartDate ?? _keptPersistedStartIso(),
        storyStartTime: timeResolved.storyStartTime,
      );
      _graph.applySeededPassageOfTime();
    }

    for (final c in _groupCharacters) {
      final memberId = _d.characterIdFor(c);
      final resolved = resolveGreetingOpening(
        _openingBaseFor(c, memberId: memberId),
        overlay,
      );
      final slot = _groupStore.memberForWrite(memberId);
      slot.affection = resolved.shortTermBond;
      slot.longTermScore = resolved.longTermBond;
      slot.trust = resolved.trustLevel;
      slot.emotion = resolved.characterEmotion;
      slot.emotionIntensity = resolved.emotionIntensity;
      // An authored starting mood has no cause and no hold.
      slot.emotionCause = '';
      slot.emotionHeldTurns = 0;
      slot.spatialStance = '';
      _graph.seeds.slotNeeds(slot, resolved.needsBaselines);
      if (_graph.pocketsEnabledFor(_d.characterIdFor(c))) {
        final pockets = Pockets.fromJson(resolved.inventory);
        slot.pockets = pockets.isEmpty
            ? PocketsLedger.startingPocketsFor(c)
            : pockets;
      }
    }
    _baseline.openingPostureSeededFor = null;
    if (_groupCharacters.isNotEmpty) {
      _realismDance.loadIntoScalars(_d.characterIdFor(_groupCharacters.first));
    }

    _stampOpening(index, scheduleEval: scheduleEval);

    if (!scheduleEval) return;
    final authored =
        greetingOverlayAt(
          group.greetingSeeds,
          index,
          firstMesEmpty: firstMesEmpty,
        ) !=
        null;
    _readRoomOrSeedPosture(
      index,
      authored: authored,
      firstMesEmpty: firstMesEmpty,
    );
  }

  /// After unauthored group RtR, persist live scalars into the current cast
  /// so persist + first-speaker [RealismDance.loadIntoScalars] keep the eval.
  /// Member-greet and custom opener share this fan-out. Whitespace first_mes
  /// is not a custom opener and must not write only [evalChar].
  void writeBackGreetingEvalToGroupSlots(CharacterCard? evalChar) {
    if (_activeGroup == null) return;
    if (_groupCharacters.isNotEmpty) {
      for (final c in _groupCharacters) {
        _realismDance.saveScalarsIntoGroup(_d.characterIdFor(c));
      }
      return;
    }
    if (evalChar != null) {
      _realismDance.saveScalarsIntoGroup(_d.characterIdFor(evalChar));
    }
  }

  /// After reload restores the greeting cursor, re-apply that index's
  /// *authored* overlay so swipe-committed fury / {} survive hydrate.
  /// Unauthored (null) overlays must not write inherit over a persisted
  /// RtR: load already hydrated curious; re-eval is the named leftover.
  Future<void> reapplyOpeningOverlayIfNeeded() async {
    if (!isOpeningGreetingChat) return;
    final groupCustom =
        _activeGroup != null &&
        !greetingFirstMesEmpty(_activeGroup!.firstMessage);
    if (groupCustom) {
      final authored =
          greetingOverlayAt(
            _activeGroup!.greetingSeeds,
            greetingIndex,
            firstMesEmpty: false,
          ) !=
          null;
      if (!authored) return;
      await applyGroupCustomGreetingSeed(greetingIndex, scheduleEval: false);
      return;
    }
    final owner = greetingOwnerCard() ?? _session.activeCharacter;
    if (owner != null) {
      final ext = owner.frontPorchExtensions;
      final firstMesEmpty = greetingFirstMesEmpty(owner.firstMessage);
      final authored = greetingHasAuthoredSeed(
        hasCardExtensions: ext != null,
        seeds: ext?.greetingSeeds ?? const [],
        greetingIndex: greetingIndex,
        firstMesEmpty: firstMesEmpty,
      );
      if (!authored) return;
      await applyGreetingOpeningSeed(
        card: owner,
        index: greetingIndex,
        scheduleEval: false,
      );
    }
  }
}
