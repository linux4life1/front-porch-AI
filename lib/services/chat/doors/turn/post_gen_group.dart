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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';

/// A group turn's post-gen pieces: the cast's hidden feelings for each
/// other ([scoreCastFeelings]), the active-character loan a pass ends
/// ([endSpeakerLoan]), and a soft member's withUser glance
/// ([runLiteGroupGlancePass]; group_lite_soft_engine_test reads it here).
class PostGenGroup {
  PostGenGroup(this._e);

  final TurnEngine _e;

  TurnDeps get _d => _e.deps;
  ChatSessionState get _session => _d.session;
  TurnProgress get _p => _e.progress;
  RealismGraph get _g => _d.doors.graph();
  EntryDoor get _entry => _d.doors.entry();
  ControlsDoor get _controls => _d.doors.controls();
  CastDoor get _cast => _d.doors.cast();
  LlmLanes get _lanes => _d.services.lanes;
  String _getCharacterIdFromCard(CharacterCard card) =>
      _session.characterIdFor(card);

  GroupChat? get _activeGroup => _session.activeGroup;
  AwayPulseState get _awayPulse => _cast.away.state;
  CastFeelingsJudge get _castFeelingsJudge => _g.castFeelingsJudge;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  Map<String, GroupMemberRealism> get _groupRealism => _g.groups.members;
  GroupRealismStore get _groupStore => _g.groups;
  bool get _realismEnabled => _controls.realismEnabled;
  RealismJudges get _realismJudges => _g.judges;
  RelationshipService get _relationshipService => _g.relationship;
  bool get _shouldTrackInterCharacterRelationships =>
      _entry.reads.shouldTrackInterCharacterRelationships;
  bool _speakerIsSoft(CharacterCard speaker) =>
      _cast.roster.speakerIsSoft(speaker);

  /// Glance only for a group soft member. Skips Needs / bond / posture /
  /// reply-facts / periodic Realism. Writes `_groupRealism[id].withUser`
  /// so [derivePresence] can show Away. 1:1 Scene Guests do not enter.
  Future<void> runLiteGroupGlancePass(GenTurn t, String scoredReply) async {
    if (_activeGroup == null) return;
    if (t.guestSpeaker != null) return;
    if (!_speakerIsSoft(t.speakingCharacter)) return;
    if (scoredReply.trim().isEmpty) return;
    if (!_realismEnabled) return;
    if (_p.postGenAbortRequested) return;

    CharacterCard? lentTo;
    final sid = _getCharacterIdFromCard(t.speakingCharacter);
    try {
      await _lanes.openWorkerLane();
      // A chat opened while the lane opened owns the pointer now.
      if (!_groupCharacters.any((c) => _getCharacterIdFromCard(c) == sid)) {
        return;
      }
      _session.activeCharacter = t.speakingCharacter;
      lentTo = t.speakingCharacter;
      if (sid.isNotEmpty) {
        _relationshipService.setWithUser(_groupRealism[sid]?.withUser);
        final meta = t.streamTarget.activeMetadata ?? <String, dynamic>{};
        meta.putIfAbsent(kWithUserPreTurn, () => _relationshipService.withUser);
        t.streamTarget.activeMetadata = meta;
      }
      await _realismJudges.runWithUserPass(scoredReply);
      debugPrint(
        '[Presence] lite-glance ${t.speakingCharacter.name}='
        '${_relationshipService.withUser}',
      );
      if (sid.isNotEmpty) {
        _groupStore.memberForWrite(sid).withUser =
            _relationshipService.withUser;
      }
      if (t.mode == GenerationMode.normal && !_awayPulse.consumingReturnSpeak) {
        _awayPulse.presentSpeakerTurns++;
      }
    } finally {
      if (lentTo != null) endSpeakerLoan(lentTo);
      await _lanes.closeWorkerLane();
    }
  }

  /// Ends a group pass's loan of the active character to [speaker]. A group
  /// has none between turns, so the loan ends at null, and only while the
  /// pointer still names [speaker]: a chat opened during the pass, or the
  /// next turn's own pass, owns it otherwise. Ending the loan only when the
  /// pointer had held someone left whoever answered first active for the
  /// rest of the visit: Chance Time named them on every turn and your
  /// bubbles took their colours.
  void endSpeakerLoan(CharacterCard speaker) {
    if (stillLentTo(_session.activeCharacter, speaker)) {
      _session.activeCharacter = null;
    }
  }

  /// How [reply] moved the speaker's hidden feelings toward the others. The
  /// char→char judge scores it while the Realism Engine is on (that is when
  /// the feelings reach a prompt); the old keyword scan is the floor when
  /// the engine is off, the turn was aborted, or the judge failed.
  Future<void> scoreCastFeelings(CharacterCard speaker, String reply) async {
    final speakerId = _getCharacterIdFromCard(speaker);
    if (speakerId.isEmpty || !_shouldTrackInterCharacterRelationships) return;
    final others = [
      for (final c in _groupCharacters)
        if (_getCharacterIdFromCard(c) != speakerId) c,
    ];
    final judged = _realismEnabled && !_p.postGenAbortRequested
        ? await _castFeelingsJudge.judge(
            speakerName: speaker.name,
            otherNames: [for (final c in others) c.name],
            reply: clampEvalMessage(reply),
            recentExchange: recentExchange(_session.messages),
          )
        : null;
    if (judged == null) {
      _relationshipService.updateInterCharacterFeelingsFromRecentExchange(
        speakerId,
      );
      return;
    }
    _relationshipService.applyInterCharacterDeltas(speakerId, {
      for (final c in others) _getCharacterIdFromCard(c): ?judged[c.name],
    });
  }
}
