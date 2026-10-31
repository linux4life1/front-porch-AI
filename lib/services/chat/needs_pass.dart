// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Needs pass: the one place Needs run from, behind one gate.
//
// Disabled means disabled. [NeedsPass._needsActive] is the gate (the Realism
// engine, this chat's Needs switch, the global Needs switch read live), and
// every way Needs run reads it: the pre-turn stamp, the prompt lines and the
// judge (wired to [NeedsPass.active] in chat_service_wiring_*), the clock's
// wear, the chip under the reply, Reprocess Needs. Off, none of them run and
// nothing of Needs is written. What this file does not gate on the gate is
// state: the bars seeded from a card or a session (the chat's stored
// switch). Regen / delete undoing a stamp a reply already carries, which
// came from wear that happened, lives in needs_rewinds.dart.
// test/hygiene/needs_gate_ratchet_test.dart keeps new Needs code here.
//
// The wear: after the clock commits, every present body wears the beat's
// story minutes at fixed rates (needs_wear.dart); the scene eval then
// scores events on top. With the clock off the reply is the beat: the
// speaker's hunger, bladder and energy tick a fixed step (version 1's
// per-turn tick, the maintainer's ruling of 2026-10-08), so the body still
// moves between events. Continue does not invent a second beat.

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/enabled_needs.dart';
import 'package:front_porch_ai/services/chat/group_member_realism.dart';
import 'package:front_porch_ai/services/chat/group_speaker_resolution.dart';
import 'package:front_porch_ai/services/chat/needs_beat_wear.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/needs_wear.dart';
import 'package:front_porch_ai/services/chat/realism_scope.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

class NeedsPass {
  NeedsPass(
    this._scope, {
    required this.loadIntoScalars,
    required this.chatRealism,
  });

  final RealismScope _scope;

  /// The group dance's load of a member into the live scalars.
  final void Function(String charId) loadIntoScalars;

  /// This chat's own Realism switch, not the gate [active] reads.
  final bool Function() chatRealism;

  /// The gate every Needs run reads. [_needsActive] keeps its name: the
  /// ratchet pins the one definition here.
  bool get active => _needsActive;

  bool get _realismEnabled => _scope.realismEnabled();
  bool get _needsSimEnabled => _scope.needsSimEnabled();
  bool get _clockRunning => _scope.clockRunning();
  NeedsSimulation get _needsSimulation => _scope.needs();
  TimeService get _timeService => _scope.time();
  GroupChat? get _activeGroup => _scope.activeGroup();
  CharacterCard? get _activeCharacter => _scope.activeCharacter();
  List<CharacterCard> get _groupCharacters => _scope.groupCharacters();
  List<ChatMessage> get _messages => _scope.messages;
  Map<String, dynamic>? get _pendingRealismMetadata => _scope.pending();
  set _pendingRealismMetadata(Map<String, dynamic>? v) => _scope.setPending(v);
  String _getCharacterIdFromCard(CharacterCard c) => _scope.characterIdFor(c);
  Map<String, int> _getGroupNeeds(String id) => _scope.groups.needsOf(id);
  GroupMemberRealism _memberForWrite(String id) =>
      _scope.groups.memberForWrite(id);
  void _loadGroupRealismIntoScalars(String id) => loadIntoScalars(id);
  late final NeedsBeatWear _wear = NeedsBeatWear(_scope);

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
      _scope.realismSettings().needsSimDefault;

  /// The chat's own Needs switch at the start of a 1:1 chat, from the card's
  /// choice ([FrontPorchExtensions.needsSimChoice]). A card that says nothing
  /// asks for Needs in a chat whose Realism is on: Needs need Realism, so
  /// filling in Needs where it cannot run would only flip a stored switch.
  /// Porch Life is not part of it: it vetoes every chat live through
  /// [active] (maintainer ruling, 2026-10-10), so a chat started while it is
  /// off keeps its card's choice for when it comes back on. A silent card
  /// reads the chat's own Realism switch, not the gate, for the same reason
  /// (Porch Life's Realism vetoes live too), so callers set Realism first.
  bool seedNeedsSim(bool? cardChoice) => cardChoice ?? chatRealism();

  /// The pre-turn stamp: the body as it is before this reply, with the
  /// carried fraction, on the pending map, so regen and the chip rewind to
  /// the turn's base. 1:1 stamps the live vector; a group stamps the
  /// speaker's own bars (or the card's baselines on a first turn) and that
  /// member's carry, and loads the speaker into the scalars. Returns the
  /// vector stamped, or null when nothing was.
  Map<String, int>? stampPreTurn({CharacterCard? groupSpeaker}) {
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

  void wearBodiesAfterClock(GenerationMode mode, ChatMessage target) {
    if (!_needsActive) return;
    if (mode == GenerationMode.continue_) return;
    _pendingRealismMetadata ??= {};
    _pendingRealismMetadata!['needs_time_wear'] = const <String, int>{};
    wearBeatOn(target);
  }

  /// A beat of a day or more ([kLongSkipMinutes]: a skip line, a calendar
  /// jump) lands every body at its everyday level before the reply prompt
  /// is built, so the reply to "two weeks later" reads bodies that lived
  /// those weeks. Runs after the turn's pre-turn stamp, so regen and the
  /// chip still measure from the body before the skip. The minutes are
  /// taken here, so the post-gen wear charges nothing twice; the stamps
  /// ride the turn's pending map onto the reply, where regen, swipe and
  /// delete read them.
  void landLivedBeatBeforeReply() {
    if (!_needsActive || !_clockRunning) return;
    if (!_timeService.bodyBeatLivedOwed) return;
    final minutes = _timeService.takeBodyWearMinutes();
    final beat = _activeGroup == null
        ? _wear.host(minutes, offScreen: true, lived: true)
        : _wear.group(minutes, offScreen: true, lived: true);
    _pendingRealismMetadata ??= {};
    final pending = _pendingRealismMetadata!;
    pending[kLongSkipMinutesMeta] = minutes;
    if (beat.before.isEmpty) return;
    pending.putIfAbsent(kNeedsPreWearByMember, () => beat.before);
    pending.putIfAbsent(kNeedsPreWearCarryByMember, () => beat.carryBefore);
    pending[kNeedsWornByMember] = beat.after;
  }

  /// Wears whatever minutes the clock has not yet charged, taking them so
  /// they cannot be charged twice, and records the result on [target]. A
  /// second call in the same turn (a named-time correction read from the
  /// reply) keeps the first call's "before" and extends its "after" and
  /// the chip's time part. With the clock off the reply itself is the
  /// beat: the speaker ticks [needsTickPerReply], through the same stamps,
  /// so regen, swipe and delete rewind it the same way.
  void wearBeatOn(ChatMessage target) {
    if (!_needsActive) return;
    final BeatWear beat;
    if (_clockRunning) {
      final minutes = _timeService.takeBodyWearMinutes();
      if (minutes <= 0) return;
      final offScreen = _timeService.bodyBeatOffScreen;
      final lived = _timeService.bodyBeatLongSkip;
      final rested = _timeService.bodyBeatSlept;
      beat = _activeGroup == null
          ? _wear.host(
              minutes,
              offScreen: offScreen,
              lived: lived,
              rested: rested,
            )
          : _wear.group(
              minutes,
              offScreen: offScreen,
              lived: lived,
              rested: rested,
            );
    } else {
      beat = _wear.tickSpeaker();
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
  void attachDeltaChipToLastMessage() {
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
    final senderCard = _activeGroup != null
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
