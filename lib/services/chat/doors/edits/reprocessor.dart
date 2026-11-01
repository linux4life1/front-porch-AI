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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart'
    show AppDatabaseMemoryQueries, Objective;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edit_deps.dart';
import 'package:front_porch_ai/services/chat/doors/edits/reprocess_targets.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';

export 'package:front_porch_ai/services/chat/doors/edits/reprocess_targets.dart';

/// The registers the Realism judges write, as `realism_state` names them.
/// A Feelings re-score rewinds exactly these and stamps them back.
const List<String> _kJudgedRegisters = [
  'affectionScore',
  'relationshipTier',
  'longTermScore',
  'longTermTier',
  'turnsSinceLongTermCheck',
  'shortTermDeltasSummary',
  'trustLevel',
  'pendingTrustRepair',
  'activeFixation',
  'fixationLifespan',
  'characterEmotion',
  'emotionIntensity',
  'emotionCause',
  'emotionHeldTurns',
];

/// Reply metadata the judges own. A re-score replaces all of it.
const List<String> _kJudgedMetaKeys = [
  'bond_delta',
  'trust_delta',
  'bond_reason',
  'trust_reason',
  'arousal_delta',
  'arousal_reason',
  'trust_repair_verdict',
  'trust_repair_recovery',
  'trust_repair_reason',
  kFeelingsUnscoredMeta,
];

/// What Manual Reprocess → Feelings did.
enum FeelingsRescore {
  /// The judges answered; the reply carries the new score.
  scored,

  /// Not on offer right now (not the last reply, Realism off, a turn still
  /// running, no record to rewind to). Nothing ran.
  refused,

  /// The judges ran but nothing readable came back, or the pass failed. The
  /// reply keeps what it had.
  unreadable,
}

/// Manual Reprocess: Needs (forwarded to [NeedsReprocess]) and Feelings.
///
/// Feelings asks the Realism judges again about the user line the LAST
/// reply answers, without touching the reply's text or the clock. Same
/// input, same answer, like a regen: the judged registers rewind to the
/// stamp the user line carries (`realism_pre_turn`, per speaker in a group),
/// the turn's mood decay replays, and the judges run through the one shared
/// dispatch a send uses ([RealismJudges.runPreGenJudges] — one-shot or
/// three calls, tools first). What the judges do not own stays as the turn
/// left it: needs, clock, pockets, posture, the decay cadence and the
/// group's hidden feelings, a climax's arousal reset, and the turn's quests.
/// A pass that cannot read an answer, or fails, puts everything back.
class Reprocessor {
  Reprocessor(this._d) : targets = ReprocessTargets(_d.view);

  final EditDeps _d;

  /// Which reprocess choices a reply offers, and as whom.
  final ReprocessTargets targets;

  /// True while Manual Reprocess → Feelings runs the judges again. They may
  /// not start quests then, and tier crossings wait in [rescoreCrossings]
  /// until the new score is kept.
  bool rescoringFeelings = false;
  final List<TierCrossing> rescoreCrossings = [];

  ChatSessionState get _session => _d.session;
  EditServices get _s => _d.services;
  late final RealismScope _scope = _s.graph().scope;
  GroupChat? get _activeGroup => _session.activeGroup;
  RelationshipService get _relationshipService => _scope.relationship();
  NsfwService get _nsfwService => _scope.nsfw();
  GroupRealismStore get _groupStore => _scope.groups;
  Map<String, dynamic>? get _pendingRealismMetadata => _scope.pending();
  set _pendingRealismMetadata(Map<String, dynamic>? v) => _scope.setPending(v);

  String _getCharacterIdFromCard(CharacterCard c) => _d.characterIdFor(c);
  void notifyListeners() => _d.notify();

  /// Re-evaluate a message's needs deltas under a user critique; see
  /// [NeedsReprocess.manualReprocessNeeds] for [onlyNeeds] scoping.
  Future<bool> manualReprocessNeeds(
    int index,
    String critique, {
    Set<String> onlyNeeds = const <String>{},
  }) => _s.graph().needsReprocess.manualReprocessNeeds(
    index,
    critique,
    onlyNeeds: onlyNeeds,
  );

  /// Revert a prior manual reprocess on the given message.
  Future<bool> revertNeedsReprocess(int index) =>
      _s.graph().needsReprocess.revertNeedsReprocess(index);

  Future<FeelingsRescore> reprocessFeelings(int index) async {
    const refused = FeelingsRescore.refused;
    if (_d.turn.isTurnBusy() || !_s.graph().realismActiveThisMode) {
      return refused;
    }
    if (targets.reprocessFeelingsTargetFor(index) == null) return refused;
    final msg = _session.messages[index];
    final userMsg = _session
        .messages[_session.messages.lastIndexWhere((m) => m.isUser, index - 1)];
    final inGroup = _activeGroup != null;
    final speaker = inGroup
        ? resolveGroupSpeakerForMessage(_session.groupCharacters, msg)
        : _session.activeCharacter;
    if (speaker == null) return refused;
    final sid = inGroup ? _getCharacterIdFromCard(speaker) : '';
    final userMeta = userMsg.metadata ?? const <String, dynamic>{};
    final bySpeaker = userMeta[kRealismPreTurnBySpeaker];
    final rawStamp = !inGroup
        ? userMeta[kRealismPreTurn]
        : (bySpeaker is Map ? bySpeaker[sid] : null);
    if (rawStamp is! Map) return refused;

    final objectives = _s.objectives();
    final preActive = _session.activeCharacter;
    final prePin = _groupStore.turnSpeakerId;
    final preObjectives = objectives.activeObjectives;
    // Both held for the whole pass: settling keeps every mutation out, and
    // "evaluating" is what the bubble can read to hide the pill meanwhile.
    _d.turn.setPostGenerating(true);
    _s.graph().evalStatus.evaluating = true;
    _d.turn.clearPostGenAbortFlags();
    notifyListeners();
    var result = FeelingsRescore.unreadable;
    try {
      final ok = await _d.services.lanes.withWorkerLane(
        () => _rescoreFeelingsHeld(
          msg,
          index: index,
          speaker: speaker,
          sid: sid,
          stamp: Map<String, dynamic>.from(rawStamp),
        ),
      );
      if (ok) result = FeelingsRescore.scored;
    } catch (e, st) {
      // _rescoreFeelingsHeld already put the registers back.
      debugPrint('[Realism:Rescore] failed, reply kept as it was: $e\n$st');
    } finally {
      rescoringFeelings = false;
      rescoreCrossings.clear();
      _pendingRealismMetadata = null;
      _session.activeCharacter = preActive;
      _groupStore.turnSpeakerId = prePin;
      objectives.activeObjectives = preObjectives;
      _s.graph().evalStatus.stopChunkTimer();
      _s.graph().evalStatus.evaluating = false;
      _d.turn.setPostGenerating(false);
      _d.turn.clearPostGenAbortFlags();
    }
    await _d.saveChat();
    notifyListeners();
    return result;
  }

  Future<bool> _rescoreFeelingsHeld(
    ChatMessage msg, {
    required int index,
    required CharacterCard speaker,
    required String sid,
    required Map<String, dynamic> stamp,
  }) async {
    final inGroup = sid.isNotEmpty;
    final groupSid = inGroup ? sid : null;
    _session.activeCharacter = speaker;
    if (inGroup) {
      _groupStore.turnSpeakerId = sid;
      _s.graph().dance.loadIntoScalars(sid);
    }
    _s.objectives().activeObjectives = await _objectivesBeforeTurn(
      speaker,
      msg.activeMetadata?['objective_turn_ops'],
    );
    final now = _s.graph().snapshot.capture();
    final nowCadence = _relationshipService.captureCadenceAndFeelings();
    final nowTiers = {
      'bond': _relationshipService.relationshipTier,
      'long_term': _relationshipService.longTermTier,
      'trust': _relationshipService.trustTier,
    };

    try {
      return await _rescoreFromSnapshot(
        msg,
        index: index,
        speaker: speaker,
        stamp: stamp,
        now: now,
        nowCadence: nowCadence,
        nowTiers: nowTiers,
        groupSid: groupSid,
      );
    } catch (_) {
      // Whatever threw, the snapshot goes back before anything is saved.
      _putJudgedRegisters(now, now['arousalLevel'], groupSid);
      rethrow;
    }
  }

  /// Everything after the snapshot: rewind, judges, keep or put back. The
  /// reply's metadata is written last, so a throw before it leaves the reply
  /// untouched.
  Future<bool> _rescoreFromSnapshot(
    ChatMessage msg, {
    required int index,
    required CharacterCard speaker,
    required Map<String, dynamic> stamp,
    required Map<String, dynamic> now,
    required Map<String, dynamic> nowCadence,
    required Map<String, int> nowTiers,
    required String? groupSid,
  }) async {
    // Rewind to where the judges stood when the line was first scored.
    _putJudgedRegisters(
      {
        for (final k in [..._kJudgedRegisters, 'turnsSinceDecayCheck'])
          if (stamp.containsKey(k)) k: stamp[k],
      },
      stamp['arousalLevel'],
      groupSid,
    );
    _s.graph().restores.applyMoodDecay();
    if (groupSid != null) _s.graph().dance.loadIntoScalars(groupSid);
    // Posture is written after the reply; the one-shot judge read the
    // position the turn began in.
    final stanceBefore =
        msg.activeMetadata?[kSpatialStancePreTurn] ?? stamp['spatialStance'];
    if (stanceBefore is String) {
      _relationshipService.setSpatialStance(stanceBefore);
    }

    _pendingRealismMetadata = <String, dynamic>{};
    rescoringFeelings = true;
    _s.graph().evalStatus.evaluating = true;
    _s.graph().evalStatus.streamText = '';
    notifyListeners();
    final idle = _d.services.lanes.mouthIdle();
    if (idle != null) await idle;
    await _s.graph().judges.runPreGenJudges(
      onChunk: _s.graph().evalStatus.onChunk,
      logSpeakerName: speaker.name,
    );
    rescoringFeelings = false;

    final pending = _pendingRealismMetadata ?? const <String, dynamic>{};
    final scored =
        !_d.services.graph().evalStatus.cancelled &&
        pending[kFeelingsUnscoredMeta] != true &&
        (pending.containsKey('bond_delta') ||
            pending.containsKey('trust_delta') ||
            pending.containsKey('trust_repair_verdict'));
    if (!scored) {
      debugPrint(
        '[Realism:Rescore] ${speaker.name}: no readable answer — the reply '
        'keeps what it had',
      );
      _putJudgedRegisters(now, now['arousalLevel'], groupSid);
      return false;
    }

    final meta = Map<String, dynamic>.from(msg.activeMetadata!);
    final nowArousal = (now['arousalLevel'] as num?)?.toInt() ?? 0;
    final oldArousal = (meta['arousal_delta'] as num?)?.toInt() ?? 0;
    final newArousal = (pending['arousal_delta'] as num?)?.toInt() ?? 0;
    // A climax already reset arousal after this reply; that reset stands.
    final arousal = meta['climax_triggered'] == true
        ? nowArousal
        : nowArousal - oldArousal + newArousal;
    // Cadence, the hidden group feelings and posture are the turn's.
    _putJudgedRegisters(
      {...nowCadence, 'spatialStance': now['spatialStance']},
      arousal,
      groupSid,
    );

    meta.removeWhere((k, _) => _kJudgedMetaKeys.contains(k));
    for (final k in _kJudgedMetaKeys) {
      if (pending.containsKey(k)) meta[k] = pending[k];
    }
    meta['emotion_label'] = _scope.emotion();
    _s.graph().mood.stampCause(meta);
    final verdict = pending[RealismVerification.kMetaKey];
    if (verdict is Map) {
      meta[RealismVerification.kMetaKey] = {
        ...?(meta[RealismVerification.kMetaKey] as Map?),
        ...verdict,
      };
    }
    final live = _s.graph().snapshot.capture();
    meta['realism_state'] = {
      ...Map<String, dynamic>.from(meta['realism_state'] as Map),
      for (final k in [..._kJudgedRegisters, 'arousalLevel'])
        if (live.containsKey(k)) k: live[k],
    };
    // Our Story cards only for a tier the old score had not already reached,
    // cited at the reply (a length one past its index).
    for (final c in rescoreCrossings) {
      if (c.newTier != nowTiers[c.axis]) {
        _s.graph().plantTierCrossing(c, citeLength: index + 1);
      }
    }
    // In place: the reply's metadata and its swipe slot share one map.
    msg.activeMetadata!
      ..clear()
      ..addAll(meta);
    debugPrint(
      '[Realism:Rescore] ${speaker.name}: bond ${meta['bond_delta']} '
      'trust ${meta['trust_delta']} mood ${_scope.emotion()}',
    );
    return true;
  }

  /// The speaker's quests as the judges saw them before this reply's turn:
  /// the turn's own new quest hidden, any it demoted or set aside put back.
  /// The judge prompt names the main quest, so this is part of "same input".
  Future<List<Objective>> _objectivesBeforeTurn(
    CharacterCard speaker,
    Object? turnOps,
  ) async {
    final created = <String>{};
    final demoted = <String>{};
    final setAside = <String>{};
    if (turnOps is List) {
      for (final op in turnOps.whereType<Map>()) {
        final id = op['id'];
        if (id is! String) continue;
        switch (op['op']) {
          case 'created':
            created.add(id);
          case 'demoted':
            demoted.add(id);
          case 'deactivated' || 'evicted':
            setAside.add(id);
        }
      }
    }
    final session = _session.currentSessionId;
    if (session == null) return const [];
    final List<Objective> all;
    try {
      all = setAside.isEmpty
          ? await _s.objectives().getActiveObjectivesFor(speaker)
          : await _s.db().getObjectivesForCharacter(
              _getCharacterIdFromCard(speaker),
              chatId: session,
            );
    } catch (e) {
      debugPrint('[Realism:Rescore] Could not read quests: $e');
      return _s.objectives().activeObjectives;
    }
    return [
      for (final o in all)
        if ((o.active || setAside.contains(o.id)) && !created.contains(o.id))
          demoted.contains(o.id) ? o.copyWith(isPrimary: true) : o,
    ];
  }

  /// Writes [state]'s judged registers into the live scalars (and, in a
  /// group, the speaker's own entry). Keys [state] lacks keep their value.
  void _putJudgedRegisters(
    Map<String, dynamic> state,
    Object? arousal,
    String? groupSid,
  ) {
    _relationshipService.restoreFromMessageState(
      state,
      groupSpeakerId: groupSid,
    );
    _s.graph().mood.restoreFromStamp(state);
    // Lust is scored only while Afterglow runs; a re-score leaves it alone.
    if (arousal is num && _nsfwService.nsfwCooldownEnabled) {
      _nsfwService.setArousalLevel(arousal.toInt());
    }
    if (groupSid == null) return;
    _s.graph().dance.saveScalarsIntoGroup(groupSid);
    // The save skips an empty mood; a first-turn member had none.
    _s.graph().mood.saveToMember(groupSid, evenIfEmpty: true);
  }
}
