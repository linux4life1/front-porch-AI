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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

import 'entry_door.dart';

/// Per-member realism and Needs reads for the group UI (sidebar member
/// cards, the member grid, the phone): pure reads over the group's
/// per-member map, plus the one reset of a member's state. Each member's
/// numbers are the same records a 1:1 shows for the same character.
class GroupMemberReads {
  GroupMemberReads(this._door, this._d);

  final EntryDoor _door;
  final EntryDeps _d;

  ChatSessionState get _session => _d.session;
  EntryServices get _s => _d.services;
  RealismScope get _scope => _s.realism();
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  GroupRealismStore get _groupStore => _scope.groups;
  Map<String, GroupMemberRealism> get _groupRealism => _groupStore.members;
  ExpressionService get _expression => _s.expression();
  MoodRegisters get _mood => _s.mood();
  bool get _realismEnabled => _scope.realismEnabled();
  bool get _clockRunning => _scope.clockRunning();
  String _getCharacterIdFromCard(CharacterCard c) =>
      _d.shared.characterIdFor(c);

  /// Empty stance fails toward here. Group card glance.
  String spatialStanceForGroupCharacter(CharacterCard character) {
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.spatialStance ?? '';
  }

  /// Glance judge for a group card. Null = unknown (keyword fallback).
  bool? withUserForGroupCharacter(CharacterCard character) {
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.withUser;
  }

  /// Returns the current emotion label (e.g. "joy", "sadness", "affection") for
  /// the given character when in a realism-enabled group chat. Returns null otherwise.
  String? getEmotionForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?.emotion;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  /// Returns a snapshot of all realism data for a specific character in the
  /// current group (when `isGroupRealismActive` is true). Includes keys like:
  /// 'emotion', 'emotionIntensity', 'affection', 'trust', 'needs', 'fixation',
  /// and (when group size ≤ 4) the hidden 'relationships' map toward other members.
  /// The 'relationships' map is shown read-only as Group Dynamics (the
  /// sidebar section on desktop and the PWA; see [GroupDynamics.of]). It is
  /// never editable from the UI.
  /// Returns null if not in an active realism group or no data for that char.
  Map<String, dynamic>? getRealismStateForGroupCharacter(
    CharacterCard character,
  ) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final data = _groupRealism[id];
    return (data != null && data.isNotEmpty)
        ? Map.unmodifiable(data.toJson())
        : null;
  }

  // ── Convenient per-character realism accessors for the UI ───────────────

  /// Returns the full needs vector for the given group character.
  /// Empty map if not in group realism mode or no data.
  /// Only official needs keys are returned (legacy bad keys such as 'arousal'/'libido'
  /// from older group data are silently filtered).
  Map<String, int> getNeedsForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return const {};
    return _groupStore.needsOf(_getCharacterIdFromCard(character));
  }

  int getAffectionForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.affection ?? 0;
  }

  /// Long-term bond for one group member.
  ///
  /// This accessor was simply missing, and both clients worked around its
  /// absence by showing something else: the desktop member card passed the
  /// SHORT-term score to both bond rows, and the web facade hard-coded 0 under
  /// a comment claiming long-term is not tracked per member. It is — the
  /// per-speaker load/save pair moves `longTermScore` in and out of the group
  /// blob on every turn, and it grows on its own cadence, so it genuinely
  /// diverges from short-term.
  ///
  /// Falls back to short-term when the key is absent, matching what
  /// [RelationshipService.loadRelationshipScalarsForSpeaker] does when it seeds
  /// a member who predates the key.
  int getLongTermForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    final entry = _groupRealism[id];
    return entry?.longTermScore ?? entry?.affection ?? 0;
  }

  int getTrustForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.trust ?? 0;
  }

  String? getFixationForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?.fixation;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  int getArousalForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.arousal ?? 0;
  }

  /// The member's own recovery in the 1:1 chip's words, with its minutes and
  /// whether it is a soft window: off their own entry, never the live
  /// scalars, which hold whoever was loaded last. Empty while none runs and
  /// while Afterglow does not run for them.
  ({String chip, bool soft, int minutes}) getRefractoryForGroupCharacter(
    CharacterCard character,
  ) {
    if (!isGroupRealismActive || !_door.members.afterglowRunsFor(character)) {
      return (chip: '', soft: false, minutes: 0);
    }
    final body =
        _groupRealism[_getCharacterIdFromCard(character)]?.refractory ??
        Refractory.none;
    final words = describeRefractory(
      body.minutes,
      clockRunning: _clockRunning,
      soft: body.soft,
      peaks: body.peaksLastHour,
    );
    return (chip: words.chip, soft: body.soft, minutes: body.minutes);
  }

  /// Porch Life's Expressions switch: the phone shows a mood picture only
  /// while it is on, as the desktop sidebar does.
  bool get expressionsEnabled =>
      _s.storage.expressionSettings.expressionEnabled;

  /// The face label for [character]. In 1:1, the chat's label. In a group,
  /// the member's own mood: the live label (ONNX) is theirs only when it was
  /// classified from a reply they wrote, never a System row or a streaming
  /// placeholder.
  String? expressionLabelFor(CharacterCard character) {
    if (_activeGroup == null) return _expression.currentExpressionLabel;
    if (_s.storage.expressionSettings.expressionClassificationMode == 'onnx') {
      // Read first: it keeps the classifier following new replies.
      final live = _expression.currentExpressionLabel;
      final source = _expression.onnxLabelSource;
      final speaker = source == null || source.sender == 'System'
          ? null
          : resolveGroupSpeakerForMessage(
              _groupCharacters,
              source,
              logOnMiss: false,
            );
      if (speaker != null &&
          _getCharacterIdFromCard(speaker) ==
              _getCharacterIdFromCard(character)) {
        return live;
      }
    }
    return _expression.labelForEmotion(
      getEmotionForGroupCharacter(character) ?? '',
    );
  }

  String? getEmotionIntensityForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?.emotionIntensity;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  /// The member's whole mood (label, intensity, cause, hold) for the member
  /// card and the phone, or null outside active group realism.
  MoodState? getMoodForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    return _mood.memberState(_getCharacterIdFromCard(character));
  }

  /// Returns the remaining lifespan (in turns) for the current fixation of the
  /// given group character, if any. Returns null if not in active group realism
  /// or no fixation data.
  int? getFixationLifespanForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    return _groupRealism[id]?.fixationLifespan;
  }

  /// Returns the top N most urgent needs (lowest value first) for the character,
  /// as a list of (needName, value) pairs.
  List<(String, int)> getTopUrgentNeedsForGroupCharacter(
    CharacterCard character, {
    int count = 2,
  }) {
    final needs = visibleNeeds(
      getNeedsForGroupCharacter(character),
      character.frontPorchExtensions?.needsOff ?? const [],
    );
    if (needs.isEmpty) return const [];

    final sorted = needs.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value)); // lowest = most urgent

    return sorted.take(count).map((e) => (e.key, e.value)).toList();
  }

  /// Clears the per-character realism state (emotion, bond/affection, trust,
  /// arousal, fixation, needs vector, and any hidden inter-character relationships)
  /// for the specified character in the current group chat session.
  /// Safe to call even if no prior state existed for the character.
  void resetRealismForGroupCharacter(CharacterCard character) {
    if (_activeGroup == null) return;
    final id = _getCharacterIdFromCard(character);
    if (_groupRealism.containsKey(id)) {
      _groupRealism.remove(
        id,
      ); // also clears hidden 'relationships' toward other group members
      // (old checkpoint call removed in v30)
      debugPrint('[GroupRealism] Reset per-character state for $id');
      _d.notify();
    }
  }

  /// True for group chats where the Realism Engine is enabled, Director Mode
  /// included: the per-character state still shows (held still while the
  /// user is off stage) and the cast's feelings for each other keep moving.
  /// Used by the group sidebar to decide whether to show per-character
  /// emotion / needs indicators.
  bool get isGroupRealismActive =>
      _realismEnabled && (_session.groupManager?.isActive ?? false);

  /// Phase 3: Hard cap for inter-character relationship tracking.
  /// Hidden inter-character dynamics (seeding, decay, injection, updates)
  /// run only when the group has 2–4 **full** members. Soft (lite) guests
  /// do not count and never join the graph.
  ///
  /// When the group has 5+ full members:
  /// - Inter-character 'relationships' maps remain empty / are ignored.
  /// - Full members still receive per-speaker realism evaluations for
  ///   their feelings **toward the user** (visible bars continue to work).
  bool get shouldTrackInterCharacterRelationships {
    if (_activeGroup == null) return false;
    return shouldTrackInterCharacterAmong(_groupCharacters);
  }
}
