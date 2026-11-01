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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';

/// The relationship service's wiring: bond, trust, fixation, stance and the
/// cast's feelings for each other, each read from the loaded speaker's group
/// slot in a group, plus the "Our Story" card a tier crossing plants.
extension RealismRelationshipWiring on RealismGraph {
  RelationshipService buildRelationship() {
    final h = deps.hooks;
    final entry = deps.doors.entry;
    Map<String, GroupMemberRealism> slots() => groups.members;
    return RelationshipService(
      onNotify: deps.notify,
      onSaveChat: () => deps.doors.sessions().save(),
      getIsGroupActive: () => session.activeGroup != null,
      getObserverMode: () => entry().director.observerMode,
      getGroupCharacterCount: () =>
          fullGroupCharacters(session.groupCharacters).length,
      getShouldTrackInterCharacterRelationships: () =>
          entry().reads.shouldTrackInterCharacterRelationships,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getCurrentGroupMemberIds: () => fullGroupCharacters(
        session.groupCharacters,
      ).map(h.characterIdFor).toSet(),
      getOtherGroupMemberIds: (selfId) => fullGroupCharacters(
        session.groupCharacters,
      ).map(h.characterIdFor).where((id) => id != selfId).toList(),
      getOtherGroupMemberIdToLowerName: (selfId) {
        final m = <String, String>{};
        for (final other in fullGroupCharacters(session.groupCharacters)) {
          final oid = h.characterIdFor(other);
          if (oid == selfId) continue;
          m[oid] = other.name.toLowerCase();
        }
        return m;
      },
      getRecentExchangeLowerText: () {
        if (session.messages.length < 2) return '';
        return session.messages.reversed
            .take(2)
            .map((m) => m.displayText.toLowerCase())
            .join(' ');
      },
      getMessageCount: () => session.messages.length,
      getIsGroupRealismActive: () => entry().reads.isGroupRealismActive,
      getGroupAffectionScore: (charId, {int defaultValue = 0}) =>
          slots()[charId]?.affection ?? defaultValue,
      setGroupAffectionScore: (charId, v) =>
          groups.memberForWrite(charId).affection = v,
      getGroupLongTermScore: (charId, {int defaultValue = 0}) =>
          slots()[charId]?.longTermScore ?? defaultValue,
      setGroupLongTermScore: (charId, v) =>
          groups.memberForWrite(charId).longTermScore = v,
      getGroupTrustLevel: (charId, {int defaultValue = 0}) =>
          slots()[charId]?.trust ?? defaultValue,
      setGroupTrustLevel: (charId, v) =>
          groups.memberForWrite(charId).trust = v,
      getGroupFixation: (charId, {String defaultValue = ''}) =>
          slots()[charId]?.fixation ?? defaultValue,
      setGroupFixation: (charId, v) =>
          groups.memberForWrite(charId).fixation = v,
      getGroupFixationLifespan: (charId, {int defaultValue = 0}) =>
          slots()[charId]?.fixationLifespan ?? defaultValue,
      setGroupFixationLifespan: (charId, v) =>
          groups.memberForWrite(charId).fixationLifespan = v,
      getGroupRelationshipTier: (charId, {int defaultValue = 0}) =>
          slots()[charId]?.relationshipTier ?? defaultValue,
      setGroupRelationshipTier: (charId, v) =>
          groups.memberForWrite(charId).relationshipTier = v,
      getGroupLongTermTier: (charId, {int defaultValue = 0}) =>
          slots()[charId]?.longTermTier ?? defaultValue,
      setGroupLongTermTier: (charId, v) =>
          groups.memberForWrite(charId).longTermTier = v,
      getGroupSpatialStance: (charId, {String defaultValue = ''}) =>
          slots()[charId]?.spatialStance ?? defaultValue,
      setGroupSpatialStance: (charId, v) =>
          groups.memberForWrite(charId).spatialStance = v,
      getGroupWithUser: (charId) => slots()[charId]?.withUser,
      setGroupWithUser: (charId, v) =>
          groups.memberForWrite(charId).withUser = v,
      getGroupInterCharacterRelationships: (charId) =>
          slots()[charId]?.relationships ?? const <String, int>{},
      setGroupInterCharacterRelationships: (charId, rels) =>
          groups.memberForWrite(charId).relationships = rels,
      getGroupCounter: (charId, key, {int defaultValue = 0}) =>
          groups.intOr(charId, key, defaultValue),
      setGroupCounter: (charId, key, v) =>
          groups.memberForWrite(charId).setValue(key, v),
      // Living Time §7 v1.5: bond/trust tier crossings → "Our Story" cards.
      // Fire-and-forget; plant never throws. Owner is the current speaker.
      onTierCrossing: (crossing) {
        // A Feelings re-score holds its crossings until its score is kept.
        final reprocess = deps.doors.edits().reprocess;
        if (reprocess.rescoringFeelings) {
          reprocess.rescoreCrossings.add(crossing);
          return;
        }
        plantTierCrossing(crossing, citeLength: session.messages.length);
      },
    );
  }

  /// Plants an Our Story card for a tier the score crossed. [citeLength] is
  /// the transcript length the reply being scored lands at.
  void plantTierCrossing(TierCrossing crossing, {required int citeLength}) {
    final sessionId = session.currentSessionId;
    if (sessionId == null) return;
    final charId = groups.currentSpeakerId();
    if (charId.isEmpty) return;
    unawaited(
      RelationshipMilestones.plant(
        store: journalStore,
        sessionId: sessionId,
        characterId: charId,
        crossing: crossing,
        sourcePositions: persistTipCite(
          base: deps.doors.sessions().history.basePosition,
          length: citeLength,
        ),
        storyDay: time.dayCount,
        storyClock: time.storyClockIso,
        maxCards: deps.services.storage.memorySettings.journalMaxCards,
      ),
    );
  }
}
