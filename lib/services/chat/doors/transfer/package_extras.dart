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

import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/objective_origin.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';

import 'transfer_host.dart';

/// The per-session rows an `.fpchat` package carries beside its transcript:
/// Journal cards (Phase 1), Growth rings and Objectives (Phase 2), in both
/// directions. Every row is read or written under the open session id.
class PackageExtras {
  PackageExtras(this._session, this._host);

  final ChatSessionState _session;
  final TransferHost _host;

  /// The open chat's row owners: the 1:1 card and every group member.
  Set<String> _owners() => <String>{
    if (_session.activeCharacter != null)
      _host.characterIdFor(_session.activeCharacter!),
    for (final c in _session.groupCharacters) _host.characterIdFor(c),
  }..removeWhere((e) => e.isEmpty);

  // ── Export ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> exportJournalCards() async {
    final sid = _session.currentSessionId;
    if (sid == null) return const [];
    final owners = _owners();
    final out = <Map<String, dynamic>>[];
    for (final oid in owners) {
      final cards = await _host.journalStore().cardsFor(sid, oid);
      for (final c in cards) {
        List<int> sources = const [];
        final rawSources = c.sourceMessageIds;
        if (rawSources != null && rawSources.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawSources);
            if (decoded is List) {
              sources = decoded.map((e) => (e as num).toInt()).toList();
            }
          } catch (_) {}
        }
        Map<String, dynamic>? metaMap;
        final rawMeta = c.metadata;
        if (rawMeta != null && rawMeta.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawMeta);
            if (decoded is Map) {
              metaMap = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}
        }
        out.add({
          'character_id': c.characterId,
          'content': c.content,
          'category': c.category,
          'emotion_label': c.emotionLabel,
          'emotion_intensity': c.emotionIntensity,
          'source_message_ids': sources,
          'pinned': c.pinned,
          'heat': c.heat,
          'metadata': ?metaMap,
          'kind': JournalPhysics.cardKind(c),
        });
      }
    }
    return out;
  }

  Future<Map<String, dynamic>> exportGrowth() async {
    final sid = _session.currentSessionId;
    if (sid == null) return const {};
    final rings = await _host.db().getGrowthRingsForSession(sid);
    final cursor = await _host.db().getGrowthCursor(sid);
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

  Future<List<Map<String, dynamic>>> exportObjectives() async {
    final sid = _session.currentSessionId;
    if (sid == null) return const [];
    final owners = _owners();

    final out = <Map<String, dynamic>>[];
    for (final oid in owners) {
      final rows = await _host.db().getObjectivesForCharacter(oid, chatId: sid);
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

  // ── Import ────────────────────────────────────────────────────────────

  Future<void> importJournalCards(List<dynamic> journal) async {
    final sid = _session.currentSessionId;
    if (sid == null) return;
    final maxCards = _host.storage.memorySettings.journalMaxCards;
    for (final raw in journal) {
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
      final heat = (m['heat'] as num?)?.toDouble();
      final pinned = m['pinned'] == true;
      await _host.journalStore().addCard(
        sessionId: sid,
        characterId: cid,
        content: content,
        category: m['category'] as String? ?? 'moment',
        emotionLabel: m['emotion_label'] as String?,
        emotionIntensity: m['emotion_intensity'] as String?,
        sourcePositions: sources,
        kind: m['kind'] as String?,
        heat: heat,
        pinned: pinned,
        maxCards: maxCards,
        extraMetadata: m['metadata'] is String
            ? null
            : (m['metadata'] is Map
                  ? Map<String, dynamic>.from(m['metadata'] as Map)
                  : null),
      );
    }
  }

  Future<void> importGrowth(Map<String, dynamic> growth) async {
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
      await _host.db().insertGrowthRing(
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
    await _host.db().setGrowthCursor(
      sid,
      cursor.clamp(0, _session.messages.length),
    );
    // Canonical roster refresh (group + 1:1). Scene guests are cleared on
    // import seed, so guest-owned rings from the package stay in DB for
    // that session id but are not injected until a guest re-enters.
    await _host.growthDesk().refreshCache();
  }

  Future<void> importObjectives(List<dynamic> list) async {
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
      await _host.db().insertObjective(
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
    if (_session.activeGroup != null) {
      await _host.loadSpeakerObjectives();
    } else {
      await _host.loadActiveObjectives();
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
