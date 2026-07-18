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

/// Low-level private helpers for reading/writing the per-character group realism
/// map (`_groupRealism`) and resolving the current speaker's id. Pure plumbing
/// over the map — no orchestration or engine logic — extracted verbatim from
/// `chat_service.dart` (zero behaviour change) to shrink the god file. These are
/// private and never part of the public interface, so they are safe to move to
/// an extension (no `implements`/fake can override them).
extension ChatServiceGroupRealismHelpers on ChatService {
  /// Returns the stable charId of the character whose realism state should be
  /// read/written for the current turn. In group mode this is the speaker
  /// we are about to generate for (or just generated for).
  String _getCurrentSpeakerIdForRealism() {
    if (_activeGroup == null || _groupCharacters.isEmpty) {
      return _getCharacterId();
    }
    // During a turn the speaker is pinned the moment they're picked
    // (_generateResponse). Prefer it — it's the only reliable "who is speaking
    // right now" signal, because `nextCharacter` points at the *upcoming*
    // speaker and is null for random turn order (which made this fall back to
    // the first/primary member for every random turn).
    final pinned = _turnSpeakerIdForRealism;
    if (pinned != null &&
        _groupCharacters.any((c) => _getCharacterIdFromCard(c) == pinned)) {
      return pinned;
    }
    // Outside a turn (pre-pick): the upcoming speaker if known (round-robin),
    // else the first member.
    final next = nextCharacter;
    if (next != null) {
      return _getCharacterIdFromCard(next);
    }
    return _getCharacterIdFromCard(_groupCharacters.first);
  }

  // ── Per-character realism state helpers (group mode) ────────────────────
  void _setGroupRealismValue(String charId, String key, dynamic value) {
    if (_activeGroup == null) return;
    _groupRealism.putIfAbsent(charId, () => <String, dynamic>{});
    _groupRealism[charId]![key] = value;
  }

  int _getGroupInt(String charId, String key, {int defaultValue = 0}) =>
      (_groupRealism[charId]?[key] as num?)?.toInt() ?? defaultValue;

  String _getGroupString(
    String charId,
    String key, {
    String defaultValue = '',
  }) => (_groupRealism[charId]?[key] as String?) ?? defaultValue;

  // Tolerant coercion for a needs vector that may arrive as JSON-decoded
  // (num values), dynamic map from metadata/snapshots/pre_state, or proper
  // Map<String,int>. Used for pre-turn vectors in chips, restores, and fallbacks.
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

  Map<String, int> _getGroupNeeds(String charId) {
    final raw = _groupRealism[charId]?['needs'];
    final result = <String, int>{};
    for (final k in NeedsSimulation.needKeys) {
      final v = (raw is Map) ? raw[k] : null;
      if (v is num) {
        result[k] = v.toInt();
      } else {
        result[k] = NeedsSimulation.needDefaults[k] ?? 80;
      }
    }
    return result;
  }

  void _setGroupNeeds(String charId, Map<String, int> needs) {
    _setGroupRealismValue(charId, 'needs', needs);
  }

  /// Needs decay rates for the character being decayed on the CURRENT turn.
  ///
  /// Single source of truth for BOTH the 1:1 `tickDecay` closure and the group
  /// realism-dance decay loop — it replaces the old split where 1:1 read the
  /// host card's ext while a group read one shared `_groupDecayRates` map for
  /// everybody. In 1:1 this is the active host; in a group it is the speaker the
  /// dance has impersonated into `_activeCharacter` before decay, so each member
  /// decays at its OWN authored rate exactly like a solo card.
  ///
  /// Falls back to the legacy shared map only for pre-per-member groups whose
  /// member cards genuinely lack ext data; empty there → downstream uses
  /// `NeedsSimulation.needDecay` defaults (identical to the ext defaults).
  Map<String, int> _activeDecayRates() {
    CharacterCard? card = _activeCharacter;
    if (_activeGroup != null && card == null) {
      // Off the main dance path (e.g. the sim's own tickDecay closure in tests
      // where no character is impersonated): resolve the speaker by id.
      final sid = _getCurrentSpeakerIdForRealism();
      for (final c in _groupCharacters) {
        if (_getCharacterIdFromCard(c) == sid) {
          card = c;
          break;
        }
      }
    }
    final ext = card?.frontPorchExtensions;
    if (ext != null) {
      return {
        'hunger': ext.needsDecayHunger,
        'bladder': ext.needsDecayBladder,
        'energy': ext.needsDecayEnergy,
        'social': ext.needsDecaySocial,
        'fun': ext.needsDecayFun,
        'hygiene': ext.needsDecayHygiene,
        'comfort': ext.needsDecayComfort,
      };
    }
    if (_activeGroup != null && _groupDecayRates.isNotEmpty) {
      return _groupDecayRates;
    }
    return const <String, int>{};
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
  Future<void> _attachNeedsDeltaChipToLastMessage() async {
    if (!_needsSimEnabled || _messages.isEmpty) return;
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
    if (needsDeltas.isEmpty) return;
    _messages.last.activeMetadata ??= {};
    _messages.last.activeMetadata!['needs_deltas'] = needsDeltas;
    debugPrint(
      '[Realism:Needs] Chip: ${needsDeltas.length} need delta(s) attached for '
      '${_messages.last.sender}',
    );
    await _saveChat();
    notifyListeners();
  }
}
