// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Characters and groups link worlds, never a place inside one. Older
// libraries could link a bare place; this lifts those links to the place's
// world on every load (a re-parent can turn a world into a place at any
// time), and once per library gives back the Setting that chats seeded
// from such a link never got.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_repository.dart';

const _repairPrefKey = 'gave_bare_place_chats_a_setting_v1';

class WorldLinkLift {
  WorldLinkLift({
    required WorldRepository repo,
    required AppDatabase Function() db,
    required CharacterRepository? Function() characters,
    required GroupChatRepository? Function() groups,
  }) : _repo = repo,
       _db = db,
       _characters = characters,
       _groups = groups;

  final WorldRepository _repo;
  final AppDatabase Function() _db;
  final CharacterRepository? Function() _characters;
  final GroupChatRepository? Function() _groups;

  List<String> _lift(List<String> refs) =>
      liftLinkRefs(refs, _repo.resolveWorld, _repo.worldById);

  Future<void> run() async {
    try {
      final n = await _db().rewriteWorldRefsInCharactersAndGroups(_lift);
      if (n > 0) debugPrint('[Worlds] lifted place links to their world: $n');
      _liftInMemory();
      await _maybeRepairChats();
    } catch (e) {
      debugPrint('[Worlds] place link lift skipped: $e');
    }
  }

  /// The rows are already written; keep loaded cards and groups in step so
  /// a later save from memory can't put the place back.
  void _liftInMemory() {
    for (final c in _characters()?.characters ?? const []) {
      final lifted = _lift(c.worldNames);
      if (!listEquals(lifted, c.worldNames)) c.worldNames = lifted;
    }
    for (final g in _groups()?.groups ?? const []) {
      final lifted = _lift(g.worldIds);
      if (!listEquals(lifted, g.worldIds)) g.worldIds = lifted;
    }
  }

  /// A chat seeded from a bare place got it as Lore with no Setting, since
  /// the place inherits its climate. Promote the first such place once; a
  /// Setting the user clears afterwards stays cleared.
  Future<void> _maybeRepairChats() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_repairPrefKey) == true) return;
    var repaired = 0;
    for (final chatId in await _db().chatIdsWithoutSetting()) {
      final slots = await _repo.getChatWorldAttachments(chatId);
      final place = slots.loreIds
          .where((id) => _promotableToSetting(id, _repo))
          .firstOrNull;
      if (place == null) continue;
      await _repo.setChatWorldAttachments(
        chatId,
        primaryId: place,
        loreIds: [
          for (final id in slots.loreIds)
            if (id != place) id,
        ],
      );
      repaired++;
    }
    await prefs.setBool(_repairPrefKey, true);
    if (repaired > 0) {
      debugPrint('[Worlds] gave $repaired place-only chat(s) their Setting');
    }
  }
}

/// A place inside a world whose chain authors a climate: what a bare place
/// link should have seeded as the chat's Setting.
bool _promotableToSetting(String id, WorldRepository repo) {
  final w = repo.worldById(id);
  if (w == null || topWorldOf(w, repo.worldById).id == w.id) return false;
  return repo.climateAuthorFor(id) != null;
}

extension LinkableWorlds on WorldRepository {
  /// Top-level worlds only: what a character or group links.
  List<World> get linkableWorlds => linkableWorldsOf(placeWorlds, worldById);
}
