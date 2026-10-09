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

part of '../chat_service.dart';

/// What Manual Reprocess can redo for a reply: its Needs (a critique pass,
/// chat_service_needs_reprocess.dart) or its Feelings (the Realism judges
/// asked again, [ChatServiceFeelingsRescore] below).
///
/// Who a Reprocess Needs pass would run as, and which needs are on.
///
/// Public getters only — FakeChatService implements those, and probing
/// library-private fields from an extension would throw mid-build on a
/// golden double (same contract as [_lastRagReceiptImpl]).
extension ChatServiceNeedsReprocessTarget on ChatService {
  /// Speaker + enabled keys for a reprocess of [index], or null when the
  /// entry must stay hidden: not reprocessable, Needs off, every need off,
  /// or a group speaker that cannot be resolved to a roster card.
  ({String speaker, List<String> enabled, CharacterCard? card})?
  reprocessNeedsTargetFor(int index) {
    if (index < 0 || index >= messages.length) return null;
    if (isGenerating) return null;
    final msg = messages[index];
    if (msg.isUser || msg.sender == 'System') return null;
    final meta = msg.activeMetadata;
    if (meta == null || !meta.containsKey('realism_state')) return null;
    final preState = meta['realism_state'];
    if (preState is! Map || preState['needs'] == null) return null;
    if (!needsActive) return null;

    final isGroupNonObs = activeGroup != null && !observerMode;
    CharacterCard? card;
    if (isGroupNonObs) {
      card = resolveGroupSpeakerForMessage(
        groupCharacters,
        msg,
        logOnMiss: false,
      );
      if (card == null) return null;
    } else {
      card = activeCharacter;
    }
    final enabled = enabledNeedKeys(card);
    if (enabled.isEmpty) return null;
    return (
      speaker: card?.name ?? 'the character',
      enabled: enabled,
      card: card,
    );
  }

  /// Speaker name for a Feelings re-score of [index], or null when that
  /// choice must stay hidden: not the last reply, Realism off for this chat,
  /// a reply the judges never stamped, a line with no record of where
  /// feelings stood before it (nothing honest to rewind to), or a speaker
  /// who already answered that line once before this reply.
  String? reprocessFeelingsTargetFor(int index) {
    if (index < 0 || index != messages.length - 1) return null;
    if (isGenerating || !realismEnabled) return null;
    final inGroup = activeGroup != null;
    if (inGroup && observerMode) return null;
    final msg = messages[index];
    if (msg.isUser || msg.sender == 'System') return null;
    final meta = msg.activeMetadata;
    if (meta == null || meta['realism_state'] is! Map) return null;
    if (meta['is_dream'] == true || meta['is_chance_time_narration'] == true) {
      return null;
    }
    final userAt = messages.lastIndexWhere((m) => m.isUser, index - 1);
    if (userAt < 0) return null;
    final userMeta = messages[userAt].metadata;
    CharacterCard? card;
    if (!inGroup) {
      card = activeCharacter;
      if (userMeta?[kRealismPreTurn] is! Map) return null;
    } else {
      card = resolveGroupSpeakerForMessage(
        groupCharacters,
        msg,
        logOnMiss: false,
      );
      if (card == null) return null;
      final bySpeaker = userMeta?[kRealismPreTurnBySpeaker];
      if (bySpeaker is! Map || bySpeaker[groupMemberStoreId(card)] is! Map) {
        return null;
      }
    }
    if (card == null) return null;
    for (var i = userAt + 1; i < index; i++) {
      final m = messages[i];
      if (m.isUser || m.sender == 'System') continue;
      final same = inGroup
          ? identical(
              resolveGroupSpeakerForMessage(
                groupCharacters,
                m,
                logOnMiss: false,
              ),
              card,
            )
          : m.sender == msg.sender;
      if (same) return null;
    }
    return card.name;
  }
}

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
];

/// Reply metadata the judges own. A re-score replaces all of it.
const List<String> _kJudgedMetaKeys = [
  'bond_delta',
  'trust_delta',
  'bond_reason',
  'trust_reason',
  'arousal_delta',
  'trust_repair_verdict',
  'trust_repair_recovery',
  'trust_repair_reason',
  kFeelingsUnscoredMeta,
];

/// Manual Reprocess → Feelings: ask the Realism judges again about the user
/// line the LAST reply answers, without touching the reply's text or the
/// clock.
///
/// Same input, same answer, like a regen: the judged registers rewind to
/// the stamp the user line carries (`realism_pre_turn`, per speaker in a
/// group), the turn's mood decay replays, and the judges run through the
/// one shared dispatch a send uses ([_runPreGenRealismJudges] — one-shot or
/// three calls, tools first). What the judges do not own stays as the turn
/// left it: needs, clock, pockets, posture, the decay cadence and the
/// group's hidden feelings, a climax's arousal reset, and the turn's quests.
/// A pass that cannot read an answer puts everything back and returns false.
extension ChatServiceFeelingsRescore on ChatService {
  Future<bool> reprocessFeelings(int index) async {
    if (_isTurnBusy || !_realismActiveThisMode) return false;
    if (reprocessFeelingsTargetFor(index) == null) return false;
    final msg = _messages[index];
    final userMsg =
        _messages[_messages.lastIndexWhere((m) => m.isUser, index - 1)];
    final inGroup = _activeGroup != null;
    final speaker = inGroup
        ? _resolveGroupSpeakerForMessage(msg)
        : _activeCharacter;
    if (speaker == null) return false;
    final sid = inGroup ? _getCharacterIdFromCard(speaker) : '';
    final userMeta = userMsg.metadata ?? const <String, dynamic>{};
    final bySpeaker = userMeta[kRealismPreTurnBySpeaker];
    final rawStamp = !inGroup
        ? userMeta[kRealismPreTurn]
        : (bySpeaker is Map ? bySpeaker[sid] : null);
    if (rawStamp is! Map) return false;

    final preActive = _activeCharacter;
    final prePin = _turnSpeakerIdForRealism;
    final preObjectives = _activeObjectives;
    _isPostGenerating = true;
    _clearPostGenAbortFlags();
    notifyListeners();
    var ok = false;
    try {
      ok = await _withWorkerLane(
        () => _rescoreFeelingsHeld(
          msg,
          index: index,
          speaker: speaker,
          sid: sid,
          stamp: Map<String, dynamic>.from(rawStamp),
        ),
      );
    } finally {
      _rescoringFeelings = false;
      _rescoreCrossings.clear();
      _pendingRealismMetadata = null;
      _activeCharacter = preActive;
      _turnSpeakerIdForRealism = prePin;
      _activeObjectives = preObjectives;
      _evalChunkTimer?.cancel();
      _evalChunkTimer = null;
      _isEvaluatingRealism = false;
      _isPostGenerating = false;
      _clearPostGenAbortFlags();
    }
    await _saveChat();
    notifyListeners();
    return ok;
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
    _activeCharacter = speaker;
    if (inGroup) {
      _turnSpeakerIdForRealism = sid;
      _loadGroupRealismIntoScalars(sid);
    }
    _activeObjectives = await _objectivesBeforeTurn(
      speaker,
      msg.activeMetadata?['objective_turn_ops'],
    );
    final now = _captureRealismState();
    final nowCadence = _relationshipService.captureCadenceAndFeelings();
    final nowTiers = {
      'bond': _relationshipService.relationshipTier,
      'long_term': _relationshipService.longTermTier,
      'trust': _relationshipService.trustTier,
    };

    // Rewind to where the judges stood when the line was first scored.
    _putJudgedRegisters(
      {
        for (final k in [..._kJudgedRegisters, 'turnsSinceDecayCheck'])
          if (stamp.containsKey(k)) k: stamp[k],
      },
      stamp['arousalLevel'],
      groupSid,
    );
    _applyMoodDecay();
    if (inGroup) _loadGroupRealismIntoScalars(sid);
    // Posture is written after the reply; the one-shot judge read the
    // position the turn began in.
    final stanceBefore =
        msg.activeMetadata?[kSpatialStancePreTurn] ?? stamp['spatialStance'];
    if (stanceBefore is String) {
      _relationshipService.setSpatialStance(stanceBefore);
    }

    _pendingRealismMetadata = <String, dynamic>{};
    _rescoringFeelings = true;
    _isEvaluatingRealism = true;
    _realismEvalStreamText = '';
    notifyListeners();
    final kobold = _llmProvider?.koboldService;
    if (kobold != null) await kobold.waitForIdle();
    await _runPreGenRealismJudges(
      onChunk: (chunk) {
        _realismEvalStreamText += chunk;
        _evalChunkTimer?.cancel();
        _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
          try {
            notifyListeners();
          } catch (_) {}
        });
      },
      logSpeakerName: speaker.name,
    );
    _rescoringFeelings = false;

    final pending = _pendingRealismMetadata ?? const <String, dynamic>{};
    final scored =
        !_realismEvalCancelled &&
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
    meta['emotion_label'] = _characterEmotion;
    final verdict = pending[RealismVerification.kMetaKey];
    if (verdict is Map) {
      meta[RealismVerification.kMetaKey] = {
        ...?(meta[RealismVerification.kMetaKey] as Map?),
        ...verdict,
      };
    }
    final live = _captureRealismState();
    meta['realism_state'] = {
      ...Map<String, dynamic>.from(meta['realism_state'] as Map),
      for (final k in [..._kJudgedRegisters, 'arousalLevel'])
        if (live.containsKey(k)) k: live[k],
    };
    // In place: the reply's metadata and its swipe slot share one map.
    msg.activeMetadata!
      ..clear()
      ..addAll(meta);

    // Our Story cards only for a tier the old score had not already reached.
    for (final c in _rescoreCrossings) {
      if (c.newTier != nowTiers[c.axis]) {
        _plantTierCrossing(c, citeLength: index);
      }
    }
    debugPrint(
      '[Realism:Rescore] ${speaker.name}: bond ${meta['bond_delta']} '
      'trust ${meta['trust_delta']} mood $_characterEmotion',
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
    final session = _currentSessionId;
    if (session == null) return const [];
    final List<Objective> all;
    try {
      all = setAside.isEmpty
          ? await getActiveObjectivesFor(speaker)
          : await _db.getObjectivesForCharacter(
              _getCharacterIdFromCard(speaker),
              chatId: session,
            );
    } catch (e) {
      debugPrint('[Realism:Rescore] Could not read quests: $e');
      return _activeObjectives;
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
    final emotion = state['characterEmotion'];
    if (emotion is String) _characterEmotion = emotion;
    final intensity = state['emotionIntensity'];
    if (intensity is String) _emotionIntensity = intensity;
    if (arousal is num) _nsfwService.setArousalLevel(arousal.toInt());
    if (groupSid == null) return;
    _saveScalarsIntoGroupRealism(groupSid);
    // The save skips an empty mood; a first-turn member had none.
    _memberForWrite(groupSid)
      ..emotion = _characterEmotion
      ..emotionIntensity = _emotionIntensity;
  }
}
