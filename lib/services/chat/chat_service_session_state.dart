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

/// While [_loadLastSession] hydrates, [_doSaveChat] must not stamp the
/// still-live previous chat's persona onto the row being loaded.
final Expando<bool> _preserveSessionPersonaOf = Expando();

/// Scene-guest and group-realism hydrate, plus small session accessors.
/// Persist lives in chat_service_session_state_save.dart (same library).
extension ChatServiceSessionState on ChatService {
  // v30: Load per-character group realism/needs state.
  // Priority:
  // 1. Live state from the current session's group_realism_state column (if present and non-empty).
  // 2. Default state from the group's default_member_realism_state (important for Group Card imports and new sessions).
  //
  // Pass null for `session` to force-load from group defaults only (used for brand-new group chats).
  /// Restore Scene Guest (Lite NPC) dbIds for a 1:1 session from the reused
  /// group realism column, then resolve their cards. Tolerant of missing,
  /// empty, '{}', legacy group state, or malformed JSON (clears guests).
  void _loadSceneGuestsFromSession(Session? session) {
    _sceneGuest.ids.clear();
    _sceneGuest.cards.clear();
    final stateJson = session?.groupRealismState;
    // Timed lorebook effects ride the same blob — hydrate (resets first, so
    // a null/empty session clears any prior chat's timers).
    _loreTimedEffects.hydrate(stateJson);
    if (stateJson == null || stateJson.isEmpty || stateJson == '{}') return;
    try {
      final decoded = jsonDecode(stateJson);
      if (decoded is Map && decoded['sceneGuests'] is List) {
        for (final id in decoded['sceneGuests'] as List) {
          final s = id?.toString();
          if (s != null && s.isNotEmpty) _sceneGuest.ids.add(s);
        }
      }
      // (The old 'guestEvolution' key is no longer read — guest growth lives
      // in the growth_rings table now, keyed by the guest's stable charId.)
    } catch (e) {
      debugPrint('[SceneGuest] Failed to parse sceneGuests from session: $e');
      return;
    }
    if (_sceneGuest.ids.isNotEmpty) {
      // Fire-and-forget resolve; UI updates via notifyListeners inside.
      _resolveSceneGuestCards();
    }
  }

  void _loadGroupRealismStateFromSession(Session? session) {
    if (_activeGroup == null) return;

    String? stateJson = session?.groupRealismState;

    // Timed lorebook effects ride the SESSION blob only (never the group's
    // default-member-state fallback below — defaults carry no chat timers).
    _loreTimedEffects.hydrate(stateJson);

    // Fall back to group definition defaults (crucial for imported Group Cards and split-to-solo)
    if (stateJson == null || stateJson.isEmpty || stateJson == '{}') {
      stateJson = _activeGroup!.defaultMemberRealismState;
    }

    _groupRealism = {};
    _groupDecayRates = {};
    _groupAuthorNotes = {};
    _groupAuthorNoteStrengths = {};
    _groupCharacterSystemPrompts = {};
    _groupCharacterRAGPriorities = {};

    if (stateJson.isNotEmpty && stateJson != '{}') {
      try {
        final decoded = jsonDecode(stateJson);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);

          // Main per-character realism data (needs, emotion, bond, trust, fixation, relationships, arousal, etc.)
          final perChar =
              map['perChar'] ??
              map; // support both wrapped and direct formats during transition
          if (perChar is Map) {
            _groupRealism = perChar.map(
              (k, v) =>
                  MapEntry(k.toString(), GroupMemberRealism.fromJson(v as Map)),
            );
          }

          // Global group decay rates
          final globalDecay = map['globalDecayRates'];
          if (globalDecay is Map) {
            _groupDecayRates = globalDecay.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            );
          }

          // Per-char author notes (scoped to this group)
          final notes = map['authorNotes'];
          if (notes is Map) {
            _groupAuthorNotes = notes.map(
              (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
            );
          }

          final strengths = map['authorNoteStrengths'];
          if (strengths is Map) {
            _groupAuthorNoteStrengths = strengths.map(
              (k, v) => MapEntry(
                k.toString(),
                (v as num?)?.toInt() ?? _authorNoteStrength,
              ),
            );
          }

          final sysPrompts = map['characterSystemPrompts'];
          if (sysPrompts is Map) {
            _groupCharacterSystemPrompts = sysPrompts.map(
              (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
            );
          }

          // RAG settings (now also in the column)
          if (map.containsKey('ragEnabled')) {
            _groupRagEnabled = map['ragEnabled'] as bool? ?? true;
          }
          if (map.containsKey('retrievalCount')) {
            _groupRetrievalCount =
                (map['retrievalCount'] as num?)?.toInt() ?? 4;
          }
          if (map.containsKey('memoryBudgetPercent')) {
            _groupMemoryBudgetPercent =
                (map['memoryBudgetPercent'] as num?)?.toDouble() ?? 10.0;
          }

          final ragPrios = map['characterRAGPriorities'];
          if (ragPrios is Map) {
            _groupCharacterRAGPriorities = ragPrios.map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            );
          }

          // Per-char objectives for group mode (each member has independent tasks)
          _groupObjectives.clear();
          final objMap = map['objectives'];
          if (objMap is Map) {
            objMap.forEach((charId, list) {
              if (list is List) {
                _groupObjectives[charId.toString()] = [];
              }
            });
          }

          // One-time seeding of objectives from an imported Group Card is handled
          // asynchronously after this state load completes (see callers of this method).

          debugPrint(
            '[GroupState v30] Loaded realism state for ${_groupRealism.length} characters '
            '(session + group defaults) for group ${_activeGroup!.name}',
          );
        }
      } catch (e) {
        debugPrint(
          '[GroupState v30] Failed to parse group realism state JSON: $e',
        );
        _groupRealism = {};
      }
    }
  }

  /// Evaluates emotion + relationship baseline from the greeting message only.

  // ── Small session-state accessors, moved verbatim from the god file's
  // field block (zero behaviour change) ──
  bool get isLoadingSession => _isLoadingSession;

  String? get parentSessionId => _parentSessionId;
  int? get forkIndex => _forkIndex;
  String? get sessionName => _sessionName;
  String? get sessionDescription => _sessionDescription;

  /// The per-chat gallery look selected for [characterId] in the active session,
  /// or null (no look chosen → the character's library face shows). Keyed by the
  /// character's library id so the same character shares one selection across a
  /// group cast.
  String? selectedLookFor(String characterId) => _selectedLooks[characterId];

  /// Set (or clear, when [lookId] is null) the per-chat gallery look for
  /// [characterId] in the active session, persist the whole map to the session's
  /// selected-look column, and repaint. Never touches `imagePath` — the library
  /// face is independent of which look shows in a given chat.
  Future<void> setLookForCharacter(String characterId, String? lookId) async {
    final sid = _currentSessionId;
    if (sid == null || characterId.isEmpty) return; // never key by a blank id
    // decodeSelectedLooks also drops empty keys, so a blank would silently fail
    // to round-trip; refuse it here so the caller notices instead.
    if (lookId == null) {
      _selectedLooks.remove(characterId);
    } else {
      _selectedLooks[characterId] = lookId;
    }
    notifyListeners();
    await _db.setSelectedLookForSession(
      sid,
      encodeSelectedLooks(_selectedLooks),
    );
  }
}
