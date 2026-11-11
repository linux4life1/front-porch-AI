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
import 'package:front_porch_ai/services/chat/doors/edits/edit_deps.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// What Manual Reprocess can redo for a reply, and as whom: its Needs (a
/// critique pass, needs_reprocess.dart) or its Feelings (the Realism judges
/// asked again, [Reprocessor.reprocessFeelings]).
///
/// Public reads only ([EditsView]): the bubble asks these on golden doubles,
/// and probing library-private state there would throw mid-build.
class ReprocessTargets {
  ReprocessTargets(this._v);

  final EditsView _v;

  /// Speaker + enabled keys for a reprocess of [index], or null when the
  /// entry must stay hidden: not reprocessable, Needs off, every need off,
  /// or a group speaker that cannot be resolved to a roster card.
  ({String speaker, List<String> enabled, CharacterCard? card})?
  reprocessNeedsTargetFor(int index) {
    final messages = _v.messages();
    if (index < 0 || index >= messages.length) return null;
    if (_v.isGenerating()) return null;
    final msg = messages[index];
    if (msg.isUser || msg.sender == 'System') return null;
    final meta = msg.activeMetadata;
    if (meta == null || !meta.containsKey('realism_state')) return null;
    final preState = meta['realism_state'];
    if (preState is! Map || preState['needs'] == null) return null;
    final isGroupTurn = _v.activeGroup() != null;
    CharacterCard? card;
    if (isGroupTurn) {
      card = resolveGroupSpeakerForMessage(
        _v.groupCharacters(),
        msg,
        logOnMiss: false,
      );
      if (card == null) return null;
    } else {
      card = _v.activeCharacter();
    }
    // The reply's speaker's Needs, not whoever is up next.
    final forCard = _v.needsActiveForCard;
    final on = isGroupTurn && forCard != null && card != null
        ? forCard(card)
        : _v.needsActive();
    if (!on) return null;
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
    final messages = _v.messages();
    if (index < 0 || index != messages.length - 1) return null;
    if (_v.isGenerating() || _v.isEvaluatingRealism()) return null;
    final inGroup = _v.activeGroup() != null;
    if (inGroup && _v.observerMode()) return null;
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
      card = _v.activeCharacter();
      if (userMeta?[kRealismPreTurn] is! Map) return null;
    } else {
      card = resolveGroupSpeakerForMessage(
        _v.groupCharacters(),
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
    // The reply's speaker's Realism, not whoever is up next.
    final realismFor = _v.realismEnabledForCard;
    final realismOn = inGroup && realismFor != null
        ? realismFor(card)
        : _v.realismEnabled();
    if (!realismOn) return null;
    for (var i = userAt + 1; i < index; i++) {
      final m = messages[i];
      if (m.isUser || m.sender == 'System') continue;
      final same = inGroup
          ? identical(
              resolveGroupSpeakerForMessage(
                _v.groupCharacters(),
                m,
                logOnMiss: false,
              ),
              card,
            )
          : m.sender == msg.sender;
      if (same) return null;
    }
    // Last, so golden doubles (which lack it) never get here: a turn still
    // settling — a re-score among them — cannot be re-scored.
    if (_v.isSettlingTurn()) return null;
    return card.name;
  }
}
