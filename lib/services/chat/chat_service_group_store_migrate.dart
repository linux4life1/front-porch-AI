// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// One-time, idempotent re-key of group stores from a legacy name/
/// stableGroupId onto [groupMemberStoreId] (UUID when the member has one).
extension ChatServiceGroupStoreMigrate on ChatService {
  /// Move live maps + definition blobs. Persist the group row when
  /// definition keys moved. Returns true when a session-scoped map moved
  /// (caller persists the session once).
  bool _rekeyGroupStores() {
    if (_activeGroup == null) return false;
    final members = _groupCharacters;
    if (members.isEmpty) return false;

    var sessionChanged = false;
    sessionChanged |= migrateGroupStoreKeys(_groupRealism, members);
    sessionChanged |= migrateGroupStoreKeys(_groupAuthorNotes, members);
    sessionChanged |= migrateGroupStoreKeys(_groupAuthorNoteStrengths, members);
    sessionChanged |= migrateGroupStoreKeys(
      _groupCharacterSystemPrompts,
      members,
    );
    sessionChanged |= migrateGroupStoreKeys(
      _groupCharacterRAGPriorities,
      members,
    );
    sessionChanged |= migrateGroupStoreKeys(_groupObjectives, members);
    sessionChanged |= _rekeyGroupMemberRelationships(members);

    if (_rekeyGroupDefinitionBlobs(members)) {
      final group = _activeGroup;
      final repo = _groupChatRepository;
      if (group != null && repo != null) {
        unawaited(() async {
          try {
            await repo.save(group);
          } catch (e) {
            debugPrint('[GroupStore] Failed to persist rekeyed group: $e');
          }
        }());
      }
    }
    unawaited(_rekeyGroupObjectiveRows(members));
    return sessionChanged;
  }

  /// Session-scoped rows always move. Card-level rows move only when
  /// no library character already owns that legacy key.
  Future<void> _rekeyGroupObjectiveRows(Iterable<CharacterCard> members) async {
    final sid = _currentSessionId;
    try {
      for (final member in members) {
        final dest = groupMemberStoreId(member);
        final legacy = member.stableGroupId;
        if (dest == legacy) continue;
        if (sid != null) {
          await _db.rekeyObjectiveCharacterId(legacy, dest, chatId: sid);
        }
        final clash =
            _characterRepository?.characters.any(
              (c) => c.stableGroupId == legacy && c.dbId != member.dbId,
            ) ??
            false;
        if (!clash) {
          await _db.rekeyObjectiveCharacterId(legacy, dest);
        }
      }
    } catch (e) {
      debugPrint('[GroupStore] Failed to rekey objective rows: $e');
    }
  }

  bool _rekeyGroupMemberRelationships(Iterable<CharacterCard> members) {
    final idMap = groupMemberLegacyIdMap(members);
    if (idMap.isEmpty) return false;
    var changed = false;
    for (final state in _groupRealism.values) {
      final rels = state.relationships;
      if (rels == null || rels.isEmpty) continue;
      if (!rels.keys.any(idMap.containsKey)) continue;
      state.relationships = {
        for (final e in rels.entries) idMap[e.key] ?? e.key: e.value,
      };
      changed = true;
    }
    return changed;
  }

  bool _rekeyGroupDefinitionBlobs(Iterable<CharacterCard> members) {
    final group = _activeGroup;
    if (group == null) return false;
    var changed = false;

    Map<String, dynamic> decode(String raw) {
      if (raw.isEmpty || raw == '{}') return {};
      try {
        final decoded = jsonDecode(raw);
        return decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      } catch (_) {
        return {};
      }
    }

    final defaults = decode(group.defaultMemberRealismState);
    if (defaults.isNotEmpty && migrateGroupRealismBlobKeys(defaults, members)) {
      group.defaultMemberRealismState = jsonEncode(defaults);
      changed = true;
    }

    final baseline = decode(group.baselineRealismState);
    if (baseline.isNotEmpty && migrateGroupStoreKeys(baseline, members)) {
      group.baselineRealismState = jsonEncode(baseline);
      changed = true;
    }

    changed |= migrateGroupStoreKeys(group.characterSystemPrompts, members);
    return changed;
  }
}
