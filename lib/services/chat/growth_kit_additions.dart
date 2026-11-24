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

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character/trait_kit.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/group_member_realism.dart'
    show GroupRealismKeys;
import 'package:front_porch_ai/services/chat/growth_kit_seed.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// Kit entries added in the editor mid-chat (maintainer ruling 2026-11-24):
/// an entry the author appends to a card's Boons & Bogies kit lands AT ONCE
/// as a ring in every chat with that character, at the tier and pin the
/// author set — the save is the author's yes. Without this a chat whose kit
/// had seeded never saw a new entry, and one that had not only got an offer
/// in the Growth panel (docs/design/boons-and-bogies.md §4).
///
/// Which chats: a library card's 1:1 chats (rings keyed by its
/// `stableGroupId`) and the 1:1 chats it visits as a scene guest; a group
/// member's copy (its own row, "the group keeps its own copy") reaches that
/// group's chats under the member's store id. A chat with Boons & Bogies off
/// for that character takes nothing (ruling 18's freeze); words a live ring
/// already says and bogeys past the cap of three are skipped.
class GrowthKitAdditions {
  GrowthKitAdditions({
    required this.store,
    required this.getDb,
    required this.featureOn,
    required this.openSessionId,
    required this.openBbFor,
    required this.refreshOpen,
  });

  final GrowthStore store;
  final AppDatabase? Function() getDb;

  /// Porch Life: Growth and Boons & Bogies both on.
  final bool Function() featureOn;

  /// The chat on screen: its switches are read live, not from the DB row,
  /// and its Growth cache is refreshed after a write.
  final String? Function() openSessionId;
  final bool Function(String ownerId) openBbFor;
  final Future<void> Function() refreshOpen;

  /// A library card's save: [before] is its kit as it was when the editor
  /// opened. Returns how many rings were written.
  Future<int> forLibraryCard(
    CharacterCard card,
    List<TraitKitEntry> before,
  ) async {
    final added = GrowthKitSeed.added(before, _kit(card));
    final db = getDb();
    final dbId = card.dbId;
    if (added.isEmpty || db == null || dbId == null || !featureOn()) return 0;
    final ownerId = card.stableGroupId;
    final targets = <_Target>[
      for (final s in await db.getSessionsForCharacter(dbId))
        _Target(s, ownerId, oneToOne: true),
      for (final s in await _guestSessions(db, dbId))
        _Target(s, ownerId, oneToOne: true),
    ];
    return _write(targets, added);
  }

  /// A group member's copy saved (desktop Edit group or the open group's
  /// member editor, web member edit): [memberId] is its `group_members` id.
  Future<int> forGroupMember(
    String memberId,
    CharacterCard card,
    List<TraitKitEntry> before,
  ) async {
    final added = GrowthKitSeed.added(before, _kit(card));
    final db = getDb();
    if (added.isEmpty || db == null || !featureOn()) return 0;
    final row = await (db.select(
      db.groupMembers,
    )..where((m) => m.id.equals(memberId))).getSingleOrNull();
    if (row == null) return 0;
    final ownerId = groupMemberStoreId(card);
    return _write([
      for (final s in await db.getSessionsForGroup(row.groupId))
        _Target(s, ownerId, oneToOne: false),
    ], added);
  }

  Future<int> _write(List<_Target> targets, List<TraitKitEntry> added) async {
    final open = openSessionId();
    var written = 0;
    var touchedOpen = false;
    for (final t in targets) {
      final id = t.session.id;
      if (!(id == open ? openBbFor(t.ownerId) : t.bbOn)) continue;
      final rings = (await store.ringsFor(
        id,
        t.ownerId,
      )).where((r) => !r.retired).toList();
      final plan = GrowthKitSeed.planAdditions(
        added: added,
        activeRings: rings,
      );
      for (final r in plan) {
        await store.addRing(
          sessionId: id,
          characterId: t.ownerId,
          content: r.characterText,
          category: r.category,
          strength: r.strength,
          pinned: r.pinned,
          metadata: r.metadata,
          advanceCount: r.advanceCount,
        );
      }
      written += plan.length;
      touchedOpen |= id == open && plan.isNotEmpty;
      // A 1:1 chat that never settled its kit would still offer it in the
      // Growth panel; the entries it would add are here now.
      if (t.oneToOne && plan.isNotEmpty) {
        final db = getDb();
        if (db != null &&
            await db.getKitSeedState(id) == GrowthKitSeed.kStateUnsettled) {
          await store.setKitSeedState(id, GrowthKitSeed.kStateSettled);
        }
      }
    }
    if (touchedOpen) await refreshOpen();
    if (written > 0) {
      debugPrint(
        '[Growth] kit edit: $written ring(s) into ${targets.length} '
        'chat(s)',
      );
    }
    return written;
  }

  /// 1:1 chats this character visits as a scene guest (their dbIds ride
  /// `group_realism_state.sceneGuests`).
  Future<List<Session>> _guestSessions(AppDatabase db, String dbId) async {
    final rows =
        await (db.select(db.sessions)..where(
              (s) =>
                  s.groupId.isNull() &
                  s.deletedAt.isNull() &
                  s.groupRealismState.like('%sceneGuests%'),
            ))
            .get();
    return [
      for (final s in rows)
        if (_guestIds(s).contains(dbId)) s,
    ];
  }

  static List<String> _guestIds(Session s) {
    try {
      final json = jsonDecode(s.groupRealismState);
      final ids = json is Map ? json['sceneGuests'] : null;
      return ids is List ? ids.whereType<String>().toList() : const [];
    } catch (e) {
      debugPrint('[Growth] kit edit: unreadable guest list on ${s.id}: $e');
      return const [];
    }
  }

  static List<TraitKitEntry> _kit(CharacterCard card) =>
      card.frontPorchExtensions?.traitKit ?? const [];
}

/// One chat to write into, and the owner whose rings it holds.
class _Target {
  _Target(this.session, this.ownerId, {required this.oneToOne});

  final Session session;
  final String ownerId;
  final bool oneToOne;

  /// The stored switch: a 1:1 chat's (guests share it), or the member's own
  /// `bb_switch` in a group (absent: on, as the group store reads it).
  bool get bbOn {
    if (oneToOne) return session.bbEnabled;
    try {
      final json = jsonDecode(session.groupRealismState);
      final per = json is Map ? json['perChar'] : null;
      final me = per is Map ? per[ownerId] : null;
      final v = me is Map ? me[GroupRealismKeys.bbSwitch] : null;
      return v is bool ? v : true;
    } catch (e) {
      debugPrint('[Growth] kit edit: unreadable group state: $e');
      return true;
    }
  }
}
