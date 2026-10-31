// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// Phase 2 package payload: Growth rings + Objectives (export/import).
extension ChatServicePackageExtras on ChatService {
  Future<Map<String, dynamic>> _exportGrowthForPackage() async {
    final sid = _session.currentSessionId;
    if (sid == null) return const {};
    final rings = await _db.getGrowthRingsForSession(sid);
    final cursor = await _db.getGrowthCursor(sid);
    return {
      'cursor': cursor,
      'rings': [
        for (final r in rings)
          {
            'character_id': r.characterId,
            'content': r.content,
            'category': r.category,
            'strength': r.strength,
            'pinned': r.pinned,
            'retired': r.retired,
            'source_message_ids': _decodeIntList(r.sourceMessageIds),
            if (r.metadata != null && r.metadata!.isNotEmpty)
              'metadata': r.metadata,
          },
      ],
    };
  }

  Future<List<Map<String, dynamic>>> _exportObjectivesForPackage() async {
    final sid = _session.currentSessionId;
    if (sid == null) return const [];
    final owners = <String>{
      if (_session.activeCharacter != null)
        _getCharacterIdFromCard(_session.activeCharacter!),
      for (final c in _groupCharacters) _getCharacterIdFromCard(c),
    }..removeWhere((e) => e.isEmpty);

    final out = <Map<String, dynamic>>[];
    for (final oid in owners) {
      final rows = await _db.getObjectivesForCharacter(oid, chatId: sid);
      for (final o in rows) {
        out.add({
          'character_id': o.characterId,
          'objective': o.objective,
          'tasks': o.tasks,
          'active': o.active,
          'is_primary': o.isPrimary,
          'check_frequency': o.checkFrequency,
          'injection_depth': o.injectionDepth,
          if (o.servedAmbition != null) 'served_ambition': o.servedAmbition,
          // v58: who the goal is from, and where it stands.
          'origin': objectiveOrigin(o),
          if (o.status != null) 'status': o.status,
        });
      }
    }
    return out;
  }

  Future<void> _importGrowthFromPackage(Map<String, dynamic> growth) async {
    final sid = _session.currentSessionId;
    if (sid == null) return;
    final cursor = (growth['cursor'] as num?)?.toInt() ?? 0;
    final rings = growth['rings'] as List? ?? const [];
    for (final raw in rings) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final cid = (m['character_id'] as String? ?? '').trim();
      final content = (m['content'] as String? ?? '').trim();
      if (cid.isEmpty || content.isEmpty) continue;
      final sources =
          (m['source_message_ids'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const <int>[];
      await _db.insertGrowthRing(
        GrowthRingsCompanion(
          sessionId: drift.Value(sid),
          characterId: drift.Value(cid),
          content: drift.Value(content),
          category: drift.Value(m['category'] as String? ?? 'trait'),
          strength: drift.Value((m['strength'] as num?)?.toDouble() ?? 0.3),
          pinned: drift.Value(m['pinned'] == true),
          retired: drift.Value(m['retired'] == true),
          sourceMessageIds: drift.Value(
            sources.isEmpty ? null : jsonEncode(sources),
          ),
          metadata: drift.Value(
            m['metadata'] is String
                ? m['metadata'] as String
                : (m['metadata'] is Map ? jsonEncode(m['metadata']) : null),
          ),
        ),
      );
    }
    await _db.setGrowthCursor(sid, cursor.clamp(0, _session.messages.length));
    // Canonical roster refresh (group + 1:1). Scene guests are cleared on
    // import seed, so guest-owned rings from the package stay in DB for
    // that session id but are not injected until a guest re-enters.
    await _growthDesk.refreshCache();
  }

  Future<void> _importObjectivesFromPackage(List<dynamic> list) async {
    final sid = _session.currentSessionId;
    if (sid == null) return;
    for (final raw in list) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final cid = (m['character_id'] as String? ?? '').trim();
      final objective = (m['objective'] as String? ?? '').trim();
      if (cid.isEmpty || objective.isEmpty) continue;
      final tasks = m['tasks'];
      final tasksJson = tasks is String
          ? tasks
          : (tasks is List ? jsonEncode(tasks) : '[]');
      await _db.insertObjective(
        ObjectivesCompanion(
          characterId: drift.Value(cid),
          chatId: drift.Value(sid),
          objective: drift.Value(objective),
          tasks: drift.Value(tasksJson),
          active: drift.Value(m['active'] != false),
          isPrimary: drift.Value(m['is_primary'] == true),
          checkFrequency: drift.Value(
            (m['check_frequency'] as num?)?.toInt() ?? 3,
          ),
          injectionDepth: drift.Value(
            (m['injection_depth'] as num?)?.toInt() ?? 4,
          ),
          servedAmbition: drift.Value(m['served_ambition'] as String?),
          // A package from before v58 carries neither: the read-time rule
          // (objectiveOrigin) classifies it the way the ladder would.
          origin: drift.Value(m['origin'] as String?),
          status: drift.Value(m['status'] as String?),
        ),
      );
    }
    // 1:1 vs group loaders differ — same both-paths block as other sites.
    if (_activeGroup != null) {
      await _loadObjectivesForCurrentSpeaker();
    } else {
      await _loadActiveObjectives();
    }
  }

  List<int> _decodeIntList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final d = jsonDecode(raw);
      if (d is List) return d.map((e) => (e as num).toInt()).toList();
    } catch (_) {}
    return const [];
  }
}
