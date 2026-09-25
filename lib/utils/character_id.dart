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

/// Group-member store key. Empty [CharacterCard.imagePath] falls back
/// to [CharacterCard.dbId] (the member UUID) so Needs/trust match the
/// engine. Tabs must use this — `stableGroupId` alone keys by name.
String groupMemberStoreId(CharacterCard card) {
  final path = card.imagePath;
  if (path == null || path.isEmpty) {
    final id = card.dbId;
    if (id != null && id.isNotEmpty) return id;
  }
  return card.stableGroupId;
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
