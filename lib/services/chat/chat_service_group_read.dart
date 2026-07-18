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

/// Per-group-character realism / needs **read** accessors consumed by the UI
/// (sidebar member cards, group member grid, roster). Pure reads over the
/// `_groupRealism` map plus the one mutating reset helper; no orchestration.
///
/// Extracted verbatim from `chat_service.dart` (zero behaviour change) to shrink
/// the god file toward the 500-line cap. As a `part of` the same library, this
/// extension reaches the private `_groupRealism` map, `_getCharacterIdFromCard`,
/// `_activeGroup`, and `isGroupRealismActive` exactly as the in-class methods did.
extension ChatServiceGroupRead on ChatService {
  /// Returns the current emotion label (e.g. "joy", "sadness", "affection") for
  /// the given character when in a realism-enabled group chat. Returns null otherwise.
  String? getEmotionForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?['emotion'] as String?;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  /// Returns a snapshot of all realism data for a specific character in the
  /// current group (when `isGroupRealismActive` is true). Includes keys like:
  /// 'emotion', 'emotionIntensity', 'affection', 'trust', 'needs', 'fixation',
  /// and (when group size ≤ 4) the hidden 'relationships' map toward other members.
  /// This is primarily for debugging/advanced use; the UI never exposes inter-char data.
  /// Returns null if not in an active realism group or no data for that char.
  Map<String, dynamic>? getRealismStateForGroupCharacter(
    CharacterCard character,
  ) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final data = _groupRealism[id];
    return (data != null && data.isNotEmpty) ? Map.unmodifiable(data) : null;
  }

  // ── Convenient per-character realism accessors for the UI ───────────────

  /// Returns the full needs vector for the given group character.
  /// Empty map if not in group realism mode or no data.
  /// Only official needs keys are returned (legacy bad keys such as 'arousal'/'libido'
  /// from older group data are silently filtered).
  Map<String, int> getNeedsForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return const {};
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?['needs'];
    final result = <String, int>{};
    for (final k in NeedsSimulation.needKeys) {
      final v = (raw is Map) ? raw[k] : null;
      if (v is num) {
        result[k] = v.toInt();
      } else {
        // Fill any missing official needs so the UI always shows the complete set.
        // This handles legacy/incomplete group data after previous cleanups.
        result[k] = NeedsSimulation.needDefaults[k] ?? 80;
      }
    }
    return result;
  }

  int getAffectionForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return (_groupRealism[id]?['affection'] as num?)?.toInt() ?? 0;
  }

  int getTrustForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return (_groupRealism[id]?['trust'] as num?)?.toInt() ?? 0;
  }

  String? getFixationForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?['fixation'] as String?;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  int getArousalForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return (_groupRealism[id]?['arousal'] as num?)?.toInt() ?? 0;
  }

  String? getEmotionIntensityForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?['emotionIntensity'] as String?;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  /// Returns the remaining lifespan (in turns) for the current fixation of the
  /// given group character, if any. Returns null if not in active group realism
  /// or no fixation data.
  int? getFixationLifespanForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?['fixationLifespan'] as num?;
    return raw?.toInt();
  }

  /// Returns the top N most urgent needs (lowest value first) for the character,
  /// as a list of (needName, value) pairs.
  List<(String, int)> getTopUrgentNeedsForGroupCharacter(
    CharacterCard character, {
    int count = 2,
  }) {
    final needs = getNeedsForGroupCharacter(character);
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
      notifyListeners();
    }
  }
}
