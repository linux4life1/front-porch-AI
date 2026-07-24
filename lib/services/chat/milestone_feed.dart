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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';

/// One "Our Story" timeline entry (living-time-features.md §7 v1).
class MilestoneEntry {
  /// 'ring' | 'chance' | 'objective' | 'memory' | 'dream' | 'ambition' |
  /// 'milestone' | 'promise'
  final String kind;
  final String text;
  final int? storyDay;

  /// Message position for tap-to-jump, when a receipt exists.
  final int? position;
  final String? emotion;
  final DateTime? wallTime;

  const MilestoneEntry({
    required this.kind,
    required this.text,
    this.storyDay,
    this.position,
    this.emotion,
    this.wallTime,
  });
}

/// Pure read-model aggregator over data the app already persists — growth
/// rings, salient journal cards (pinned / strong-feeling / dreams),
/// Chance Time narrations, and achieved objectives. ZERO new writes in v1
/// (threshold-crossing milestone cards are the documented v1.5 follow-up).
///
/// Ordering: story position where a receipt exists (cards, rings, chance
/// narrations); entries that only know wall-clock time (objectives, ringless
/// receipts) are interleaved via the cards' own (wallTime → position) index —
/// the diary doubles as the mapping between real time and story position.
class MilestoneFeed {
  final AppDatabase? Function() getDb;

  MilestoneFeed({required this.getDb});

  static int? _maxPosition(String? sourceIdsJson) {
    if (sourceIdsJson == null || sourceIdsJson.isEmpty) return null;
    try {
      final list = jsonDecode(sourceIdsJson);
      if (list is! List || list.isEmpty) return null;
      return list.whereType<num>().map((n) => n.toInt()).fold<int?>(
        null,
        (max, v) => max == null || v > max ? v : max,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _kindOf(JournalMemoryData card) {
    final raw = card.metadata;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded['kind'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<MilestoneEntry>> entriesFor({
    required String sessionId,
    required String characterId,
    required List<ChatMessage> messages,
  }) async {
    final db = getDb();
    if (db == null) return const [];

    final entries = <MilestoneEntry>[];
    // Wall-time → story-position index, built from every card that carries
    // both (used to interleave position-less sources).
    final timeIndex = <(DateTime, int)>[];

    for (final card in await db.getJournalCards(sessionId, characterId)) {
      final pos = _maxPosition(card.sourceMessageIds);
      if (pos != null) timeIndex.add((card.createdAt, pos));
      // Card kinds (Living Time): dreams §1, ambition progress + waypoint
      // milestones §6 — all timeline-salient by nature; plain cards need
      // pinning or a strong feeling to make the cut.
      final kind = switch (_kindOf(card)) {
        'dream' => 'dream',
        'ambition' => 'ambition',
        'milestone' => 'milestone',
        'promise' => 'promise',
        _ => 'memory',
      };
      final salient =
          card.pinned || card.emotionIntensity == 'strong' || kind != 'memory';
      if (!salient) continue;
      final (day, _) = JournalStore.stampOf(card);
      entries.add(
        MilestoneEntry(
          kind: kind,
          text: card.content,
          storyDay: day,
          position: pos,
          emotion: card.emotionLabel,
          wallTime: card.createdAt,
        ),
      );
    }

    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.activeMetadata?['is_chance_time_narration'] != true) continue;
      entries.add(
        MilestoneEntry(
          kind: 'chance',
          text: m.text
              .replaceAll('[🎰 CHANCE TIME! ', '')
              .replaceAll(']', ''),
          position: i,
        ),
      );
    }

    for (final ring in await db.getGrowthRings(sessionId, characterId)) {
      final pos = _maxPosition(ring.sourceMessageIds);
      if (pos != null) timeIndex.add((ring.createdAt, pos));
      entries.add(
        MilestoneEntry(
          kind: 'ring',
          text: ring.retired ? '${ring.content} (outgrown)' : ring.content,
          position: pos,
          wallTime: ring.createdAt,
        ),
      );
    }

    for (final o in await db.getObjectivesForCharacter(
      characterId,
      chatId: sessionId,
    )) {
      if (o.active) continue;
      bool achieved;
      try {
        final tasks = jsonDecode(o.tasks);
        achieved = tasks is List &&
            tasks.isNotEmpty &&
            tasks.every((t) => t is Map && t['completed'] == true);
      } catch (_) {
        achieved = false;
      }
      if (!achieved) continue;
      entries.add(
        MilestoneEntry(
          kind: 'objective',
          text: 'Objective achieved: ${o.objective}',
          wallTime: o.createdAt,
        ),
      );
    }

    timeIndex.sort((a, b) => a.$1.compareTo(b.$1));
    int pseudoPosition(DateTime? t) {
      if (t == null || timeIndex.isEmpty) return -1;
      var best = -1;
      for (final (wall, pos) in timeIndex) {
        if (wall.isAfter(t)) break;
        best = pos;
      }
      return best;
    }

    entries.sort((a, b) {
      final pa = a.position ?? pseudoPosition(a.wallTime);
      final pb = b.position ?? pseudoPosition(b.wallTime);
      if (pa != pb) return pa.compareTo(pb);
      final ta = a.wallTime;
      final tb = b.wallTime;
      if (ta != null && tb != null) return ta.compareTo(tb);
      return 0;
    });
    return entries;
  }
}
