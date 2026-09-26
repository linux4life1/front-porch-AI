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

import 'package:path/path.dart' as p;
import 'package:front_porch_ai/models/models.dart';

/// The stable-id derivation on its own, for callers that have the raw fields
/// but no [CharacterCard] — the database cleanup resolves it straight from
/// `characters.image_path` / `characters.name` rows. Keeping ONE
/// implementation matters: a second copy that drifted would make the cleanup
/// disagree with the app about which rows belong to a live character, and
/// "doesn't belong to anyone" is a DELETE.
String stableGroupIdFrom(String? imagePath, String name) {
  if (imagePath != null && imagePath.isNotEmpty) {
    return p.basenameWithoutExtension(imagePath);
  }

  // Rare fallback for characters that have never had an image file.
  return name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
}

/// Group-member store key for realism, needs, openings, posture,
/// Group Settings, and seeds.
///
/// UUID-first: [CharacterCard.dbId] / `GroupMember.id` when the member
/// has one. [CharacterCard.stableGroupId] only for legacy members with
/// no UUID (empty image path used to key by name).
String groupMemberStoreId(CharacterCard card) {
  final id = card.dbId;
  if (id != null && id.isNotEmpty) return id;
  return card.stableGroupId;
}

/// Move a member's legacy [CharacterCard.stableGroupId] entry onto
/// [groupMemberStoreId] when the dest key is absent. If both exist,
/// drop the legacy key. Never keeps both. Idempotent. Returns true
/// when [store] was mutated.
bool migrateGroupStoreKeys<T>(
  Map<String, T> store,
  Iterable<CharacterCard> members,
) {
  var changed = false;
  for (final member in members) {
    final dest = groupMemberStoreId(member);
    final legacy = member.stableGroupId;
    if (dest == legacy) continue;
    if (!store.containsKey(legacy)) continue;
    final moved = store.remove(legacy);
    if (!store.containsKey(dest) && moved is T) {
      store[dest] = moved;
    }
    changed = true;
  }
  return changed;
}

/// Legacy name/stableGroupId → UUID for members that have a dbId.
Map<String, String> groupMemberLegacyIdMap(Iterable<CharacterCard> members) {
  final map = <String, String>{};
  for (final member in members) {
    final dest = groupMemberStoreId(member);
    if (dest != member.stableGroupId) {
      map[member.stableGroupId] = dest;
    }
  }
  return map;
}

extension StableGroupId on CharacterCard {
  /// The canonical stable identifier for *singular/library* CharacterCards only.
  ///
  /// Used for library lookups, 1:1 chat keys, and (for backward compat in some
  /// cross-cutting utilities) certain non-group paths.
  ///
  /// **Group members are fully decoupled** — they use their own UUID (GroupMember.id)
  /// for all per-member realism, prompts, objectives, RAG, etc. Never derive group
  /// membership or keys from stableGroupId or characterIds.
  ///
  /// This value is **always** derived from the character's image filename
  /// (basename without extension). It is the portable, round-trippable ID
  /// that survives export, import, and duplication for library characters.
  ///
  /// Do **not** use `dbId` for any of the above — it is an internal
  /// database surrogate key and is not stable across devices or imports.
  String get stableGroupId => stableGroupIdFrom(imagePath, name);
}
