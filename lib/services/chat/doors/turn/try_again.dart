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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';

import 'send_spine.dart';

/// Try again (Generate reply) on a trailing user line: the reply was
/// deleted, cancelled or failed, or a fork stopped at the user line. The
/// turn's score rode the lost reply, so the line is rewound to its own
/// stamp and scored again the way a send scores it. Same input, same
/// deltas — never stacked (#339). Also the stamp-less 1:1 rewind a line
/// sent before stamps existed falls back to.
class TryAgain {
  TryAgain(this._s);

  final SendSpine _s;

  ChatSessionState get _session => _s.session;
  RealismGraph get realism => _s.graph;
  TurnEngine get turnEngine => _s.engine;
  MediaDoor get mediaDoor => _s.media;
  ObjectivesDoor get objectivesDoor => _s.objectives;
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  UserTurnHold get _userTurn => _s.controls.userTurn;
  set _stoppedReplyAnchor(ChatMessage? v) =>
      _s.cast.guests.stoppedReplyAnchor = v;
  bool get _realismEvalCancelled => realism.evalStatus.cancelled;
  set _realismEvalCancelled(bool v) => realism.evalStatus.cancelled = v;
  Map<String, dynamic>? get _pendingRealismMetadata =>
      realism.registers.pending;
  set _pendingRealismMetadata(Map<String, dynamic>? v) =>
      realism.registers.pending = v;
  NeedsSimulation get _needsSimulation => realism.needs;
  RealismDance get _realismDance => realism.dance;
  MoodRegisters get _mood => realism.mood;
  RelationshipService get _relationshipService => realism.relationship;
  String _getCharacterIdFromCard(CharacterCard card) => _s.characterIdFor(card);
  Future<void> _saveChat() => _s.saveChat();
  void notifyListeners() => _s.notify();
  Future<void> _runAwayPulse({
    required String userText,
    required bool fromUserSend,
  }) =>
      _s.cast.away.runAwayPulse(userText: userText, fromUserSend: fromUserSend);
  void _restoreRealismStateFromMessage(
    ChatMessage? msg, {
    String? groupSpeakerId,
  }) => realism.restores.fromMessage(msg, groupSpeakerId: groupSpeakerId);

  /// Generate reply on a trailing user message (reply deleted, cancelled,
  /// failed, or a fork at the user line). The turn's score rode the lost
  /// reply, so rewind to the user message's stamp and score it again, the
  /// same way a send does. Same input, same deltas — never stacked (#339).
  Future<void> answerTrailingUserLine({
    String? webQuery,
    String? wikiQuery,
    CharacterCard? forceSpeaker,
  }) async {
    _stoppedReplyAnchor = null;
    turnEngine.progress.answeringUnansweredLine = true;
    _userTurn.open();
    try {
      await _answerTrailingUserTurn(webQuery, wikiQuery, forceSpeaker);
    } finally {
      turnEngine.progress.answeringUnansweredLine = false;
      _userTurn.close();
    }
  }

  Future<void> _answerTrailingUserTurn(
    String? webQuery,
    String? wikiQuery,
    CharacterCard? forceSpeaker,
  ) async {
    final userMsg = _session.messages.last;
    final baseAt = _session.messages.length;
    _rewindToUserTurnBaseline(userMsg);
    // Group scores inside _generateResponse's dance for the picked speaker.
    // A group line from before stamps has nothing to rewind to, so it keeps
    // the old no-dance retry rather than stacking on a still-scored member.
    final groupLegacy =
        _activeGroup != null &&
        userMsg.metadata?[kRealismPreTurnBySpeaker] is! Map;
    var cancelled = false;
    if (_activeGroup == null) {
      await _s.handoff.scoreUserTurnBeforeReply(userMsg: userMsg);
      cancelled = _realismEvalCancelled;
      if (cancelled) {
        // Quests the cancelled score proposed have no reply to ride on.
        await objectivesDoor.revertTurn(
          ChatMessage(
            text: '',
            sender: '',
            isUser: false,
            metadata: _pendingRealismMetadata,
          ),
        );
        _needsSimulation.consumePendingCatastrophe();
        _pendingRealismMetadata = null;
        _realismEvalCancelled = false;
      }
    } else {
      // Send pulses before generating (and honours @Name of an Away
      // member); directUserSend below then skips the in-turn pulse.
      await _runAwayPulse(
        userText: AtMentionText.routingText(userMsg),
        fromUserSend: true,
      );
    }
    if (!cancelled) {
      mediaDoor.armForcedLookup(webQuery: webQuery, wikiQuery: wikiQuery);
      await turnEngine.generate(
        GenerationMode.normal,
        directUserSend: true,
        forceSpeaker: forceSpeaker,
        skipSpeakerEval: groupLegacy,
      );
    }
    // Cancelled or failed with no reply: leave the line unscored, as it was
    // before the tap, 1:1 and group alike. A kept partial reply is answered.
    final answered = _session.messages
        .skip(baseAt)
        .any((m) => !m.isUser && m.sender != 'System' && m.text.isNotEmpty);
    if (!answered) {
      _rewindToUserTurnBaseline(userMsg);
      await _saveChat();
      notifyListeners();
    }
  }

  void _rewindToUserTurnBaseline(ChatMessage userMsg) {
    final meta = userMsg.metadata;
    if (_activeGroup == null) {
      final stamp = meta?[kRealismPreTurn];
      if (stamp is Map) {
        _restoreRealismStateFromMessage(_realismStampCarrier(stamp));
      } else {
        rewindToLastAcceptedReply();
      }
      return;
    }
    final bySpeaker = meta?[kRealismPreTurnBySpeaker];
    if (bySpeaker is! Map) return;
    for (final entry in bySpeaker.entries) {
      final sid = entry.key;
      final stamp = entry.value;
      if (sid is! String || stamp is! Map) continue;
      if (!_groupCharacters.any((c) => _getCharacterIdFromCard(c) == sid)) {
        continue;
      }
      _realismDance.loadIntoScalars(sid);
      _restoreRealismStateFromMessage(
        _realismStampCarrier(stamp),
        groupSpeakerId: sid,
      );
      _realismDance.saveScalarsIntoGroup(sid);
      // The save skips an empty mood; a first-turn member had none.
      _mood.writeMemberFromStamp(sid, stamp);
    }
  }

  /// Stamp-less 1:1 user line (sent before stamps existed): rewind only the
  /// scored registers to the last accepted reply. Needs and pockets were
  /// already refunded by the delete that left this line trailing.
  bool rewindToLastAcceptedReply() {
    for (var i = _session.messages.length - 2; i >= 0; i--) {
      final m = _session.messages[i];
      if (m.isUser || m.sender == 'System') continue;
      final state = m.activeMetadata?['realism_state'];
      if (state is! Map) continue;
      restoreScoredRegisters(Map<String, dynamic>.from(state));
      return true;
    }
    return false;
  }

  /// Bond/trust/feelings, mood and arousal from one realism stamp.
  void restoreScoredRegisters(Map<String, dynamic> s) {
    _relationshipService.restoreFromMessageState(s);
    _mood.restoreFromStamp(s);
    realism.nsfw.restoreNsfwFromRealismState(s);
  }

  ChatMessage _realismStampCarrier(Map stamp) => ChatMessage(
    text: '',
    sender: '',
    isUser: false,
    metadata: {'realism_state': Map<String, dynamic>.from(stamp)},
  );
}
