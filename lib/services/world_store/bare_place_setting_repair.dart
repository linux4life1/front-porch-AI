// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Older libraries could link a character or group to a bare place inside a
// world. Seeding filed a place that inherits its climate as Lore, so those
// chats started with no Setting and no weather. Once per library, the first
// such place in a Setting-less chat becomes its Setting. Stored character
// and group links are never rewritten.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_repository.dart';

const _repairPrefKey = 'gave_bare_place_chats_a_setting_v1';

/// A Setting the user clears afterwards stays cleared: this runs once.
Future<void> repairBarePlaceSettings(
  WorldRepository repo,
  AppDatabase db,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_repairPrefKey) == true) return;
    var repaired = 0;
    for (final chatId in await db.chatIdsWithoutSetting()) {
      final slots = await repo.getChatWorldAttachments(chatId);
      final place = slots.loreIds
          .where((id) => _promotableToSetting(id, repo))
          .firstOrNull;
      if (place == null) continue;
      await repo.setChatWorldAttachments(
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
  } catch (e) {
    debugPrint('[Worlds] bare place Setting repair skipped: $e');
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
